<script setup lang="ts">
import { useFavorites } from '../stores/favorites'
import type { RoomItem } from '../api/types'
import RoomCard from '../components/RoomCard.vue'
import { formatTime } from '../time'

const favorites = useFavorites()

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
</script>

<template>
  <div class="page">
    <h2 class="section-title">我的收藏</h2>
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
