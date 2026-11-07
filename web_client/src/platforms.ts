/** 平台元数据（纯本地样式，不加载外部图片）。 */
export interface PlatformMeta {
  id: string
  name: string
  short: string
  color: string
  gradient: string
}

export const PLATFORMS: PlatformMeta[] = [
  {
    id: 'huya',
    name: '虎牙直播',
    short: '虎',
    color: '#f80',
    gradient: 'linear-gradient(135deg,#ff9800,#f57c00)',
  },
  {
    id: 'douyu',
    name: '斗鱼直播',
    short: '斗',
    color: '#ff5d23',
    gradient: 'linear-gradient(135deg,#ff7a45,#ff5d23)',
  },
  {
    id: 'bilibili',
    name: '哔哩哔哩',
    short: 'B',
    color: '#00a1d6',
    gradient: 'linear-gradient(135deg,#22b6e8,#00a1d6)',
  },
]

export function platformMeta(id: string): PlatformMeta {
  return (
    PLATFORMS.find((p) => p.id === id) ?? {
      id,
      name: id,
      short: id.slice(0, 1).toUpperCase(),
      color: '#888',
      gradient: 'linear-gradient(135deg,#aaa,#888)',
    }
  )
}

export function formatOnline(n: number): string {
  if (!n || n <= 0) return ''
  if (n >= 100000000) return `${(n / 100000000).toFixed(1)}亿`
  if (n >= 10000) return `${(n / 10000).toFixed(1)}万`
  return String(n)
}
