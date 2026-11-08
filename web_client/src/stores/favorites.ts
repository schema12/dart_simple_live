import { computed, reactive } from 'vue'
import type { RoomDetail, RoomItem } from '../api/types'

export interface FavoriteItem {
  platform: string
  roomId: string
  title: string
  userName: string
  cover: string
  addedAt: number
  pinnedAt?: number // 置顶时间戳；置顶项排在列表最前（支持多个置顶）
}

const STORAGE_KEY = 'sl_favorites'

function load(): FavoriteItem[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return []
    const list = JSON.parse(raw) as FavoriteItem[]
    return Array.isArray(list) ? list : []
  } catch {
    return []
  }
}

const state = reactive<{ items: FavoriteItem[] }>({ items: load() })

/** 置顶项在前（按置顶时间倒序），其余按收藏时间倒序。 */
const sortedItems = computed(() => {
  const pinned = state.items
    .filter((i) => i.pinnedAt)
    .sort((a, b) => (b.pinnedAt ?? 0) - (a.pinnedAt ?? 0))
  const rest = state.items.filter((i) => !i.pinnedAt)
  return [...pinned, ...rest]
})

function persist(): void {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state.items))
}

function keyOf(platform: string, roomId: string): string {
  return `${platform}::${roomId}`
}

export function useFavorites() {
  function has(platform: string, roomId: string): boolean {
    return state.items.some(
      (i) => keyOf(i.platform, i.roomId) === keyOf(platform, roomId),
    )
  }

  function addFromItem(item: RoomItem): void {
    if (has(item.platform, item.roomId)) return
    state.items.unshift({
      platform: item.platform,
      roomId: item.roomId,
      title: item.title,
      userName: item.userName,
      cover: item.cover,
      addedAt: Date.now(),
    })
    persist()
  }

  function addFromDetail(detail: RoomDetail): void {
    if (has(detail.platform, detail.roomId)) return
    state.items.unshift({
      platform: detail.platform,
      roomId: detail.roomId,
      title: detail.title,
      userName: detail.userName,
      cover: detail.cover,
      addedAt: Date.now(),
    })
    persist()
  }

  function remove(platform: string, roomId: string): void {
    state.items = state.items.filter(
      (i) => keyOf(i.platform, i.roomId) !== keyOf(platform, roomId),
    )
    persist()
  }

  /** 置顶/取消置顶（支持多个置顶）。 */
  function togglePin(f: FavoriteItem): void {
    const item = state.items.find(
      (i) => keyOf(i.platform, i.roomId) === keyOf(f.platform, f.roomId),
    )
    if (!item) return
    item.pinnedAt = item.pinnedAt ? undefined : Date.now()
    persist()
  }

  function toggle(detail: RoomDetail): boolean {
    if (has(detail.platform, detail.roomId)) {
      remove(detail.platform, detail.roomId)
      return false
    }
    addFromDetail(detail)
    return true
  }

  return { state, sortedItems, has, addFromItem, addFromDetail, remove, toggle, togglePin }
}
