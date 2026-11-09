<script setup lang="ts">
import { settings } from '../stores/settings'

/** 弹幕设置面板内容（原版 DanmuSettingsView 的 Web 版，无屏蔽功能）。 */
const areaOptions = [
  { value: 1, label: '全屏' },
  { value: 0.75, label: '3/4' },
  { value: 0.5, label: '半屏' },
  { value: 0.25, label: '1/4' },
]
const areaLabel = computed(() => {
  const found = areaOptions.find((a) => a.value === settings.danmaku.area)
  return found ? found.label : `${Math.round(settings.danmaku.area * 100)}%`
})

import { computed } from 'vue'
</script>

<template>
  <div class="dm-panel">
    <div class="dm-preview">
      <span
        class="dm-sample"
        :style="{
          fontSize: settings.danmaku.fontSize + 'px',
          opacity: settings.danmaku.opacity,
          fontWeight: settings.danmaku.bold ? 700 : 400,
          textShadow: settings.danmaku.stroke
            ? `0 0 ${settings.danmaku.strokeWidth}px #000, 1px 1px ${settings.danmaku.strokeWidth}px #000`
            : 'none',
        }"
        >弹幕预览 SimpleLive LAN ~~~~~~~~~~~~</span
      >
    </div>

    <div class="dm-item">
      <div class="dm-head">
        <span>字号</span><b>{{ settings.danmaku.fontSize }}px</b>
      </div>
      <input type="range" class="dm-slider" min="14" max="40" step="1" v-model.number="settings.danmaku.fontSize" />
    </div>
    <div class="dm-item">
      <div class="dm-head">
        <span>不透明度</span><b>{{ Math.round(settings.danmaku.opacity * 100) }}%</b>
      </div>
      <input type="range" class="dm-slider" min="0.1" max="1" step="0.05" v-model.number="settings.danmaku.opacity" />
    </div>
    <div class="dm-item">
      <div class="dm-head">
        <span>滚动速度</span><b>×{{ settings.danmaku.speed.toFixed(1) }}</b>
      </div>
      <input type="range" class="dm-slider" min="0.5" max="3" step="0.1" v-model.number="settings.danmaku.speed" />
    </div>
    <div class="dm-item">
      <div class="dm-head">
        <span>显示区域</span><b>{{ areaLabel }}</b>
      </div>
      <div class="dm-seg">
        <button
          v-for="a in areaOptions"
          :key="a.value"
          :class="{ on: settings.danmaku.area === a.value }"
          @click="settings.danmaku.area = a.value"
        >
          {{ a.label }}
        </button>
      </div>
    </div>
    <div class="dm-item">
      <div class="dm-head"><span>行数</span><b>{{ settings.danmaku.maxRows }}</b></div>
      <input type="range" class="dm-slider" min="2" max="15" step="1" v-model.number="settings.danmaku.maxRows" />
    </div>
    <div class="dm-item">
      <div class="dm-head">
        <span>密度（同屏最多）</span><b>{{ settings.danmaku.density }} 条</b>
      </div>
      <input type="range" class="dm-slider" min="5" max="50" step="1" v-model.number="settings.danmaku.density" />
    </div>
    <div class="dm-toggles">
      <label><input type="checkbox" v-model="settings.danmaku.stroke" /> 弹幕描边</label>
      <template v-if="settings.danmaku.stroke">
        <span class="dm-tg-label">描边宽度 {{ settings.danmaku.strokeWidth }}px</span>
        <input type="range" class="dm-slider dm-slider-sm" min="1" max="4" step="1" v-model.number="settings.danmaku.strokeWidth" />
      </template>
      <label><input type="checkbox" v-model="settings.danmaku.bold" /> 粗体字重</label>
      <label><input type="checkbox" v-model="settings.danmaku.emoji" /> 显示弹幕表情</label>
    </div>
  </div>
</template>

<style scoped>
.dm-preview {
  background: #000;
  border-radius: 10px;
  height: 56px;
  display: flex;
  align-items: center;
  overflow: hidden;
  padding: 0 12px;
  margin-bottom: 12px;
}
.dm-sample {
  color: #fff;
  white-space: nowrap;
  animation: dm-slide 6s linear infinite;
}
@keyframes dm-slide {
  from {
    transform: translateX(100%);
  }
  to {
    transform: translateX(-100%);
  }
}
.dm-item {
  padding: 8px 0;
}
.dm-head {
  display: flex;
  justify-content: space-between;
  font-size: 13.5px;
  color: var(--text-secondary);
  margin-bottom: 6px;
}
.dm-head b {
  color: var(--text);
  font-weight: 600;
}
.dm-slider {
  width: 100%;
  height: 4px;
  -webkit-appearance: none;
  appearance: none;
  border-radius: 2px;
  background: var(--border);
  outline: none;
}
.dm-slider::-webkit-slider-thumb {
  -webkit-appearance: none;
  width: 18px;
  height: 18px;
  border-radius: 50%;
  background: var(--accent);
  cursor: pointer;
}
.dm-seg {
  display: flex;
  gap: 6px;
}
.dm-seg button {
  padding: 6px 14px;
  border-radius: 999px;
  border: 1px solid var(--border);
  background: var(--bg-hover);
  color: var(--text-secondary);
  font-size: 13px;
}
.dm-seg button.on {
  background: var(--accent-weak);
  color: var(--accent);
  border-color: var(--accent);
  font-weight: 600;
}
.dm-toggles {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding-top: 10px;
  border-top: 1px solid var(--border);
}
.dm-toggles label {
  font-size: 13.5px;
  color: var(--text-secondary);
  display: flex;
  align-items: center;
  gap: 8px;
}
.dm-tg-label {
  font-size: 12.5px;
  color: var(--text-tertiary);
}
.dm-slider-sm {
  width: 140px;
}
</style>
