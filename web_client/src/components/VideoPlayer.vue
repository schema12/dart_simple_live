<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import type Hls from 'hls.js'
import mpegts from 'mpegts.js'
import type { StreamInfo, StreamUrl } from '../api/types'
import { withToken } from '../api/client'
import { settings } from '../stores/settings'

/**
 * 播放器：
 * - HLS：Safari/iPad 优先原生播放，其它浏览器用 hls.js；
 * - FLV：mpegts.js（MSE）；
 * - 线路与直连/代理回退：auto 模式先直连后代理，全部失败通知父级重新解析。
 */
const props = defineProps<{
  stream: StreamInfo | null
  autoplay: boolean
  /** 重取流后希望恢复的线路（url 索引 + 是否代理），用于保持卡住前的线路 */
  initialLine?: { line: number; viaProxy: boolean } | null
}>()

const emit = defineEmits<{
  (e: 'selectQuality', index: number): void
  (e: 'refetch'): void
  (e: 'playing'): void
  (e: 'lineChanged', line: number, viaProxy: boolean): void
}>()

const videoEl = ref<HTMLVideoElement | null>(null)
const wrapperEl = ref<HTMLDivElement | null>(null)

type PlayerState = 'idle' | 'loading' | 'playing' | 'paused' | 'error'
const state = ref<PlayerState>('idle')
const errorMsg = ref('')
const muted = ref(false)
const needGesture = ref(false)
const isFullscreen = ref(false)
const showControls = ref(true)
const controlsTimer = ref<number | null>(null)

interface Attempt {
  label: string
  kind: 'direct' | 'proxy'
  url: string
  format: StreamUrl['format']
}

const attempts = ref<Attempt[]>([])
const attemptIndex = ref(0)
const lineOfAttempt = ref<number[]>([])
const hadPlaying = ref(false)

let hls: Hls | null = null
let mpegtsPlayer: mpegts.Player | null = null
let watchdog: number | null = null
let refetchTimer: number | null = null

const currentAttempt = computed(() => attempts.value[attemptIndex.value] ?? null)

// ---------------------------------------------------------------------------
// 尝试序列构建
// ---------------------------------------------------------------------------

function buildAttempts(stream: StreamInfo): Attempt[] {
  const mode = settings.proxyMode
  const list: Attempt[] = []
  const directAllowed = mode === 'auto' || mode === 'direct'
  const proxyAllowed = mode === 'auto' || mode === 'proxy'
  const direct: Attempt[] = []
  const proxied: Attempt[] = []
  stream.urls.forEach((u, i) => {
    if (directAllowed) {
      direct.push({
        label: `直连 ${i + 1}`,
        kind: 'direct',
        url: u.url,
        format: u.format,
      })
    }
    if (proxyAllowed && u.proxy) {
      proxied.push({
        label: `代理 ${i + 1}`,
        kind: 'proxy',
        url: withToken(u.proxy),
        format: u.format,
      })
    }
  })
  // auto：先直连后代理；proxy：仅代理；direct：仅直连
  return [...direct, ...proxied]
}

function resetAndPlay(stream: StreamInfo): void {
  destroyEngine()
  attempts.value = buildAttempts(stream)
  // 记录每个尝试对应的线路（url）索引，供手动选线路使用
  const n = stream.urls.length
  const directAllowed = settings.proxyMode !== 'proxy'
  const proxyAllowed = settings.proxyMode !== 'direct' && attempts.value.some((a) => a.kind === 'proxy')
  const lines: number[] = []
  if (directAllowed) {
    for (let i = 0; i < n; i++) lines.push(i)
  }
  if (proxyAllowed && stream.urls.some((u) => u.proxy)) {
    for (let i = 0; i < n; i++) lines.push(i)
  }
  lineOfAttempt.value = lines
  attemptIndex.value = 0
  // 恢复到卡住前的线路（刷新/重取流场景）
  if (props.initialLine && props.initialLine.line >= 0) {
    const target = lines.findIndex(
      (l) => l === props.initialLine!.line,
    )
    if (target >= 0) {
      const attempt = attempts.value[target]
      if (attempt && (attempt.kind === 'proxy') === props.initialLine.viaProxy) {
        attemptIndex.value = target
      }
    }
  }
  hadPlaying.value = false
  needGesture.value = false
  errorMsg.value = ''
  if (attempts.value.length === 0) {
    state.value = 'error'
    errorMsg.value = '没有可用的播放地址'
    scheduleRefetch(3000)
    return
  }
  state.value = 'loading'
  void playAttempt()
}

/** 手动选择线路（url 索引）：优先直连尝试，无直连时用代理尝试。 */
function playLine(urlIndex: number): void {
  const target = lineOfAttempt.value.findIndex((l) => l === urlIndex)
  if (target < 0 || target >= attempts.value.length) return
  attemptIndex.value = target
  hadPlaying.value = false
  needGesture.value = false
  errorMsg.value = ''
  state.value = 'loading'
  void playAttempt()
}

defineExpose({ playLine })

// ---------------------------------------------------------------------------
// 引擎
// ---------------------------------------------------------------------------

function supportsNativeHls(): boolean {
  const video = document.createElement('video')
  const can = video.canPlayType('application/vnd.apple.mpegurl')
  return can === 'probably' || can === 'maybe'
}

async function playAttempt(): Promise<void> {
  const video = videoEl.value
  const attempt = currentAttempt.value
  if (!video || !attempt) return
  destroyEngine()
  emit(
    'lineChanged',
    lineOfAttempt.value[attemptIndex.value] ?? -1,
    attempt.kind === 'proxy',
  )
  state.value = 'loading'
  startWatchdog(15000)

  try {
    if (attempt.format === 'hls') {
      if (supportsNativeHls()) {
        // 原生 HLS：Safari 直接播，不走 MSE，也不受 CORS 限制
        video.src = attempt.url
        await tryPlay()
        return
      }
      await playHlsJs(attempt.url)
      return
    }
    if (attempt.format === 'flv' || attempt.format === 'ts') {
      if (mpegts.getFeatureList().mseLivePlayback) {
        playMpegts(attempt.url, attempt.format === 'ts' ? 'mpegts' : 'flv')
        return
      }
      // 无 MSE（旧 iOS）：直接失败进入下一尝试
      throw new Error('当前浏览器不支持 FLV 播放（无 MSE）')
    }
    // mp4 / unknown：原生直接播
    video.src = attempt.url
    await tryPlay()
  } catch (e) {
    onAttemptFailed(e instanceof Error ? e.message : String(e))
  }
}

async function playHlsJs(url: string): Promise<void> {
  const video = videoEl.value
  if (!video) return
  const mod = await import('hls.js')
  const HlsCtor = mod.default
  if (!HlsCtor.isSupported()) {
    throw new Error('当前浏览器不支持 HLS MSE 播放')
  }
  hls = new HlsCtor({
    lowLatencyMode: false,
    liveSyncDurationCount: 3,
    maxBufferLength: 20,
    manifestLoadingTimeOut: 12000,
    manifestLoadingMaxRetry: 1,
    fragLoadingTimeOut: 20000,
    fragLoadingMaxRetry: 2,
  })
  hls.loadSource(url)
  hls.attachMedia(video)
  hls.on(HlsCtor.Events.MANIFEST_PARSED, () => {
    void tryPlay()
  })
  hls.on(HlsCtor.Events.ERROR, (_evt, data) => {
    if (!hls) return
    if (data.fatal) {
      onAttemptFailed(`HLS 错误: ${data.details}`)
    }
  })
}

function playMpegts(url: string, type: 'flv' | 'mpegts'): void {
  const video = videoEl.value
  if (!video) return
  mpegtsPlayer = mpegts.createPlayer(
    {
      type,
      isLive: true,
      url,
    },
    {
      enableStashBuffer: false,
      lazyLoad: false,
      liveBufferLatencyChasing: true,
    },
  )
  mpegtsPlayer.attachMediaElement(video)
  mpegtsPlayer.load()
  mpegtsPlayer.on(mpegts.Events.ERROR, (err) => {
    onAttemptFailed(`播放器错误: ${err}`)
  })
  void tryPlay()
}

async function tryPlay(): Promise<void> {
  const video = videoEl.value
  if (!video) return
  try {
    if (props.autoplay) {
      await video.play()
    }
  } catch {
    // 浏览器限制：尝试静音自动播放
    try {
      muted.value = true
      video.muted = true
      await video.play()
      needGesture.value = true
    } catch {
      needGesture.value = true
      state.value = 'paused'
    }
  }
}

function startWatchdog(ms: number): void {
  clearWatchdog()
  watchdog = window.setTimeout(() => {
    if (state.value !== 'playing') {
      onAttemptFailed('加载超时')
    }
  }, ms)
}

function clearWatchdog(): void {
  if (watchdog !== null) {
    clearTimeout(watchdog)
    watchdog = null
  }
}

function scheduleRefetch(delay: number): void {
  if (refetchTimer !== null) return
  refetchTimer = window.setTimeout(() => {
    refetchTimer = null
    emit('refetch')
  }, delay)
}

function onAttemptFailed(reason: string): void {
  clearWatchdog()
  // 播放中断（此前成功播放过）→ 更可能是地址过期，直接让父级重新解析
  if (hadPlaying.value) {
    state.value = 'error'
    errorMsg.value = '直播流中断，正在重新获取地址…'
    scheduleRefetch(1200)
    return
  }
  if (attemptIndex.value < attempts.value.length - 1) {
    attemptIndex.value++
    void playAttempt()
  } else {
    state.value = 'error'
    errorMsg.value = `播放失败：${reason}`
    if (settings.autoRetry) {
      scheduleRefetch(4000)
    }
  }
}

// ---------------------------------------------------------------------------
// 卡顿看门狗：播放状态下画面停滞（FLV 直播流偶发断流）→ 自动重取当前线路
// ---------------------------------------------------------------------------
let stallTimer: number | null = null
let lastStallCheck = 0
let stallCount = 0

function startStallWatchdog(): void {
  stopStallWatchdog()
  lastStallCheck = 0
  stallTimer = window.setInterval(() => {
    const video = videoEl.value
    if (!video || state.value !== 'playing') return
    const now = video.currentTime
    if (lastStallCheck > 0 && Math.abs(now - lastStallCheck) < 0.15) {
      // 2 秒内画面没有前进 → 卡住
      stallCount++
      if (stallCount >= 2) {
        // 连续 2 次检测（约 6 秒）仍停滞 → 重取当前线路
        stallCount = 0
        hadPlaying.value = true
        onAttemptFailed('画面停滞')
        return
      }
    } else {
      stallCount = 0
    }
    lastStallCheck = now
  }, 2000)
}

function stopStallWatchdog(): void {
  if (stallTimer !== null) {
    clearInterval(stallTimer)
    stallTimer = null
  }
}

// ---------------------------------------------------------------------------
// 声音丢失检测（仅桌面 MSE 播放）：画面正常但持续静默 → 软刷新修复
// ---------------------------------------------------------------------------
let audioCtx: AudioContext | null = null
let audioAnalyser: AnalyserNode | null = null
let audioSource: MediaElementAudioSourceNode | null = null
let audioTimer: number | null = null
let silentSamples = 0

function trySetupAudioDetector(): void {
  // iOS/iPadOS Safari 的 WebAudio 对 MSE/HLS 支持不完整，仅桌面启用
  const isSafariLike = /^((?!chrome|android).)*safari/i.test(navigator.userAgent)
  if (isSafariLike) return
  const video = videoEl.value
  if (!video || audioCtx) return
  try {
    const Ctor =
      window.AudioContext ??
      (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext
    if (!Ctor) return
    audioCtx = new Ctor()
    audioSource = audioCtx.createMediaElementSource(video)
    audioAnalyser = audioCtx.createAnalyser()
    audioAnalyser.fftSize = 2048
    audioSource.connect(audioAnalyser)
    audioAnalyser.connect(audioCtx.destination)
    audioTimer = window.setInterval(() => {
      if (!audioAnalyser || !videoEl.value) return
      // 仅同源代理流启用：跨源直连流的 WebAudio 会被静音污染，检测无意义
      if (currentAttempt.value?.kind !== 'proxy') {
        silentSamples = 0
        return
      }
      if (state.value !== 'playing' || muted.value) {
        silentSamples = 0
        return
      }
      const buf = new Uint8Array(audioAnalyser.frequencyBinCount)
      audioAnalyser.getByteTimeDomainData(buf)
      let peak = 0
      for (let i = 0; i < buf.length; i++) {
        peak = Math.max(peak, Math.abs(buf[i] - 128))
      }
      // 视频在走、未静音，但音频持续 10 秒完全无声 → 判定声音丢失
      if (peak < 1) {
        silentSamples++
        if (silentSamples >= 5) {
          silentSamples = 0
          hadPlaying.value = true
          onAttemptFailed('声音丢失')
        }
      } else {
        silentSamples = 0
      }
    }, 2000)
  } catch {
    // 检测器失败不影响播放
  }
}

function destroyEngine(): void {
  clearWatchdog()
  stopStallWatchdog()
  if (hls) {
    try {
      hls.destroy()
    } catch {
      /* ignore */
    }
    hls = null
  }
  if (mpegtsPlayer) {
    try {
      mpegtsPlayer.pause()
      mpegtsPlayer.unload()
      mpegtsPlayer.detachMediaElement()
      mpegtsPlayer.destroy()
    } catch {
      /* ignore */
    }
    mpegtsPlayer = null
  }
  const video = videoEl.value
  if (video) {
    video.removeAttribute('src')
    try {
      video.load()
    } catch {
      /* ignore */
    }
  }
}

// ---------------------------------------------------------------------------
// 视频事件
// ---------------------------------------------------------------------------

function onPlaying(): void {
  state.value = 'playing'
  hadPlaying.value = true
  clearWatchdog()
  needGesture.value = false
  startStallWatchdog()
  trySetupAudioDetector()
  emit('playing')
}

function onPause(): void {
  if (state.value === 'playing') state.value = 'paused'
}

function onVideoError(): void {
  // 引擎内部已处理大部分错误；原生播放的错误走这里
  if (currentAttempt.value && (currentAttempt.value.format === 'hls' || currentAttempt.value.format === 'mp4' || currentAttempt.value.format === 'unknown')) {
    onAttemptFailed('视频加载失败')
  }
}

function togglePlay(): void {
  const video = videoEl.value
  if (!video) return
  if (video.paused) {
    void video.play()
  } else {
    video.pause()
  }
}

function unmute(): void {
  muted.value = false
  if (videoEl.value) videoEl.value.muted = false
  void videoEl.value?.play()
}

async function toggleFullscreen(): Promise<void> {
  const wrapper = wrapperEl.value
  const video = videoEl.value
  if (!wrapper || !video) return
  const doc = document as Document & { webkitFullscreenElement?: Element }
  const active = document.fullscreenElement || doc.webkitFullscreenElement
  try {
    if (active) {
      if (document.exitFullscreen) await document.exitFullscreen()
    } else if (wrapper.requestFullscreen) {
      await wrapper.requestFullscreen()
    } else {
      const v = video as HTMLVideoElement & { webkitEnterFullscreen?: () => void }
      v.webkitEnterFullscreen?.()
    }
  } catch {
    const v = video as HTMLVideoElement & { webkitEnterFullscreen?: () => void }
    try {
      v.webkitEnterFullscreen?.()
    } catch {
      /* ignore */
    }
  }
}

function onFsChange(): void {
  const doc = document as Document & { webkitFullscreenElement?: Element }
  isFullscreen.value =
    !!document.fullscreenElement || !!doc.webkitFullscreenElement
}

// 控制条自动隐藏
function pokeControls(): void {
  showControls.value = true
  if (controlsTimer.value !== null) clearTimeout(controlsTimer.value)
  controlsTimer.value = window.setTimeout(() => {
    if (state.value === 'playing') showControls.value = false
  }, 3000)
}

// ---------------------------------------------------------------------------
// 生命周期
// ---------------------------------------------------------------------------

watch(
  () => props.stream,
  (s) => {
    if (s) resetAndPlay(s)
    else destroyEngine()
  },
)

onMounted(() => {
  document.addEventListener('fullscreenchange', onFsChange)
  document.addEventListener('webkitfullscreenchange', onFsChange)
  pokeControls()
  if (props.stream) resetAndPlay(props.stream)
})

onBeforeUnmount(() => {
  document.removeEventListener('fullscreenchange', onFsChange)
  document.removeEventListener('webkitfullscreenchange', onFsChange)
  if (refetchTimer !== null) clearTimeout(refetchTimer)
  stopStallWatchdog()
  if (audioTimer !== null) clearInterval(audioTimer)
  destroyEngine()
  try {
    audioSource?.disconnect()
    audioAnalyser?.disconnect()
    audioCtx?.close()
  } catch {
    /* ignore */
  }
  audioSource = null
  audioAnalyser = null
  audioCtx = null
})
</script>

<template>
  <div
    ref="wrapperEl"
    class="player-wrapper"
    @click="pokeControls"
    @touchstart="pokeControls"
  >
    <video
      ref="videoEl"
      playsinline
      webkit-playsinline
      :controls="false"
      preload="none"
      @playing="onPlaying"
      @pause="onPause"
      @error="onVideoError"
      @click="togglePlay"
    ></video>

    <slot></slot>

    <!-- 状态遮罩 -->
    <div v-if="state === 'loading'" class="state-mask">
      <div class="spinner"></div>
      <div>正在连接直播流…</div>
      <div v-if="currentAttempt" class="text-tertiary attempt-label">
        {{ currentAttempt.label }} · {{ currentAttempt.format.toUpperCase() }}
      </div>
    </div>

    <div v-else-if="state === 'error'" class="state-mask">
      <div class="err-title">⚠️ {{ errorMsg }}</div>
      <div class="err-actions">
        <button class="btn" @click="emit('refetch')">重新获取地址</button>
        <button
          v-if="attemptIndex < attempts.length - 1"
          class="btn secondary"
          @click="attemptIndex++; playAttempt()"
        >
          下一线路
        </button>
      </div>
    </div>

    <div v-else-if="needGesture && state !== 'playing'" class="state-mask">
      <button class="play-hint" @click="togglePlay">
        <svg viewBox="0 0 24 24" fill="currentColor">
          <path d="M8 5v14l11-7z" />
        </svg>
        点击播放
      </button>
    </div>

    <!-- 静音提示 -->
    <button v-if="muted && state === 'playing'" class="unmute-chip" @click="unmute">
      🔇 已静音，点击开启声音
    </button>

    <!-- 控制条 -->
    <transition name="fade">
      <div v-if="showControls" class="controls">
        <button class="ctrl" @click.stop="togglePlay" :aria-label="state === 'playing' ? '暂停' : '播放'">
          <svg v-if="state === 'playing'" viewBox="0 0 24 24" fill="currentColor">
            <path d="M6 5h4v14H6zM14 5h4v14h-4z" />
          </svg>
          <svg v-else viewBox="0 0 24 24" fill="currentColor">
            <path d="M8 5v14l11-7z" />
          </svg>
        </button>

        <div class="spacer"></div>

        <button class="ctrl" @click.stop="emit('refetch')" aria-label="刷新直播流">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M21 12a9 9 0 1 1-2.6-6.4M21 3v6h-6" />
          </svg>
        </button>
        <button class="ctrl" @click.stop="toggleFullscreen" aria-label="全屏">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5" />
          </svg>
        </button>
      </div>
    </transition>
  </div>
</template>

<style scoped>
.player-wrapper {
  position: relative;
  width: 100%;
  aspect-ratio: 16 / 9;
  background: #000;
  overflow: hidden;
}
.player-wrapper:fullscreen {
  aspect-ratio: auto;
  height: 100vh;
}
video {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  object-fit: contain;
  background: #000;
}
.state-mask {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 10px;
  color: #fff;
  background: rgba(0, 0, 0, 0.45);
  z-index: 6;
  font-size: 14px;
  text-align: center;
  padding: 16px;
}
.attempt-label {
  font-size: 12px;
  opacity: 0.8;
}
.err-title {
  font-size: 15px;
  max-width: 90%;
}
.err-actions {
  display: flex;
  gap: 10px;
}
.play-hint {
  display: flex;
  align-items: center;
  gap: 8px;
  color: #fff;
  font-size: 16px;
  background: rgba(0, 0, 0, 0.5);
  border-radius: 999px;
  padding: 12px 24px;
}
.play-hint svg {
  width: 22px;
  height: 22px;
}
.unmute-chip {
  position: absolute;
  top: 10px;
  left: 10px;
  z-index: 7;
  background: rgba(0, 0, 0, 0.6);
  color: #fff;
  font-size: 12.5px;
  padding: 6px 12px;
  border-radius: 999px;
}
.controls {
  position: absolute;
  left: 0;
  right: 0;
  bottom: 0;
  display: flex;
  align-items: center;
  padding: 8px 10px;
  gap: 6px;
  background: linear-gradient(transparent, rgba(0, 0, 0, 0.6));
  z-index: 7;
}
.ctrl {
  width: 40px;
  height: 40px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: #fff;
  border-radius: 10px;
}
.ctrl:active {
  background: rgba(255, 255, 255, 0.15);
}
.ctrl svg {
  width: 22px;
  height: 22px;
}
.spacer {
  flex: 1;
}
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.25s;
}
.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}
</style>
