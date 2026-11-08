<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { usePairing } from './stores/pairing'
import PairView from './views/PairView.vue'

const route = useRoute()
const { paired } = usePairing()

const isRoomRoute = computed(() => route.name === 'room')

// 需要 keep-alive 的列表页组件名
const keepNames = ['HomeView', 'PlatformView', 'SearchView', 'FavoritesView']

const navs = computed(() => [
  { name: 'home', label: '首页', icon: 'home', to: '/' },
  { name: 'search', label: '搜索', icon: 'search', to: '/search' },
  { name: 'favorites', label: '收藏', icon: 'star', to: '/favorites' },
  { name: 'settings', label: '设置', icon: 'settings', to: '/settings' },
])
</script>

<template>
  <div class="app-root">
    <router-view v-if="paired || route.name === 'pair'" v-slot="{ Component }">
      <!-- keep-alive 保留列表页状态：从直播间返回时恢复进入时的板块与数据 -->
      <keep-alive :include="keepNames">
        <component :is="Component" />
      </keep-alive>
    </router-view>
    <PairView v-else />
    <nav v-if="paired && !isRoomRoute" class="bottom-nav">
      <router-link
        v-for="n in navs"
        :key="n.name"
        :to="n.to"
        :class="{ active: route.name === n.name }"
      >
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
          <template v-if="n.icon === 'home'">
            <path d="M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6h-6v6H4a1 1 0 0 1-1-1z" />
          </template>
          <template v-else-if="n.icon === 'search'">
            <circle cx="11" cy="11" r="7" />
            <path d="m20 20-3.5-3.5" />
          </template>
          <template v-else-if="n.icon === 'star'">
            <path
              d="m12 3 2.7 5.8 6.3.8-4.6 4.4 1.2 6.2L12 17.2 6.4 20.2l1.2-6.2L3 9.6l6.3-.8z"
            />
          </template>
          <template v-else>
            <circle cx="12" cy="12" r="3" />
            <path
              d="M19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.9-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1-1.6 1.7 1.7 0 0 0-1.9.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.9 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.6-1 1.7 1.7 0 0 0-.3-1.9l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.9.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.9-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.9V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"
            />
          </template>
        </svg>
        <span>{{ n.label }}</span>
      </router-link>
    </nav>
  </div>
</template>
