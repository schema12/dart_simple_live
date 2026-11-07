import { reactive, computed } from 'vue'
import { captureTokenFromLocation, clearToken, getToken } from '../api/client'

/** 配对状态：令牌存在即视为已配对。 */
const state = reactive({
  token: '',
  initialized: false,
})

function init(): void {
  if (state.initialized) return
  captureTokenFromLocation()
  state.token = getToken()
  state.initialized = true
}

export function usePairing() {
  init()
  const paired = computed(() => state.token.length > 0)
  function refresh(): void {
    state.token = getToken()
  }
  function unpair(): void {
    clearToken()
    state.token = ''
  }
  return { state, paired, refresh, unpair }
}
