/// 局域网服务端配置。
///
/// [tokenLoader] / [tokenSaver] 由宿主（Flutter App / CLI）提供令牌的
/// 持久化实现；未提供时每次启动生成新令牌（Web 端需重新配对）。
class LanServerConfig {
  LanServerConfig({
    this.defaultPort = 8080,
    this.portFallbackRange = 20,
    this.serverName = 'SimpleLive LAN',
    this.version = '1.0.0',
    this.initialToken,
    Future<String?> Function()? tokenLoader,
    Future<void> Function(String token)? tokenSaver,
    this.maxDanmakuRooms = 12,
    this.danmakuIdleClose = const Duration(seconds: 60),
    this.roomDetailCache = const Duration(seconds: 90),
    this.qualityCache = const Duration(seconds: 45),
    this.proxyByDefault = false,
  })  : tokenLoader = tokenLoader,
        tokenSaver = tokenSaver;

  /// 默认端口；被占用时按 [portFallbackRange] 递增重试。
  final int defaultPort;
  final int portFallbackRange;

  final String serverName;
  final String version;

  /// 初始令牌（测试或恢复用）；为空时从 [tokenLoader] 读取或新生成。
  final String? initialToken;
  final Future<String?> Function()? tokenLoader;
  final Future<void> Function(String token)? tokenSaver;

  /// 同时保持的弹幕房间上限（LRU 淘汰）。
  final int maxDanmakuRooms;

  /// 最后一个客户端离开后多久关闭平台弹幕连接。
  final Duration danmakuIdleClose;

  /// 房间详情缓存时长。
  final Duration roomDetailCache;

  /// 画质列表缓存时长。
  final Duration qualityCache;

  /// /api/stream 默认是否附带代理地址（false=默认直连 CDN）。
  final bool proxyByDefault;
}
