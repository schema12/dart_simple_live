import { reactive } from 'vue'
import type { RoomDetail, RoomItem } from '../api/types'

export interface FavoriteItem {
  platform: string
  roomId: string
  title: string
  userName: string
  cover: string
  addedAt: number
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

  function toggle(detail: RoomDetail): boolean {
    if (has(detail.platform, detail.roomId)) {
      remove(detail.platform, detail.roomId)
      return false
    }
    addFromDetail(detail)
    return true
  }

  return { state, has, addFromItem, addFromDetail, remove, toggle }
}
