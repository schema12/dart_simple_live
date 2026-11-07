<script setup lang="ts">
import { ref } from 'vue'
import { api } from '../api/client'
import type { AnchorItem, RoomItem } from '../api/types'
import { PLATFORMS } from '../platforms'
import RoomCard from '../components/RoomCard.vue'
import { useRouter } from 'vue-router'

const router = useRouter()
const keyword = ref('')
const platform = ref('huya')
const rooms = ref<RoomItem[]>([])
const anchors = ref<AnchorItem[]>([])
const loading = ref(false)
const searched = ref(false)
const error = ref('')
const page = ref(1)
const hasMore = ref(false)

async function search(reset = true): Promise<void> {
  const kw = keyword.value.trim()
  if (!kw) return
  if (loading.value) return
  loading.value = true
  error.value = ''
  searched.value = true
  try {
    if (reset) {
      page.value = 1
    }
    const result = await api.search(platform.value, kw, page.value)
    rooms.value = reset ? result.rooms : [...rooms.value, ...result.rooms]
    anchors.value = reset ? result.anchors : [...anchors.value, ...result.anchors]
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
  void search(false)
}

function openAnchor(a: AnchorItem): void {
  router.push(`/room/${a.platform}/${a.roomId}`)
}
</script>

<template>
  <div class="page">
    <div class="search-bar">
      <input
        v-model="keyword"
        class="text-input"
        placeholder="搜索主播或直播间"
        confirm-type="search"
        @keyup.enter="search(true)"
      />
      <button class="btn" :disabled="loading" @click="search(true)">
        {{ loading ? '…' : '搜索' }}
      </button>
    </div>

    <div class="chip-row">
      <button
        v-for="p in PLATFORMS"
        :key="p.id"
        class="chip"
        :class="{ active: platform === p.id }"
        @click="platform = p.id; searched && search(true)"
      >
        {{ p.name }}
      </button>
    </div>

    <div v-if="error" class="error-box">
      {{ error }}
      <div class="retry"><button class="btn" @click="search(true)">重试</button></div>
    </div>
    <div v-else-if="loading && searched && rooms.length === 0" class="loading-box">
      <div class="spinner"></div>
      正在搜索…
    </div>
    <template v-else-if="searched">
      <template v-if="anchors.length > 0">
        <h3 class="section-title">主播</h3>
        <div class="anchor-list">
          <div
            v-for="a in anchors"
            :key="`a-${a.roomId}`"
            class="anchor-item card"
            @click="openAnchor(a)"
          >
            <img :src="a.avatar" loading="lazy" />
            <div class="a-info">
              <div class="a-name">{{ a.userName }}</div>
              <div class="a-status" :class="{ live: a.liveStatus }">
                {{ a.liveStatus ? '直播中' : '未开播' }}
              </div>
            </div>
          </div>
        </div>
      </template>

      <h3 class="section-title">直播间</h3>
      <div v-if="rooms.length === 0 && !loading" class="empty">没有找到相关直播间</div>
      <div v-else class="grid">
        <RoomCard v-for="room in rooms" :key="`${room.platform}-${room.roomId}`" :room="room" />
      </div>
      <div v-if="hasMore" class="load-more">
        <button class="btn secondary" :disabled="loading" @click="loadMore">
          {{ loading ? '加载中…' : '加载更多' }}
        </button>
      </div>
    </template>
    <div v-else class="empty">输入关键词开始搜索</div>
  </div>
</template>

<style scoped>
.search-bar {
  display: flex;
  gap: 10px;
  margin-bottom: 12px;
}
.chip-row {
  display: flex;
  gap: 8px;
  overflow-x: auto;
  padding-bottom: 4px;
  margin-bottom: 8px;
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
.anchor-list {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
}
.anchor-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 14px;
  cursor: pointer;
  min-width: 200px;
}
.anchor-item img {
  width: 44px;
  height: 44px;
  border-radius: 50%;
  object-fit: cover;
}
.a-name {
  font-size: 14px;
  font-weight: 600;
}
.a-status {
  font-size: 12px;
  color: var(--text-tertiary);
}
.a-status.live {
  color: var(--danger);
}
.load-more {
  display: flex;
  justify-content: center;
  padding: 18px 0 6px;
}
</style>
