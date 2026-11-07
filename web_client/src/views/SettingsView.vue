<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { api, clearToken, getClientId, setToken } from '../api/client'
import type { ClientInfo, LogEntry, ServerInfo } from '../api/types'
import { settings, type ThemeMode, type ProxyMode } from '../stores/settings'
import { usePairing } from '../stores/pairing'

const { paired, refresh, unpair } = usePairing()

const serverInfo = ref<ServerInfo | null>(null)
const serverError = ref('')
const clients = ref<ClientInfo[]>([])
const logs = ref<LogEntry[]>([])
const showLogs = ref(false)
const clientRevoked = ref(false)

async function loadServer(): Promise<void> {
  serverError.value = ''
  try {
    serverInfo.value = await api.server()
  } catch (e) {
    serverError.value = (e as Error).message
  }
}

async function loadClients(): Promise<void> {
  try {
    clients.value = await api.clients()
  } catch {
    /* ignore */
  }
}

async function revoke(c: ClientInfo): Promise<void> {
  try {
    await api.revokeClient(c.id)
    if (c.id === getClientId()) {
      clientRevoked.value = true
      unpair()
    } else {
      await loadClients()
    }
  } catch {
    /* ignore */
  }
}

async function unpairSelf(): Promise<void> {
  clearToken()
  unpair()
  location.reload()
}

const themeOptions: { value: ThemeMode; label: string }[] = [
  { value: 'auto', label: '跟随系统' },
  { value: 'light', label: '浅色' },
  { value: 'dark', label: '深色' },
]

const proxyOptions: { value: ProxyMode; label: string }[] = [
  { value: 'auto', label: '自动（先直连后代理）' },
  { value: 'direct', label: '仅直连 CDN' },
  { value: 'proxy', label: '始终经手机代理' },
]

onMounted(() => {
  void loadServer()
  void loadClients()
})
</script>

<template>
  <div class="page">
    <h2 class="section-title">设置</h2>

    <!-- 服务状态 -->
    <div class="field-group">
      <div class="field">
        <div>
          <div class="field-label">服务连接</div>
          <div class="field-desc" v-if="serverInfo">
            {{ serverInfo.name }} v{{ serverInfo.version }} · 运行 {{ Math.floor(serverInfo.uptimeSec / 60) }} 分钟 ·
            手机 IP {{ serverInfo.addresses.join(' / ') }}:{{ serverInfo.port }}
          </div>
          <div class="field-desc" v-else-if="serverError">
            ⚠️ {{ serverError }}
          </div>
          <div class="field-desc" v-else>正在获取服务状态…</div>
        </div>
        <button class="btn secondary small" @click="loadServer(); loadClients()">刷新</button>
      </div>
      <div class="field" v-if="serverInfo">
        <div>
          <div class="field-label">在线客户端</div>
          <div class="field-desc">
            {{ serverInfo.activeClients }} 台设备 · 弹幕房间 {{ serverInfo.danmakuRooms }} 个
          </div>
        </div>
      </div>
    </div>

    <!-- 外观 -->
    <h3 class="group-title">外观</h3>
    <div class="field-group">
      <div class="field">
        <div class="field-label">主题</div>
        <div class="seg">
          <button
            v-for="t in themeOptions"
            :key="t.value"
            class="seg-item"
            :class="{ active: settings.theme === t.value }"
            @click="settings.theme = t.value"
          >
            {{ t.label }}
          </button>
        </div>
      </div>
    </div>

    <!-- 弹幕 -->
    <h3 class="group-title">弹幕</h3>
    <div class="field-group">
      <div class="field">
        <div class="field-label">显示弹幕</div>
        <button
          class="switch"
          :class="{ on: settings.danmaku.enabled }"
          @click="settings.danmaku.enabled = !settings.danmaku.enabled"
        ></button>
      </div>
      <div class="field">
        <div>
          <div class="field-label">不透明度</div>
          <div class="field-desc">{{ Math.round(settings.danmaku.opacity * 100) }}%</div>
        </div>
        <input
          type="range"
          class="slider"
          min="0.1"
          max="1"
          step="0.05"
          v-model.number="settings.danmaku.opacity"
        />
      </div>
      <div class="field">
        <div>
          <div class="field-label">字号</div>
          <div class="field-desc">{{ settings.danmaku.fontSize }}px</div>
        </div>
        <input
          type="range"
          class="slider"
          min="14"
          max="40"
          step="1"
          v-model.number="settings.danmaku.fontSize"
        />
      </div>
      <div class="field">
        <div>
          <div class="field-label">速度</div>
          <div class="field-desc">×{{ settings.danmaku.speed.toFixed(1) }}</div>
        </div>
        <input
          type="range"
          class="slider"
          min="0.5"
          max="3"
          step="0.1"
          v-model.number="settings.danmaku.speed"
        />
      </div>
      <div class="field">
        <div>
          <div class="field-label">最大行数</div>
          <div class="field-desc">{{ settings.danmaku.maxRows }} 行</div>
        </div>
        <input
          type="range"
          class="slider"
          min="2"
          max="15"
          step="1"
          v-model.number="settings.danmaku.maxRows"
        />
      </div>
      <div class="field">
        <div>
          <div class="field-label">密度限制</div>
          <div class="field-desc">同屏最多 {{ settings.danmaku.density }} 条</div>
        </div>
        <input
          type="range"
          class="slider"
          min="5"
          max="50"
          step="1"
          v-model.number="settings.danmaku.density"
        />
      </div>
    </div>

    <!-- 播放 -->
    <h3 class="group-title">播放</h3>
    <div class="field-group">
      <div class="field">
        <div>
          <div class="field-label">默认画质</div>
          <div class="field-desc">进入直播间时优先选择</div>
        </div>
        <div class="seg">
          <button
            class="seg-item"
            :class="{ active: settings.defaultQuality === 0 }"
            @click="settings.defaultQuality = 0"
          >
            最高
          </button>
          <button
            class="seg-item"
            :class="{ active: settings.defaultQuality === 1 }"
            @click="settings.defaultQuality = 1"
          >
            次高
          </button>
        </div>
      </div>
      <div class="field">
        <div>
          <div class="field-label">自动播放</div>
          <div class="field-desc">受浏览器自动播放策略影响，失败时会自动静音重试</div>
        </div>
        <button
          class="switch"
          :class="{ on: settings.autoplay }"
          @click="settings.autoplay = !settings.autoplay"
        ></button>
      </div>
      <div class="field">
        <div>
          <div class="field-label">视频线路方式</div>
          <div class="field-desc">
            代理模式会经手机转发视频流，会增加手机流量、耗电与发热
          </div>
        </div>
        <select v-model="settings.proxyMode" class="seg-select">
          <option v-for="p in proxyOptions" :key="p.value" :value="p.value">
            {{ p.label }}
          </option>
        </select>
      </div>
      <div class="field">
        <div>
          <div class="field-label">断流自动重试</div>
          <div class="field-desc">播放地址失效后自动重新获取</div>
        </div>
        <button
          class="switch"
          :class="{ on: settings.autoRetry }"
          @click="settings.autoRetry = !settings.autoRetry"
        ></button>
      </div>
    </div>

    <!-- 配对与设备 -->
    <h3 class="group-title">配对与设备</h3>
    <div class="field-group">
      <div class="field">
        <div>
          <div class="field-label">本机客户端 ID</div>
          <div class="field-desc">{{ getClientId().slice(0, 8) }}…</div>
        </div>
        <span v-if="clientRevoked" class="revoked-badge">已被撤销</span>
      </div>
      <div class="field" v-for="c in clients" :key="c.id">
        <div>
          <div class="field-label">
            {{ c.id === getClientId() ? '本设备' : c.userAgent.slice(0, 40) || c.id.slice(0, 8) }}
          </div>
          <div class="field-desc">
            最近活跃 {{ new Date(c.lastSeen).toLocaleTimeString() }} · {{ c.requests }} 次请求
          </div>
        </div>
        <button class="btn danger small" @click="revoke(c)">撤销</button>
      </div>
      <div class="field">
        <div>
          <div class="field-label">解除配对</div>
          <div class="field-desc">清除本机保存的访问令牌</div>
        </div>
        <button class="btn danger small" @click="unpairSelf">解除</button>
      </div>
    </div>

    <!-- 日志 -->
    <h3 class="group-title">诊断</h3>
    <div class="field-group">
      <div class="field">
        <div class="field-label">服务端请求日志</div>
        <button class="btn secondary small" @click="showLogs = !showLogs; logs.length === 0 && api.logs().then(l => (logs = l))">
          {{ showLogs ? '隐藏' : '查看' }}
        </button>
      </div>
    </div>
    <div v-if="showLogs" class="log-box card">
      <div v-for="(l, i) in logs" :key="i" class="log-line">
        [{{ l.time.slice(11, 19) }}] {{ l.method }} {{ l.path }}
        <span v-if="l.status" :class="{ ok: l.status < 400, bad: l.status >= 400 }">{{ l.status }}</span>
        <span class="log-meta">{{ l.elapsedMs }}ms · {{ l.remote }}</span>
      </div>
    </div>
  </div>
</template>

<style scoped>
.group-title {
  font-size: 15px;
  font-weight: 700;
  margin: 22px 4px 10px;
  color: var(--text-secondary);
}
.seg {
  display: inline-flex;
  background: var(--bg-hover);
  border-radius: 10px;
  padding: 3px;
  gap: 2px;
}
.seg-item {
  padding: 7px 14px;
  border-radius: 8px;
  font-size: 13px;
  color: var(--text-secondary);
}
.seg-item.active {
  background: var(--accent);
  color: #fff;
  font-weight: 600;
}
.seg-select {
  background: var(--bg-hover);
  border: 1px solid var(--border);
  color: var(--text);
  border-radius: 10px;
  padding: 8px 12px;
  font-size: 13px;
  max-width: 200px;
}
.btn.small {
  padding: 8px 14px;
  font-size: 13px;
}
.revoked-badge {
  color: var(--danger);
  font-size: 13px;
}
.log-box {
  padding: 12px 16px;
  font-family: ui-monospace, Menlo, Consolas, monospace;
  font-size: 12px;
  max-height: 320px;
  overflow: auto;
}
.log-line {
  padding: 2px 0;
}
.log-meta {
  color: var(--text-tertiary);
  margin-left: 8px;
}
.log-line .ok {
  color: #34c759;
}
.log-line .bad {
  color: var(--danger);
}
</style>
