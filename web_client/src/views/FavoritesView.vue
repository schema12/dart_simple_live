<script setup lang="ts">
defineOptions({ name: 'FavoritesView' })
import { ref } from 'vue'
import { api } from '../api/client'
import type { RoomItem } from '../api/types'
import RoomCard from '../components/RoomCard.vue'
import { formatTime } from '../time'
import { useFavorites } from '../stores/favorites'
import type { FavoriteItem } from '../stores/favorites'

const favorites = useFavorites()
const msg = ref('')
const importing = ref(false)
const fileInput = ref<HTMLInputElement | null>(null)

function asRoom(f: {
  platform: string
  roomId: string
  title: string
  userName: string
  cover: string
}): RoomItem {
  return {
    platform: f.platform as RoomItem['platform'],
    roomId: f.roomId,
    title: f.title,
    userName: f.userName,
    cover: f.cover,
    online: 0,
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
    <div v-else>
      <div
        v-for="f in favorites.state.items"
        :key="`${f.platform}-${f.roomId}`"
        class="fav-row card"
      >
        <RoomCard :room="asRoom(f)" class="fav-card" />
        <div class="fav-meta">
          收藏于 {{ formatTime(f.addedAt) }}
        </div>
        <button
          class="btn danger small"
          @click="favorites.remove(f.platform, f.roomId)"
        >
          取消收藏
        </button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.toolbar {
  display: flex;
  gap: 10px;
  margin-bottom: 12px;
  flex-wrap: wrap;
}
.msg {
  font-size: 13px;
  color: var(--accent);
  margin-bottom: 12px;
}
.fav-row {
  padding: 12px;
  margin-bottom: 12px;
  display: grid;
  grid-template-columns: minmax(180px, 300px) 1fr auto;
  align-items: center;
  gap: 14px;
}
@media (max-width: 700px) {
  .fav-row {
    grid-template-columns: 1fr;
  }
}
.fav-card {
  box-shadow: none;
}
.fav-meta {
  font-size: 12.5px;
  color: var(--text-tertiary);
}
.btn.small {
  padding: 8px 14px;
  font-size: 13px;
}
</style>
