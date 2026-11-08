<script setup lang="ts">
defineOptions({ name: 'FavoritesView' })
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { api } from '../api/client'
import type { RoomItem } from '../api/types'
import RoomCard from '../components/RoomCard.vue'
import { formatTime } from '../time'
import { useFavorites } from '../stores/favorites'
import type { FavoriteItem } from '../stores/favorites'
import { settings, type FavoritesLayout } from '../stores/settings'
import { platformMeta, PLATFORMS } from '../platforms'

const favorites = useFavorites()
const router = useRouter()
const msg = ref('')
const importing = ref(false)
const fileInput = ref<HTMLInputElement | null>(null)

function asRoom(f: FavoriteItem): RoomItem {
  return {
    platform: f.platform as RoomItem['platform'],
    roomId: f.roomId,
    title: f.title,
    userName: f.userName,
    cover: f.cover,
    online: 0,
  }
}

function openRoom(f: FavoriteItem): void {
  router.push(`/room/${f.platform}/${f.roomId}`)
}

function platformName(id: string): string {
  return PLATFORMS.find((p) => p.id === id)?.name ?? id
}

// 封面缩略图两级回退
function thumbFallback(e: Event): void {
  const img = e.target as HTMLImageElement
  const raw = img.getAttribute('src') ?? ''
  if (!img.dataset.stripped && /@\d+w(\.\w+)?$/.test(raw)) {
    img.dataset.stripped = '1'
    img.src = raw.replace(/@\d+w(\.\w+)?$/, '')
    return
  }
  if (!img.dataset.fallback) {
    img.dataset.fallback = '1'
    img.src =
      'data:image/svg+xml;utf8,' +
      encodeURIComponent(
        `<svg xmlns="http://www.w3.org/2000/svg" width="96" height="54"><rect width="96" height="54" fill="#2b3038"/></svg>`,
      )
  }
}

// 导出收藏为 JSON 文件
function exportJson(): void {
  const data = JSON.stringify(favorites.state.items, null, 2)
  const blob = new Blob([data], { type: 'application/json' })
  const a = document.createElement('a')
  a.href = URL.createObjectURL(blob)
  a.download = `simple-live-favorites-${new Date().toISOString().slice(0, 10)}.json`
  a.click()
  URL.revokeObjectURL(a.href)
  msg.value = '已导出收藏文件'
}

// 导入 JSON 文件（合并，跳过重复）
function onImportFile(e: Event): void {
  const input = e.target as HTMLInputElement
  const file = input.files?.[0]
  if (!file) return
  const reader = new FileReader()
  reader.onload = () => {
    try {
      const list = JSON.parse(reader.result as string) as FavoriteItem[]
      if (!Array.isArray(list)) throw new Error('格式错误')
      let added = 0
      for (const item of list) {
        if (!item.platform || !item.roomId) continue
        if (favorites.has(item.platform, item.roomId)) continue
        favorites.addFromItem({
          platform: item.platform as RoomItem['platform'],
          roomId: item.roomId,
          title: item.title ?? '',
          userName: item.userName ?? '',
          cover: item.cover ?? '',
          online: 0,
        })
        added++
      }
      msg.value = `导入完成：新增 ${added} 条`
    } catch (err) {
      msg.value = `导入失败：${(err as Error).message}`
    }
    input.value = ''
  }
  reader.readAsText(file)
}

// 从手机 App 的关注列表同步导入
async function syncFromPhone(): Promise<void> {
  importing.value = true
  msg.value = ''
  try {
    const follows = await api.follows()
    let added = 0
    for (const f of follows) {
      if (!f.siteId || !f.roomId) continue
      if (favorites.has(f.siteId, f.roomId)) continue
      favorites.addFromItem({
        platform: f.siteId as RoomItem['platform'],
        roomId: f.roomId,
        title: f.roomTitle || f.userName,
        userName: f.userName,
        cover: f.roomCover || f.face,
        online: 0,
      })
      added++
    }
    msg.value = follows.length === 0
      ? '手机关注列表为空'
      : `同步完成：手机 ${follows.length} 条，新增 ${added} 条`
  } catch (e) {
    msg.value = `同步失败：${(e as Error).message}`
  } finally {
    importing.value = false
  }
}
</script>

<template>
  <div class="page">
    <h2 class="section-title">我的收藏</h2>

    <div class="toolbar">
      <button class="btn secondary" @click="exportJson">导出文件</button>
      <button class="btn secondary" @click="fileInput?.click()">导入文件</button>
      <button class="btn" :disabled="importing" @click="syncFromPhone">
        {{ importing ? '同步中…' : '导入手机关注' }}
      </button>
      <div class="spacer"></div>
      <!-- 布局切换 -->
      <div class="seg">
        <button
          class="seg-item"
          :class="{ active: settings.favoritesLayout === 'list' }"
          @click="settings.favoritesLayout = 'list'"
        >
          ☰ 列表
        </button>
        <button
          class="seg-item"
          :class="{ active: settings.favoritesLayout === 'card' }"
          @click="settings.favoritesLayout = 'card'"
        >
          ▦ 卡片
        </button>
      </div>
      <input
        ref="fileInput"
        type="file"
        accept="application/json,.json"
        style="display: none"
        @change="onImportFile"
      />
    </div>
    <div v-if="msg" class="msg">{{ msg }}</div>

    <div v-if="favorites.state.items.length === 0" class="empty">
      还没有收藏，去直播间点个 ☆ 吧
    </div>

    <!-- 紧凑列表布局 -->
    <div v-else-if="settings.favoritesLayout === 'list'" class="fav-list">
      <div
        v-for="f in favorites.state.items"
        :key="`${f.platform}-${f.roomId}`"
        class="fav-compact card"
        @click="openRoom(f)"
      >
        <img
          class="fc-thumb"
          :src="f.cover"
          loading="lazy"
          referrerpolicy="no-referrer"
          @error="thumbFallback"
        />
        <span class="fc-plat" :style="{ background: platformMeta(f.platform).gradient }">
          {{ platformMeta(f.platform).short }}
        </span>
        <div class="fc-info">
          <div class="fc-title">{{ f.title || f.userName }}</div>
          <div class="fc-meta">
            {{ f.userName }} · {{ platformName(f.platform) }} · 收藏于 {{ formatTime(f.addedAt) }}
          </div>
        </div>
        <button
          class="fc-del"
          :aria-label="'取消收藏 ' + f.title"
          @click.stop="favorites.remove(f.platform, f.roomId)"
        >
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M18 6 6 18M6 6l12 12" />
          </svg>
        </button>
      </div>
    </div>

    <!-- 卡片网格布局 -->
    <div v-else class="fav-grid">
      <RoomCard
        v-for="f in favorites.state.items"
        :key="`${f.platform}-${f.roomId}`"
        :room="asRoom(f)"
      />
    </div>
  </div>
</template>

<style scoped>
.toolbar {
  display: flex;
  gap: 10px;
  margin-bottom: 12px;
  flex-wrap: wrap;
  align-items: center;
}
.spacer {
  flex: 1;
}
.seg {
  display: inline-flex;
  background: var(--bg-hover);
  border-radius: 10px;
  padding: 3px;
  gap: 2px;
}
.seg-item {
  padding: 7px 14px;
  border-radius: 8px;
  font-size: 13px;
  color: var(--text-secondary);
}
.seg-item.active {
  background: var(--accent);
  color: #fff;
  font-weight: 600;
}
.msg {
  font-size: 13px;
  color: var(--accent);
  margin-bottom: 12px;
}

/* 紧凑列表：一屏可显示更多 */
.fav-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.fav-compact {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 8px 12px;
  cursor: pointer;
  min-height: 64px;
}
.fc-thumb {
  width: 96px;
  height: 54px;
  border-radius: 8px;
  object-fit: cover;
  flex-shrink: 0;
  background: #2b3038;
}
.fc-plat {
  flex-shrink: 0;
  width: 20px;
  height: 20px;
  border-radius: 6px;
  color: #fff;
  font-size: 11px;
  font-weight: 700;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}
.fc-info {
  flex: 1;
  min-width: 0;
}
.fc-title {
  font-size: 14px;
  font-weight: 600;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.fc-meta {
  margin-top: 3px;
  font-size: 12px;
  color: var(--text-tertiary);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.fc-del {
  flex-shrink: 0;
  width: 34px;
  height: 34px;
  border-radius: 10px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-tertiary);
  background: var(--bg-hover);
}
.fc-del svg {
  width: 16px;
  height: 16px;
}
.fc-del:active {
  color: var(--danger);
}

/* 卡片网格布局 */
.fav-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
  gap: 14px;
}
@media (max-width: 500px) {
  .fav-grid {
    grid-template-columns: repeat(2, 1fr);
    gap: 10px;
  }
}
.btn.small {
  padding: 8px 14px;
  font-size: 13px;
}
</style>
