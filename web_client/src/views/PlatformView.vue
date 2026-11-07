<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { api } from '../api/client'
import type { Category, RoomItem, SubCategory } from '../api/types'
import { platformMeta } from '../platforms'
import RoomCard from '../components/RoomCard.vue'

const route = useRoute()
const meta = computed(() => platformMeta(route.params.platform as string))

const categories = ref<Category[]>([])
const activeCategory = ref<SubCategory | null>(null)
const rooms = ref<RoomItem[]>([])
const page = ref(1)
const hasMore = ref(false)
const loading = ref(false)
const error = ref('')
const activeParent = ref('')

const currentParent = computed(() =>
  categories.value.find((c) => c.id === activeParent.value),
)

async function loadCategories(): Promise<void> {
  error.value = ''
  try {
    categories.value = await api.categories(route.params.platform as string)
    if (categories.value.length > 0) {
      activeParent.value = categories.value[0].id
      pickSub(categories.value[0].children[0] ?? null)
    }
  } catch (e) {
    error.value = (e as Error).message
  }
}

function pickSub(sub: SubCategory | null): void {
  activeCategory.value = sub
  void loadRooms(true)
}

async function loadRooms(reset = false): Promise<void> {
  const sub = activeCategory.value
  if (!sub) {
    rooms.value = []
    return
  }
  if (loading.value) return
  loading.value = true
  error.value = ''
  try {
    if (reset) {
      page.value = 1
      rooms.value = []
    }
    const result = await api.categoryRooms(
      route.params.platform as string,
      sub.id,
      sub.parentId,
      page.value,
    )
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
  void loadRooms()
}

onMounted(() => void loadCategories())

watch(
  () => route.params.platform,
  () => {
    categories.value = []
    activeCategory.value = null
    rooms.value = []
    void loadCategories()
  },
)
</script>

<template>
  <div class="page">
    <h2 class="section-title">
      <span class="plat-dot" :style="{ background: meta.gradient }">{{ meta.short }}</span>
      {{ meta.name }}
    </h2>

    <!-- 一级分类 -->
    <div class="chip-row">
      <button
        v-for="c in categories"
        :key="c.id"
        class="chip"
        :class="{ active: activeParent === c.id }"
        @click="activeParent = c.id"
      >
        {{ c.name }}
      </button>
    </div>

    <!-- 二级分类 -->
    <div class="chip-row sub-row">
      <button
        v-for="sub in currentParent?.children ?? []"
        :key="sub.id"
        class="chip"
        :class="{ active: activeCategory?.id === sub.id }"
        @click="pickSub(sub)"
      >
        {{ sub.name }}
      </button>
    </div>

    <div v-if="error" class="error-box">
      {{ error }}
      <div class="retry"><button class="btn" @click="activeCategory && loadRooms(true)">重试</button></div>
    </div>
    <div v-else-if="loading && rooms.length === 0" class="loading-box">
      <div class="spinner"></div>
      正在加载直播间…
    </div>
    <div v-else-if="!activeCategory" class="empty">请选择一个分类</div>
    <div v-else-if="rooms.length === 0" class="empty">该分类下暂时没有直播</div>
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
.plat-dot {
  width: 26px;
  height: 26px;
  border-radius: 8px;
  color: #fff;
  font-size: 14px;
  font-weight: 700;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}
.chip-row {
  display: flex;
  gap: 8px;
  overflow-x: auto;
  padding-bottom: 4px;
  margin-bottom: 10px;
}
.sub-row {
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
