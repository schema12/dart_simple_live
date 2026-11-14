import { reactive, watch } from 'vue'

export type ThemeMode = 'auto' | 'light' | 'dark'
export type ProxyMode = 'auto' | 'direct' | 'proxy'

export interface DanmakuSettings {
  enabled: boolean
  opacity: number // 0.1 - 1
  fontSize: number // px
  speed: number // 屏幕宽/秒 倍率 0.5-3
  density: number // 最大同时显示条数 5-50
  maxRows: number // 显示几行（优先；超过区域可容纳行数时自动收紧）3-40
  showTop: boolean // 顶部固定区（醒目留言）
  area: number // 显示区域比例 0.1-1（按画面高度百分比）
  stroke: boolean // 描边开关
  strokeWidth: number // 描边宽度 px
  bold: boolean // 粗体字重
  emoji: boolean // 显示弹幕表情
}

export type FavoritesLayout = 'list' | 'card'

export interface Settings {
  theme: ThemeMode
  danmaku: DanmakuSettings
  defaultQuality: number // 画质 index
  autoplay: boolean
  proxyMode: ProxyMode
  autoRetry: boolean
  favoritesLayout: FavoritesLayout // 收藏页布局
}

const STORAGE_KEY = 'sl_settings'

const defaults: Settings = {
  theme: 'auto',
  danmaku: {
    enabled: true,
    opacity: 1,
    fontSize: 22,
    speed: 1,
    density: 24,
    maxRows: 8, // 对齐原版默认（显示几行 8）
    showTop: true,
    area: 0.8, // 对齐原版默认（显示区域 80%）
    stroke: true,
    strokeWidth: 2,
    bold: true,
    emoji: true,
  },
  defaultQuality: 0,
  autoplay: true,
  proxyMode: 'auto',
  autoRetry: true,
  favoritesLayout: 'list',
}

function load(): Settings {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return structuredClone(defaults)
    const parsed = JSON.parse(raw) as Partial<Settings>
    return {
      ...structuredClone(defaults),
      ...parsed,
      danmaku: { ...defaults.danmaku, ...(parsed.danmaku ?? {}) },
    }
  } catch {
    return structuredClone(defaults)
  }
}

export const settings = reactive<Settings>(load())

watch(
  settings,
  (v) => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(v))
    applyTheme(v.theme)
  },
  { deep: true },
)

export function applyTheme(mode: ThemeMode): void {
  const root = document.documentElement
  if (mode === 'auto') {
    root.removeAttribute('data-theme')
  } else {
    root.setAttribute('data-theme', mode)
  }
}

// 启动时应用主题
applyTheme(settings.theme)
