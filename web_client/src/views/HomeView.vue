<script setup lang="ts">
defineOptions({ name: 'HomeView' })
import { onMounted, ref, watch } from 'vue'
import { api } from '../api/client'
import type { RoomItem } from '../api/types'
import { PLATFORMS } from '../platforms'
import RoomCard from '../components/RoomCard.vue'

const currentPlatform = ref('huya')
const rooms = ref<RoomItem[]>([])
const loading = ref(false)
const error = ref('')
const page = ref(1)
const hasMore = ref(false)

async function load(reset = false): Promise<void> {
  if (loading.value) return
  loading.value = true
  error.value = ''
  try {
    if (reset) {
      page.value = 1
      rooms.value = []
    }
    const result = await api.recommend(currentPlatform.value, page.value)
    rooms.value = reset ? result.items : [...rooms.value, ...result.items]
    hasMore.value = result.hasMore
  } catch (e) {
    error.value = (e as Error).message
  } finally {
    loading.value = false
  }
}

function loadMore(): void {
  if (!hasMore.value || loading.value) return
  page.value++
  void load()
}

onMounted(() => void load(true))
watch(currentPlatform, () => void load(true))
</script>

<template>
  <div class="page">
    <h2 class="section-title">推荐直播</h2>
    <div class="chip-row">
      <button
        v-for="p in PLATFORMS"
        :key="p.id"
        class="chip"
        :class="{ active: currentPlatform === p.id }"
        @click="currentPlatform = p.id"
      >
        {{ p.name }}
      </button>
    </div>

    <div v-if="error" class="error-box">
      {{ error }}
      <div class="retry"><button class="btn" @click="load(true)">重试</button></div>
    </div>
    <div v-else-if="loading && rooms.length === 0" class="loading-box">
      <div class="spinner"></div>
      正在获取推荐直播…
    </div>
    <div v-else-if="rooms.length === 0" class="empty">暂时没有推荐直播间</div>
    <div v-else class="grid">
      <RoomCard v-for="room in rooms" :key="`${room.platform}-${room.roomId}`" :room="room" />
    </div>
    <div v-if="hasMore" class="load-more">
      <button class="btn secondary" :disabled="loading" @click="loadMore">
        {{ loading ? '加载中…' : '加载更多' }}
      </button>
    </div>
  </div>
</template>

<style scoped>
.chip-row {
  display: flex;
  gap: 8px;
  overflow-x: auto;
  padding-bottom: 4px;
  margin-bottom: 14px;
}
.grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
  gap: 14px;
}
@media (max-width: 500px) {
  .grid {
    grid-template-columns: repeat(2, 1fr);
    gap: 10px;
  }
}
.load-more {
  display: flex;
  justify-content: center;
  padding: 18px 0 6px;
}
</style>
