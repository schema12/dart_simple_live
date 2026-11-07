<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { setToken, api } from '../api/client'
import { usePairing } from '../stores/pairing'

const router = useRouter()
const { refresh } = usePairing()

const input = ref('')
const checking = ref(false)
const error = ref('')

async function submit(): Promise<void> {
  const token = input.value.trim().toLowerCase()
  if (!/^[0-9a-f]{16,64}$/.test(token)) {
    error.value = '令牌格式不正确（32 位十六进制字符）'
    return
  }
  checking.value = true
  error.value = ''
  setToken(token)
  try {
    await api.server()
    refresh()
    router.replace('/')
  } catch (e) {
    error.value = (e as Error).message || '连接失败，请检查网络'
  } finally {
    checking.value = false
  }
}
</script>

<template>
  <div class="pair-page">
    <div class="pair-card card">
      <div class="logo">
        <svg viewBox="0 0 32 32" class="logo-svg">
          <rect width="32" height="32" rx="7" fill="#00a1d6" />
          <path
            d="M9 12.5 7 8.5M23 12.5l2-4M10.5 12.5h11c2 0 3.5 1.6 3.5 3.5v5.5c0 2-1.5 3.5-3.5 3.5h-11c-2 0-3.5-1.5-3.5-3.5V16c0-1.9 1.5-3.5 3.5-3.5z"
            fill="none"
            stroke="#fff"
            stroke-width="2.2"
            stroke-linecap="round"
          />
          <circle cx="13.5" cy="18.5" r="1.6" fill="#fff" />
          <circle cx="18.5" cy="18.5" r="1.6" fill="#fff" />
        </svg>
        <h1>SimpleLive LAN</h1>
        <p class="text-secondary">手机局域网直播聚合</p>
      </div>

      <div class="steps">
        <div class="step">
          <span class="num">1</span>
          <span>在手机上打开 SimpleLive LAN，进入「局域网服务器」并启动服务</span>
        </div>
        <div class="step">
          <span class="num">2</span>
          <span>用 iPad 扫描手机页面上的二维码，或输入下方配对令牌</span>
        </div>
      </div>

      <div class="input-row">
        <input
          v-model="input"
          class="text-input"
          placeholder="输入手机显示的配对令牌"
          autocapitalize="off"
          autocomplete="off"
          @keyup.enter="submit"
        />
      </div>
      <div v-if="error" class="err">{{ error }}</div>
      <button class="btn" :disabled="checking" style="width: 100%" @click="submit">
        {{ checking ? '正在连接…' : '连接手机服务器' }}
      </button>
      <p class="text-tertiary tip">
        令牌显示在手机「局域网服务器」页面的服务地址下方。
      </p>
    </div>
  </div>
</template>

<style scoped>
.pair-page {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 20px;
}
.pair-card {
  width: 100%;
  max-width: 420px;
  padding: 28px 24px;
}
.logo {
  text-align: center;
  margin-bottom: 20px;
}
.logo-svg {
  width: 56px;
  height: 56px;
  margin-bottom: 10px;
}
.logo h1 {
  font-size: 20px;
  margin: 0;
}
.logo p {
  margin: 6px 0 0;
  font-size: 13px;
}
.steps {
  display: flex;
  flex-direction: column;
  gap: 10px;
  margin-bottom: 18px;
}
.step {
  display: flex;
  gap: 10px;
  font-size: 13.5px;
  color: var(--text-secondary);
  line-height: 1.5;
}
.num {
  flex-shrink: 0;
  width: 20px;
  height: 20px;
  border-radius: 50%;
  background: var(--accent-weak);
  color: var(--accent);
  font-size: 12px;
  font-weight: 700;
  display: flex;
  align-items: center;
  justify-content: center;
}
.input-row {
  margin-bottom: 10px;
}
.err {
  color: var(--danger);
  font-size: 13px;
  margin-bottom: 10px;
}
.tip {
  font-size: 12.5px;
  margin-top: 14px;
  text-align: center;
}
</style>
