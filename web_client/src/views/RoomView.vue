<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch, nextTick } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api, danmakuWsUrl, onUnauthorized } from '../api/client'
import type { DanmakuMessage, RoomDetail, StreamInfo, QualityInfo } from '../api/types'
import { formatOnline, platformMeta } from '../platforms'
import { useFavorites } from '../stores/favorites'
import { settings } from '../stores/settings'
import VideoPlayer from '../components/VideoPlayer.vue'
import DanmakuOverlay from '../components/DanmakuOverlay.vue'

const route = useRoute()
const router = useRouter()
const favorites = useFavorites()
const meta = computed(() => platformMeta(route.params.platform as string))
const roomId = computed(() => route.params.roomId as string)
const platform = computed(() => route.params.platform as string)

const detail = ref<RoomDetail | null>(null)
const stream = ref<StreamInfo | null>(null)
const qualities = ref<QualityInfo[]>([])
const currentQuality = ref(settings.defaultQuality)
const loading = ref(true)
const detailError = ref('')
const streamError = ref('')
const refetchCount = ref(0)
const isLive = computed(() => detail.value?.status ?? false)
const isFavorite = computed(() =>
  favorites.has(platform.value, roomId.value),
)

// 弹幕
const overlayRef = ref<InstanceType<typeof DanmakuOverlay> | null>(null)
const playerRef = ref<InstanceType<typeof VideoPlayer> | null>(null)
const selectedLine = ref(0)
// 当前播放线路（用于刷新后恢复卡住前的线路）
const pendingLine = ref<{ line: number; viaProxy: boolean } | null>(null)

function selectLine(i: number): void {
  selectedLine.value = i
  pendingLine.value = { line: i, viaProxy: false }
  playerRef.value?.playLine(i)
}

function onLineChanged(line: number, viaProxy: boolean): void {
  if (line >= 0) {
    selectedLine.value = line
    pendingLine.value = { line, viaProxy }
  }
}
const chatList = ref<DanmakuMessage[]>([])
const chatEl = ref<HTMLElement | null>(null)
const wsState = ref<'connecting' | 'open' | 'closed'>('connecting')
let ws: WebSocket | null = null
let reconnectTimer: number | null = null
let reconnectDelay = 1000
let closedByUs = false

const scList = computed(() =>
  chatList.value.filter((m) => m.type === 'superChat') as Extract<
    DanmakuMessage,
    { type: 'superChat' }
  >[],
)

// ---------------------------------------------------------------------------
// 数据加载
// ---------------------------------------------------------------------------

async function loadDetail(): Promise<void> {
  loading.value = true
  detailError.value = ''
  try {
    detail.value = await api.room(platform.value, roomId.value, true)
    if (isLive.value) {
      await loadStream(true)
      connectWs()
    } else {
      stream.value = null
    }
  } catch (e) {
    detailError.value = (e as Error).message
  } finally {
    loading.value = false
  }
}

// 房间画质记忆：刷新/重连后保持卡住前的画质；设置里的画质仅首次进入生效
const QUALITY_MEM_KEY = 'sl_room_quality'
function loadQualityMemory(): Record<string, number> {
  try {
    return JSON.parse(localStorage.getItem(QUALITY_MEM_KEY) || '{}')
  } catch {
    return {}
  }
}
function saveQualityMemory(index: number): void {
  try {
    const mem = loadQualityMemory()
    mem[`${platform.value}::${roomId.value}`] = index
    localStorage.setItem(QUALITY_MEM_KEY, JSON.stringify(mem))
  } catch {
    /* ignore */
  }
}

async function loadStream(resetQuality = false): Promise<void> {
  streamError.value = ''
  try {
    if (resetQuality) {
      const q = await api.qualities(platform.value, roomId.value)
      qualities.value = q.qualities
      // 优先使用本房间上次使用的画质；没有记忆时才用设置里的默认画质
      const mem = loadQualityMemory()[`${platform.value}::${roomId.value}`]
      const prefer = mem ?? settings.defaultQuality
      currentQuality.value = q.qualities.some((x) => x.index === prefer)
        ? prefer
        : 0
    }
    stream.value = await api.stream(
      platform.value,
      roomId.value,
      currentQuality.value,
      settings.proxyMode === 'proxy' ? '1' : settings.proxyMode === 'direct' ? '0' : 'auto',
    )
    selectedLine.value = pendingLine.value?.line ?? 0
    saveQualityMemory(currentQuality.value)
  } catch (e) {
    streamError.value = (e as Error).message
    stream.value = null
  }
}

function selectQuality(index: number): void {
  currentQuality.value = index
  pendingLine.value = null
  void loadStream(false)
}

function onRefetch(): void {
  refetchCount.value++
  if (refetchCount.value <= 8) {
    void loadStream(false)
  }
}

// ---------------------------------------------------------------------------
// 弹幕 WebSocket
// ---------------------------------------------------------------------------

function connectWs(): void {
  closedByUs = false
  cleanupWs()
  wsState.value = 'connecting'
  try {
    ws = new WebSocket(danmakuWsUrl(platform.value, roomId.value))
  } catch {
    scheduleReconnect()
    return
  }
  ws.onopen = () => {
    wsState.value = 'open'
    reconnectDelay = 1000
    // 心跳
  }
  ws.onmessage = (ev) => {
    let msg: DanmakuMessage
    try {
      msg = JSON.parse(ev.data as string) as DanmakuMessage
    } catch {
      return
    }
    onDanmakuMessage(msg)
  }
  ws.onclose = () => {
    wsState.value = 'closed'
    if (!closedByUs) scheduleReconnect()
  }
  ws.onerror = () => {
    wsState.value = 'closed'
  }
}

const heartbeat = setInterval(() => {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: 'ping' }))
  }
}, 25000)

function scheduleReconnect(): void {
  if (closedByUs || reconnectTimer !== null) return
  reconnectTimer = window.setTimeout(() => {
    reconnectTimer = null
    reconnectDelay = Math.min(reconnectDelay * 2, 15000)
    connectWs()
  }, reconnectDelay)
}

function cleanupWs(): void {
  if (ws) {
    ws.onclose = null
    ws.onerror = null
    ws.onmessage = null
    try {
      ws.close()
    } catch {
      /* ignore */
    }
    ws = null
  }
}

function onDanmakuMessage(msg: DanmakuMessage): void {
  switch (msg.type) {
    case 'chat':
      chatList.value.push(msg)
      if (chatList.value.length > 150) {
        chatList.value = chatList.value.slice(-150)
      }
      overlayRef.value?.push(msg.text, msg.color)
      void scrollChat()
      break
    case 'online':
      if (detail.value) detail.value = { ...detail.value, online: msg.online }
      break
    case 'superChat':
      chatList.value.push(msg)
      void scrollChat()
      break
    case 'gift':
      chatList.value.push(msg)
      void scrollChat()
      break
    case 'error':
    case 'reconnecting':
      chatList.value.push({
        type: 'reconnecting',
        message: msg.message,
      } as DanmakuMessage)
      void scrollChat()
      break
    default:
      break
  }
}

async function scrollChat(): Promise<void> {
  await nextTick()
  const el = chatEl.value
  if (!el) return
  const nearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 80
  if (nearBottom) {
    el.scrollTop = el.scrollHeight
  }
}

// ---------------------------------------------------------------------------
// 生命周期
// ---------------------------------------------------------------------------

onMounted(() => {
  void loadDetail()
})

onBeforeUnmount(() => {
  closedByUs = true
  cleanupWs()
  if (reconnectTimer !== null) clearTimeout(reconnectTimer)
})

onUnauthorized(() => {
  // 令牌失效：跳转配对页
  router.replace('/pair')
})

watch(
  () => settings.danmaku.enabled,
  () => {
    // 无需处理，overlay 自行响应
  },
)

function goBack(): void {
  if (window.history.length > 1) router.back()
  else router.replace('/')
}

function toggleFavorite(): void {
  if (!detail.value) return
  favorites.toggle(detail.value)
}
</script>

<template>
  <div class="room-page" :class="{ fullscreen: false }">
    <!-- 顶栏 -->
    <div class="top-bar">
      <button class="back" @click="goBack" aria-label="返回">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <path d="m15 5-7 7 7 7" />
        </svg>
      </button>
      <div class="top-title" v-if="detail">{{ detail.title }}</div>
      <div class="top-title" v-else>直播间</div>
    </div>

    <div v-if="loading" class="loading-box page-pad">
      <div class="spinner"></div>
      正在获取直播间信息…
    </div>

    <div v-else-if="detailError" class="error-box page-pad">
      {{ detailError }}
      <div class="retry"><button class="btn" @click="loadDetail">重试</button></div>
    </div>

    <div v-else-if="detail" class="room-body">
      <div class="player-col">
        <VideoPlayer
          ref="playerRef"
          :stream="stream"
          :autoplay="settings.autoplay"
          :initial-line="pendingLine"
          :current-quality="currentQuality"
          @select-quality="selectQuality"
          @refetch="onRefetch"
          @line-changed="onLineChanged"
        >
          <DanmakuOverlay
            ref="overlayRef"
            :enabled="settings.danmaku.enabled"
          />
        </VideoPlayer>

        <!-- 信息与控制 -->
        <div class="room-bar">
          <img class="avatar" :src="detail.userAvatar" />
          <div class="room-info">
            <div class="room-title-line">
              <span class="plat-badge" :style="{ background: meta.gradient }">{{ meta.short }}</span>
              <span class="room-title">{{ detail.title }}</span>
            </div>
            <div class="room-sub">
              <span class="anchor-name">{{ detail.userName }}</span>
              <span v-if="detail.online > 0" class="online-dot">· {{ formatOnline(detail.online) }} 人观看</span>
              <span v-if="detail.categoryName" class="cat">· {{ detail.categoryName }}</span>
              <span v-if="wsState !== 'open' && isLive" class="ws-hint">
                · 弹幕{{ wsState === 'connecting' ? '连接中' : '已断开' }}
              </span>
            </div>
          </div>
          <button
            class="fav-toggle"
            :class="{ active: isFavorite }"
            @click="toggleFavorite"
            :aria-label="isFavorite ? '取消收藏' : '收藏'"
          >
            <svg viewBox="0 0 24 24" :fill="isFavorite ? 'currentColor' : 'none'" stroke="currentColor" stroke-width="2">
              <path d="m12 3 2.7 5.8 6.3.8-4.6 4.4 1.2 6.2L12 17.2 6.4 20.2l1.2-6.2L3 9.6l6.3-.8z" />
            </svg>
          </button>
        </div>

        <!-- 画质 / 线路 / 弹幕开关 -->
        <div v-if="isLive && qualities.length" class="quality-bar">
          <div class="quality-chips">
            <button
              v-for="q in qualities"
              :key="q.index"
              class="chip"
              :class="{ active: currentQuality === q.index }"
              @click="selectQuality(q.index)"
            >
              {{ q.quality }}
            </button>
          </div>
          <div class="bar-actions">
            <button
              class="chip"
              :class="{ active: settings.danmaku.enabled }"
              @click="settings.danmaku.enabled = !settings.danmaku.enabled"
            >
              弹幕 {{ settings.danmaku.enabled ? '开' : '关' }}
            </button>
          </div>
        </div>


        <!-- 手动选线路 -->
        <div v-if="isLive && stream && stream.urls.length > 1" class="quality-bar line-bar">
          <span class="line-label">线路</span>
          <div class="quality-chips">
            <button
              v-for="(u, i) in stream.urls"
              :key="i"
              class="chip"
              :class="{ active: selectedLine === i }"
              @click="selectLine(i)"
            >
              {{ i + 1 }}·{{ u.format.toUpperCase() }}{{ u.proxy ? '' : '' }}
            </button>
          </div>
        </div>

        <div v-if="!isLive" class="offline-card card">
          <div class="offline-icon">💤</div>
          <div class="offline-text">主播当前未开播</div>
          <a class="btn secondary" :href="detail.url" target="_blank" rel="noopener">
            打开平台页面
          </a>
        </div>

        <div v-if="streamError && isLive" class="error-box">
          获取播放地址失败：{{ streamError }}
          <div class="retry">
            <button class="btn" @click="loadStream(false)">重试</button>
          </div>
        </div>

        <div v-if="detail.introduction" class="intro card">
          <div class="intro-title">房间介绍</div>
          <div class="intro-body">{{ detail.introduction }}</div>
        </div>
      </div>

      <!-- 聊天面板 -->
      <div class="chat-col">
        <div class="chat-header">
          <span>弹幕互动</span>
          <span class="text-tertiary sc-count" v-if="scList.length">
            SC {{ scList.length }}
          </span>
        </div>
        <div ref="chatEl" class="chat-list">
          <div
            v-for="(m, i) in chatList"
            :key="i"
            class="chat-item"
            :class="'kind-' + m.type"
          >
            <template v-if="m.type === 'chat'">
              <span class="chat-user">{{ m.user }}：</span>
              <span class="chat-text" :style="{ color: m.color && m.color !== '#ffffff' ? m.color : undefined }">
                <template v-if="settings.danmaku.emoji && m.spans && m.spans.length">
                  <template v-for="(sp, si) in m.spans" :key="si">
                    <img v-if="sp.img" class="chat-emoji" :src="sp.img" referrerpolicy="no-referrer" />
                    <template v-else>{{ sp.text }}</template>
                  </template>
                </template>
                <template v-else>{{ m.text }}</template>
              </span>
            </template>
            <template v-else-if="m.type === 'gift'">
              🎁 <span class="chat-user">{{ m.user }}</span>
              <span class="chat-text"> {{ m.text }}</span>
            </template>
            <template v-else-if="m.type === 'superChat'">
              <div class="sc-card" :style="{ background: m.backgroundColor, color: '#fff' }">
                <div class="sc-top">
                  <span class="sc-user">{{ m.user }}</span>
                  <span class="sc-price">¥{{ m.price }}</span>
                </div>
                <div class="sc-msg">{{ m.message }}</div>
              </div>
            </template>
            <template v-else-if="m.type === 'reconnecting' || m.type === 'error'">
              <span class="sys-msg">— {{ m.message }} —</span>
            </template>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.room-page {
  min-height: 100vh;
  background: var(--bg);
}
.page-pad {
  padding-top: 70px;
}
.top-bar {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  height: 52px;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 0 12px;
  background: var(--bg-elevated);
  border-bottom: 1px solid var(--border);
  z-index: 50;
}
.back {
  width: 38px;
  height: 38px;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 10px;
}
.back svg {
  width: 22px;
  height: 22px;
}
.top-title {
  font-size: 15px;
  font-weight: 600;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  flex: 1;
}
.room-body {
  padding-top: 52px;
}
@media (min-width: 960px) {
  .room-body {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 340px;
    align-items: start;
  }
  .chat-col {
    height: calc(100vh - 52px);
    position: sticky;
    top: 52px;
    border-left: 1px solid var(--border);
  }
}
.player-col {
  min-width: 0;
}
.room-bar {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 14px;
  background: var(--bg-card);
}
.avatar {
  width: 44px;
  height: 44px;
  border-radius: 50%;
  object-fit: cover;
  flex-shrink: 0;
  background: var(--bg-hover);
}
.room-info {
  flex: 1;
  min-width: 0;
}
.room-title-line {
  display: flex;
  align-items: center;
  gap: 8px;
}
.plat-badge {
  flex-shrink: 0;
  width: 22px;
  height: 22px;
  border-radius: 6px;
  color: #fff;
  font-size: 12px;
  font-weight: 700;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}
.room-title {
  font-size: 15px;
  font-weight: 600;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.room-sub {
  margin-top: 4px;
  font-size: 12.5px;
  color: var(--text-tertiary);
  display: flex;
  gap: 4px;
  flex-wrap: wrap;
}
.anchor-name {
  color: var(--accent);
  font-weight: 600;
}
.ws-hint {
  color: var(--text-tertiary);
}
.fav-toggle {
  width: 40px;
  height: 40px;
  border-radius: 12px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-tertiary);
  background: var(--bg-hover);
}
.fav-toggle svg {
  width: 20px;
  height: 20px;
}
.fav-toggle.active {
  color: #ffb300;
}
.quality-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  padding: 10px 14px;
  background: var(--bg-card);
  border-top: 1px solid var(--border);
  overflow-x: auto;
}
.line-bar {
  justify-content: flex-start;
  padding-top: 0;
}
.line-label {
  flex-shrink: 0;
  font-size: 13px;
  color: var(--text-tertiary);
}
.dm-panel {
  margin: 0 14px 12px;
  padding: 14px 16px;
}
.chat-emoji {
  display: inline-block;
  height: 1.3em;
  vertical-align: -0.3em;
  margin: 0 2px;
}
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.2s;
}
.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}
.quality-chips {
  display: flex;
  gap: 8px;
  overflow-x: auto;
}
.bar-actions {
  display: flex;
  gap: 8px;
}
.offline-card {
  margin: 14px;
  padding: 40px 20px;
  text-align: center;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12px;
}
.offline-icon {
  font-size: 40px;
}
.offline-text {
  font-size: 15px;
  color: var(--text-secondary);
}
.intro {
  margin: 14px;
  padding: 14px 16px;
}
.intro-title {
  font-weight: 700;
  font-size: 14px;
  margin-bottom: 8px;
}
.intro-body {
  font-size: 13.5px;
  color: var(--text-secondary);
  white-space: pre-wrap;
  word-break: break-word;
  line-height: 1.6;
}
.chat-col {
  display: flex;
  flex-direction: column;
  background: var(--bg-card);
  max-height: 320px;
  margin: 0;
}
@media (min-width: 960px) {
  .chat-col {
    max-height: none;
    margin: 0;
  }
}
.chat-header {
  padding: 12px 16px;
  font-weight: 700;
  font-size: 14px;
  border-bottom: 1px solid var(--border);
  display: flex;
  justify-content: space-between;
}
.chat-list {
  flex: 1;
  overflow-y: auto;
  padding: 10px 14px;
  display: flex;
  flex-direction: column;
  gap: 8px;
  min-height: 180px;
}
.chat-item {
  font-size: 13.5px;
  line-height: 1.5;
  word-break: break-word;
}
.chat-user {
  color: var(--accent);
  font-weight: 600;
}
.chat-text {
  color: var(--text);
}
.sys-msg {
  color: var(--text-tertiary);
  font-size: 12px;
}
.sc-card {
  border-radius: 10px;
  padding: 10px 12px;
  margin: 4px 0;
}
.sc-top {
  display: flex;
  justify-content: space-between;
  font-weight: 700;
  font-size: 13px;
}
.sc-msg {
  margin-top: 4px;
  font-size: 13px;
}
</style>
