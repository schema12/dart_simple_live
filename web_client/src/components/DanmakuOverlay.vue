<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { settings } from '../stores/settings'

/**
 * Canvas 弹幕渲染器。
 * 父组件通过 ref.push(text, color) 投递弹幕。
 */
const props = defineProps<{
  enabled: boolean
}>()

const container = ref<HTMLDivElement | null>(null)
const canvas = ref<HTMLCanvasElement | null>(null)

interface Item {
  text: string
  color: string
  x: number
  row: number
  speed: number
  width: number
}

const items: Item[] = []
const rowLastEnd: number[] = []
let ctx: CanvasRenderingContext2D | null = null
let rafId = 0
let lastTs = 0
let resizeObs: ResizeObserver | null = null
let cssWidth = 0
let cssHeight = 0
let dpr = 1

function push(text: string, color: string): void {
  if (!props.enabled || !ctx || cssWidth <= 0) return
  const fontSize = settings.danmaku.fontSize
  ctx.font = `bold ${fontSize}px -apple-system, 'PingFang SC', 'Microsoft YaHei', sans-serif`
  const width = ctx.measureText(text).width
  if (width > cssWidth * 0.9) return // 超长弹幕丢弃

  const baseSpeed = Math.max(cssWidth / 8, 80) * settings.danmaku.speed
  const speed = baseSpeed * (0.9 + Math.random() * 0.3)

  // 找一个可用行：上一条已经离开出安全间距
  let row = -1
  const gap = Math.max(30, width * 0.25)
  for (let i = 0; i < settings.danmaku.maxRows; i++) {
    const last = rowLastEnd[i] ?? -Infinity
    if (last <= cssWidth + gap * -1 || last === -Infinity || last <= cssWidth - 0) {
      // 行从未用过，或上一条已完全离开
      if (last === -Infinity || last <= cssWidth) {
        row = i
        break
      }
    }
  }
  if (row === -1) {
    // 行数未满则扩展
    if (rowLastEnd.length < settings.danmaku.maxRows) {
      row = rowLastEnd.length
    } else {
      // 全满：找最快离开的行
      let minEnd = Infinity
      for (let i = 0; i < rowLastEnd.length; i++) {
        if ((rowLastEnd[i] ?? Infinity) < minEnd) {
          minEnd = rowLastEnd[i] ?? Infinity
          row = i
        }
      }
      if (minEnd <= cssWidth) {
        // 该行即将空闲，允许复用
      } else if (items.length > settings.danmaku.density) {
        return // 密度限制，丢弃
      }
    }
  }
  if (row === -1) return

  items.push({
    text,
    color,
    x: cssWidth,
    row,
    speed,
    width,
  })
  rowLastEnd[row] = cssWidth + width
}

function frame(ts: number): void {
  rafId = requestAnimationFrame(frame)
  if (!ctx || cssWidth <= 0) return
  const dt = lastTs ? Math.min((ts - lastTs) / 1000, 0.05) : 0
  lastTs = ts
  if (!props.enabled) {
    ctx.clearRect(0, 0, cssWidth, cssHeight)
    return
  }

  ctx.clearRect(0, 0, cssWidth, cssHeight)
  ctx.globalAlpha = settings.danmaku.opacity
  const fontSize = settings.danmaku.fontSize
  const rowHeight = fontSize + 8
  ctx.font = `bold ${fontSize}px -apple-system, 'PingFang SC', 'Microsoft YaHei', sans-serif`
  ctx.lineWidth = Math.max(2, fontSize / 12)
  ctx.strokeStyle = 'rgba(0,0,0,0.65)'
  ctx.textBaseline = 'middle'

  for (let i = items.length - 1; i >= 0; i--) {
    const it = items[i]
    it.x -= it.speed * dt
    if (it.x + it.width < -20) {
      items.splice(i, 1)
      continue
    }
    const y = it.row * rowHeight + rowHeight / 2 + 4
    if (y > cssHeight) continue
    ctx.strokeText(it.text, it.x, y)
    ctx.fillStyle = it.color || '#ffffff'
    ctx.fillText(it.text, it.x, y)
    // 记录该行最右端（用于行分配）
    if (it.x + it.width < (rowLastEnd[it.row] ?? Infinity)) {
      // 不更新，rowLastEnd 跟踪最右
    }
  }
  // 更新行尾位置：取每行最右侧 item 的右边缘
  for (let r = 0; r < rowLastEnd.length; r++) {
    let end = -Infinity
    for (const it of items) {
      if (it.row === r) {
        end = Math.max(end, it.x + it.width)
      }
    }
    rowLastEnd[r] = end === -Infinity ? -Infinity : end
  }
}

function resize(): void {
  const el = container.value
  const cv = canvas.value
  if (!el || !cv) return
  cssWidth = el.clientWidth
  cssHeight = el.clientHeight
  dpr = Math.min(window.devicePixelRatio || 1, 2)
  cv.width = Math.round(cssWidth * dpr)
  cv.height = Math.round(cssHeight * dpr)
  cv.style.width = `${cssWidth}px`
  cv.style.height = `${cssHeight}px`
  ctx = cv.getContext('2d')
  if (ctx) {
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
  }
}

onMounted(() => {
  resize()
  resizeObs = new ResizeObserver(resize)
  if (container.value) {
    resizeObs.observe(container.value)
  }
  rafId = requestAnimationFrame(frame)
})

onBeforeUnmount(() => {
  cancelAnimationFrame(rafId)
  resizeObs?.disconnect()
})

watch(
  () => props.enabled,
  () => {
    // 清空积压，避免开启时爆量
    items.length = 0
    rowLastEnd.length = 0
  },
)

defineExpose({ push })
</script>

<template>
  <div ref="container" class="danmaku-overlay">
    <canvas ref="canvas"></canvas>
  </div>
</template>

<style scoped>
.danmaku-overlay {
  position: absolute;
  inset: 0;
  overflow: hidden;
  pointer-events: none;
  z-index: 5;
}
canvas {
  display: block;
}
</style>
