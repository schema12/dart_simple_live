import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// 同源部署：构建产物由手机端 HTTP 服务直接提供，必须使用相对路径。
export default defineConfig({
  base: './',
  plugins: [vue()],
  build: {
    outDir: '../simple_live_app/assets/web',
    emptyOutDir: true,
    target: 'es2020',
    chunkSizeWarningLimit: 1600,
    rollupOptions: {
      output: {
        manualChunks: {
          hls: ['hls.js'],
          mpegts: ['mpegts.js'],
          vendor: ['vue', 'vue-router'],
        },
      },
    },
  },
  server: {
    // 本地开发时可通过 VITE_API_BASE 指向手机/standalone 服务器
    proxy: process.env.VITE_API_BASE
      ? {
          '/api': {
            target: process.env.VITE_API_BASE,
            changeOrigin: false,
            ws: true,
          },
        }
      : undefined,
  },
})
