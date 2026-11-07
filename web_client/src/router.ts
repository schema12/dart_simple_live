import { createRouter, createWebHashHistory } from 'vue-router'

export const router = createRouter({
  history: createWebHashHistory(),
  routes: [
    { path: '/', name: 'home', component: () => import('./views/HomeView.vue') },
    {
      path: '/platform/:platform',
      name: 'platform',
      component: () => import('./views/PlatformView.vue'),
    },
    { path: '/search', name: 'search', component: () => import('./views/SearchView.vue') },
    {
      path: '/room/:platform/:roomId',
      name: 'room',
      component: () => import('./views/RoomView.vue'),
    },
    {
      path: '/favorites',
      name: 'favorites',
      component: () => import('./views/FavoritesView.vue'),
    },
    {
      path: '/settings',
      name: 'settings',
      component: () => import('./views/SettingsView.vue'),
    },
    {
      path: '/pair',
      name: 'pair',
      component: () => import('./views/PairView.vue'),
    },
    { path: '/:pathMatch(.*)*', redirect: '/' },
  ],
})
