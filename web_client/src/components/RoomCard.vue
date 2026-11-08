<script setup lang="ts">
import { useRouter } from 'vue-router'
import type { RoomItem } from '../api/types'
import { formatOnline, platformMeta } from '../platforms'
import { useFavorites } from '../stores/favorites'

const props = defineProps<{ room: RoomItem; showPlatform?: boolean }>()
const router = useRouter()
const favorites = useFavorites()
const meta = platformMeta(props.room.platform)

function open(): void {
  router.push(`/room/${props.room.platform}/${props.room.roomId}`)
}

function toggleFav(e: Event): void {
  e.stopPropagation()
  if (favorites.has(props.room.platform, props.room.roomId)) {
    favorites.remove(props.room.platform, props.room.roomId)
  } else {
    favorites.addFromItem(props.room)
  }
}

function coverFallback(e: Event): void {
  const img = e.target as HTMLImageElement
  // 第一级回退：去掉尺寸后缀（如 @400w.jpg），部分图床不支持该变体
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
        `<svg xmlns="http://www.w3.org/2000/svg" width="400" height="225"><rect width="400" height="225" fill="#2b3038"/><text x="200" y="120" font-size="26" fill="#6b717c" text-anchor="middle">无封面</text></svg>`,
      )
  }
}
</script>

<template>
  <div class="room-card card" @click="open">
    <div class="cover-wrap">
      <img
        :src="room.cover"
        loading="lazy"
        referrerpolicy="no-referrer"
        @error="coverFallback"
      />
      <span class="badge platform-badge" :style="{ background: meta.gradient }">
        {{ meta.short }}
      </span>
      <span v-if="room.online > 0" class="badge online-badge">
        {{ formatOnline(room.online) }}
      </span>
      <button
        class="fav-btn"
        :class="{ active: favorites.has(room.platform, room.roomId) }"
        @click="toggleFav"
        :aria-label="favorites.has(room.platform, room.roomId) ? '取消收藏' : '收藏'"
      >
        <svg viewBox="0 0 24 24" :fill="favorites.has(room.platform, room.roomId) ? 'currentColor' : 'none'" stroke="currentColor" stroke-width="2">
          <path d="m12 3 2.7 5.8 6.3.8-4.6 4.4 1.2 6.2L12 17.2 6.4 20.2l1.2-6.2L3 9.6l6.3-.8z" />
        </svg>
      </button>
    </div>
    <div class="info">
      <div class="title">{{ room.title || '直播间' }}</div>
      <div class="meta-row">
        <span class="anchor">{{ room.userName }}</span>
        <span v-if="showPlatform" class="platform-name" :style="{ color: meta.color }">
          {{ meta.name }}
        </span>
      </div>
    </div>
  </div>
</template>

<style scoped>
.room-card {
  overflow: hidden;
  cursor: pointer;
  transition: transform 0.15s;
}
.room-card:active {
  transform: scale(0.985);
}
.cover-wrap {
  position: relative;
  aspect-ratio: 16 / 9;
  background: #2b3038;
}
.cover-wrap img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}
.badge {
  position: absolute;
  bottom: 6px;
  font-size: 11px;
  color: #fff;
  padding: 2px 8px;
  border-radius: 999px;
  line-height: 1.5;
}
.platform-badge {
  left: 6px;
  font-weight: 700;
}
.online-badge {
  right: 6px;
  background: rgba(0, 0, 0, 0.55);
}
.fav-btn {
  position: absolute;
  top: 6px;
  right: 6px;
  width: 30px;
  height: 30px;
  border-radius: 50%;
  background: rgba(0, 0, 0, 0.4);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
}
.fav-btn svg {
  width: 16px;
  height: 16px;
}
.fav-btn.active {
  color: #ffb300;
}
.info {
  padding: 10px 12px 12px;
}
.title {
  font-size: 13.5px;
  font-weight: 600;
  line-height: 1.35;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
  min-height: 36px;
}
.meta-row {
  margin-top: 6px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  font-size: 12px;
  color: var(--text-tertiary);
}
.anchor {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.platform-name {
  flex-shrink: 0;
  font-weight: 600;
}
</style>
