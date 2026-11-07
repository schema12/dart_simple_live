/// SimpleLive 局域网服务端。
///
/// 将 simple_live_core 的平台解析能力以 HTTP API + WebSocket 弹幕的形式
/// 提供给局域网内的 Web 客户端（iPad Safari / Chrome 等）。
///
/// 设计原则：
/// - 手机端复用 simple_live_core，浏览器只负责呈现与播放；
/// - 默认不做视频转发，仅在浏览器无法直连 CDN 时提供可选代理；
/// - 同源部署：Web 静态资源与 API 由同一个 HttpServer 提供；
/// - 访问令牌 + Host/Origin 校验，避免成为开放代理。
library simple_live_lan_server;

export 'src/lan_server.dart';
export 'src/lan_server_config.dart';
export 'src/auth/access_control.dart';
export 'src/live/live_hub.dart';
export 'src/danmaku/danmaku_hub.dart';
export 'src/proxy/stream_proxy.dart';
export 'src/static/static_files.dart';
export 'src/util/ip_utils.dart';
