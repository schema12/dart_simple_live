/** 后端 API 类型定义（与 simple_live_lan_server 的响应结构对应）。 */

export type PlatformId = 'huya' | 'douyu' | 'bilibili'

export interface PlatformInfo {
  id: string
  name: string
}

export interface RoomItem {
  platform: PlatformId
  roomId: string
  title: string
  cover: string
  userName: string
  online: number
}

export interface AnchorItem {
  platform: PlatformId
  roomId: string
  userName: string
  avatar: string
  liveStatus: boolean
}

export interface SubCategory {
  id: string
  name: string
  parentId: string
  pic?: string
  children?: SubCategory[]
}

export interface Category {
  id: string
  name: string
  pic?: string
  children: SubCategory[]
}

export interface RoomDetail {
  platform: PlatformId
  roomId: string
  title: string
  cover: string
  userName: string
  userAvatar: string
  online: number
  introduction: string
  notice: string
  status: boolean
  isRecord: boolean
  showTime?: string
  url: string
  categoryId?: string
  categoryName?: string
  categoryParentId?: string
  categoryParentName?: string
  categoryPic?: string
}

export interface QualityInfo {
  index: number
  quality: string
}

export interface StreamUrl {
  url: string
  format: 'hls' | 'flv' | 'mp4' | 'ts' | 'unknown'
  proxy?: string
}

export interface StreamInfo {
  platform: PlatformId
  roomId: string
  quality: number
  qualityName: string
  availableQualities: QualityInfo[]
  headers: Record<string, string>
  urls: StreamUrl[]
  defaultProxy: boolean
}

export interface SearchResults {
  platform: PlatformId
  keyword: string
  page: number
  rooms: RoomItem[]
  anchors: AnchorItem[]
  hasMore: boolean
}

export interface RoomListResult {
  platform: PlatformId
  page: number
  hasMore: boolean
  items: RoomItem[]
}

export interface ServerInfo {
  name: string
  version: string
  status: string
  port: number
  addresses: string[]
  uptimeSec: number
  requests: number
  wsClients: number
  activeClients: number
  danmakuRooms: number
  defaultProxy: boolean
}

export interface ClientInfo {
  id: string
  userAgent: string
  firstSeen: string
  lastSeen: string
  requests: number
  revoked: boolean
}

export interface LogEntry {
  time: string
  method: string
  path: string
  query: Record<string, string>
  remote: string
  client: string
  status?: number
  elapsedMs?: number
}

/** WebSocket 弹幕统一消息。 */
export type DanmakuMessage =
  | { type: 'hello'; platform: string; roomId: string; clients: number; online?: number }
  | { type: 'chat'; user: string; text: string; color: string; images?: string[]; spans?: DanmakuSpan[]; ts: number }
  | { type: 'gift'; user: string; text: string; color: string; ts: number }
  | { type: 'online'; online: number }
  | {
      type: 'superChat'
      id?: string
      user: string
      face: string
      message: string
      price: number
      backgroundColor: string
      backgroundBottomColor: string
      startTime: string
      endTime: string
    }
  | { type: 'clients'; clients: number }
  | { type: 'reconnecting'; message: string }
  | { type: 'error'; message: string }
  | { type: 'pong'; ts: number }
  | { type: 'bye' }

export interface DanmakuSpan {
  text?: string
  img?: string
}
