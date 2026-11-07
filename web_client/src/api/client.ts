/** API 客户端：同源请求 + 令牌鉴权 + 统一错误处理。 */

const TOKEN_KEY = 'sl_lan_token'
const CLIENT_KEY = 'sl_lan_client'

export class ApiError extends Error {
  status: number
  constructor(message: string, status: number) {
    super(message)
    this.status = status
  }
}

/** 未授权事件监听（用于跳转配对页）。 */
type UnauthorizedListener = () => void
const unauthorizedListeners: UnauthorizedListener[] = []

export function onUnauthorized(fn: UnauthorizedListener): () => void {
  unauthorizedListeners.push(fn)
  return () => {
    const i = unauthorizedListeners.indexOf(fn)
    if (i >= 0) unauthorizedListeners.splice(i, 1)
  }
}

function notifyUnauthorized(): void {
  unauthorizedListeners.forEach((fn) => fn())
}

// ---------------------------------------------------------------------------
// 令牌与客户端 ID
// ---------------------------------------------------------------------------

export function getToken(): string {
  return localStorage.getItem(TOKEN_KEY) ?? ''
}

export function setToken(token: string): void {
  localStorage.setItem(TOKEN_KEY, token)
}

export function clearToken(): void {
  localStorage.removeItem(TOKEN_KEY)
}

export function getClientId(): string {
  let id = localStorage.getItem(CLIENT_KEY) ?? ''
  if (!id) {
    id =
      typeof crypto !== 'undefined' && 'randomUUID' in crypto
        ? crypto.randomUUID()
        : `web-${Date.now()}-${Math.floor(Math.random() * 1e9).toString(36)}`
    localStorage.setItem(CLIENT_KEY, id)
  }
  return id
}

/** 启动时从 URL 捕获配对令牌（?token= 或 #/token=）。 */
export function captureTokenFromLocation(): string | null {
  const url = new URL(window.location.href)
  let candidate: string | null = null

  const queryToken = url.searchParams.get('token')
  if (queryToken) {
    candidate = queryToken
    // 从查询串中移除，避免令牌出现在历史记录/刷新请求中
    url.searchParams.delete('token')
    window.history.replaceState(null, '', url.pathname + url.search + url.hash)
  }

  if (!candidate) {
    const hash = window.location.hash
    const m = hash.match(/token=([0-9a-fA-F]{16,64})/)
    if (m) {
      candidate = m[1]
      window.history.replaceState(
        null,
        '',
        url.pathname + url.search + hash.replace(/token=[0-9a-fA-F]{16,64}/, ''),
      )
    }
  }

  if (candidate) {
    setToken(candidate)
    return candidate
  }
  return null
}

// ---------------------------------------------------------------------------
// 请求封装
// ---------------------------------------------------------------------------

interface Envelope<T> {
  code: number
  message: string
  data: T
}

export async function request<T>(
  path: string,
  params: Record<string, string | number | undefined> = {},
  options: { timeoutMs?: number; method?: string } = {},
): Promise<T> {
  const qs = new URLSearchParams()
  Object.entries(params).forEach(([k, v]) => {
    if (v !== undefined && v !== '') qs.set(k, String(v))
  })
  qs.set('token', getToken())
  qs.set('client', getClientId())

  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), options.timeoutMs ?? 25000)
  let resp: Response
  try {
    resp = await fetch(`${path}?${qs.toString()}`, {
      method: options.method ?? 'GET',
      signal: controller.signal,
      headers: { 'X-LAN-Token': getToken(), 'X-LAN-Client': getClientId() },
    })
  } catch (e) {
    clearTimeout(timeout)
    if ((e as Error).name === 'AbortError') {
      throw new ApiError('请求超时，请检查手机与网络的连接', 0)
    }
    throw new ApiError('无法连接局域网服务器', 0)
  }
  clearTimeout(timeout)

  if (resp.status === 403) {
    notifyUnauthorized()
    let msg = '访问被拒绝'
    try {
      const body = (await resp.json()) as Envelope<unknown>
      if (body?.message) msg = body.message
    } catch {
      /* ignore */
    }
    throw new ApiError(msg, 403)
  }

  let body: Envelope<T>
  try {
    body = (await resp.json()) as Envelope<T>
  } catch {
    throw new ApiError(`服务器响应异常（HTTP ${resp.status}）`, resp.status)
  }
  if (resp.status !== 200 || body.code !== 0) {
    throw new ApiError(body.message || `请求失败（HTTP ${resp.status}）`, resp.status)
  }
  return body.data
}

// ---------------------------------------------------------------------------
// 具体接口
// ---------------------------------------------------------------------------

import type {
  AnchorItem,
  Category,
  ClientInfo,
  LogEntry,
  PlatformInfo,
  RoomDetail,
  RoomItem,
  RoomListResult,
  SearchResults,
  ServerInfo,
  StreamInfo,
  SubCategory,
  QualityInfo,
} from './types'

export const api = {
  platforms: () => request<PlatformInfo[]>('/api/platforms'),
  categories: (platform: string) =>
    request<Category[]>('/api/categories', { platform }),
  recommend: (platform: string, page = 1) =>
    request<RoomListResult>('/api/recommend', { platform, page }),
  categoryRooms: (
    platform: string,
    category: string,
    parent: string,
    page = 1,
  ) =>
    request<RoomListResult>('/api/rooms', {
      platform,
      category,
      parent,
      page,
      name: category,
    }),
  search: (platform: string, keyword: string, page = 1) =>
    request<SearchResults>('/api/search', { platform, keyword, page }),
  room: (platform: string, id: string, refresh = false) =>
    request<RoomDetail>('/api/room', { platform, id, refresh: refresh ? '1' : undefined }),
  qualities: (platform: string, id: string) =>
    request<{ qualities: QualityInfo[] }>('/api/qualities', { platform, id }),
  stream: (
    platform: string,
    id: string,
    quality = 0,
    proxy: 'auto' | '1' | '0' = 'auto',
  ) => request<StreamInfo>('/api/stream', { platform, id, quality, proxy }),
  server: () => request<ServerInfo>('/api/server'),
  clients: () => request<ClientInfo[]>('/api/clients'),
  revokeClient: (id: string) =>
    request<{ revoked: boolean }>(`/api/clients/${encodeURIComponent(id)}`, {}, { method: 'DELETE' }),
  resetToken: () =>
    request<{ token: string }>('/api/token/reset', {}, { method: 'POST' }),
  logs: () => request<LogEntry[]>('/api/logs'),
}

// ---------------------------------------------------------------------------
// WebSocket
// ---------------------------------------------------------------------------

/** 给服务器相对路径（如 /api/proxy/<id>）附加鉴权参数（用于 video src 等无法自定义头的场景）。 */
export function withToken(path: string): string {
  const sep = path.includes('?') ? '&' : '?'
  return `${path}${sep}token=${encodeURIComponent(getToken())}&client=${encodeURIComponent(getClientId())}`
}

export function danmakuWsUrl(platform: string, roomId: string): string {
  const proto = window.location.protocol === 'https:' ? 'wss' : 'ws'
  const qs = new URLSearchParams({
    platform,
    id: roomId,
    token: getToken(),
    client: getClientId(),
  })
  return `${proto}://${window.location.host}/api/danmaku?${qs.toString()}`
}
