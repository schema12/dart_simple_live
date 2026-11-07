import 'dart:async';
import 'dart:collection';

import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_lan_server/src/util/map_utils.dart';

/// 平台站点集合与模型 JSON 转换、缓存管理。
class LiveHub {
  LiveHub({Map<String, LiveSite>? sites}) : _sites = sites ?? _defaultSites() {
    _defaultPlatformOrder = _sites.keys.toList();
  }

  static Map<String, LiveSite> _defaultSites() {
    return {
      'huya': HuyaSite(),
      'douyu': DouyuSite(),
      'bilibili': BiliBiliSite(),
      'douyin': DouyinSite(),
      'kuaishou': KuaishouSite(),
    };
  }

  final Map<String, LiveSite> _sites;
  late List<String> _defaultPlatformOrder;

  /// 平台凭据注入回调（由宿主接入账号/设置体系）。
  Future<Credentials?> Function(String platform)? credentialsProvider;

  /// 房间详情缓存：key -> entry
  final LinkedHashMap<String, _RoomCacheEntry> _roomCache =
      LinkedHashMap<String, _RoomCacheEntry>();
  final LinkedHashMap<String, _QualityCacheEntry> _qualityCache =
      LinkedHashMap<String, _QualityCacheEntry>();
  final LinkedHashMap<String, _UrlCacheEntry> _urlCache =
      LinkedHashMap<String, _UrlCacheEntry>();

  Duration detailTtl = const Duration(seconds: 90);
  Duration qualityTtl = const Duration(seconds: 45);
  Duration urlTtl = const Duration(seconds: 30);
  static const int _maxCacheEntries = 64;

  LiveSite site(String platform) {
    final s = _sites[platform];
    if (s == null) {
      throw ArgumentError.value(platform, 'platform', '不支持的平台');
    }
    return s;
  }

  bool supports(String platform) => _sites.containsKey(platform);

  List<Map<String, String>> platforms() => _defaultPlatformOrder
      .map((id) => {'id': id, 'name': _sites[id]!.name})
      .toList();

  String keyOf(String platform, String roomId) => '$platform::$roomId';

  /// 应用平台凭据（登录 Cookie 等）。
  Future<void> applyCredentials(Credentials credentials) async {
    final provider = credentialsProvider;
    if (provider != null) {
      final c = await provider(credentials.platform);
      if (c != null) {
        _apply(credentials.platform, c);
        return;
      }
    }
    _apply(credentials.platform, credentials);
  }

  void _apply(String platform, Credentials c) {
    switch (platform) {
      case 'bilibili':
        final bili = site('bilibili') as BiliBiliSite;
        bili.cookie = c.cookie;
        if (c.userId != null && c.userId! > 0) {
          bili.userId = c.userId!;
        }
        break;
      case 'douyu':
        final douyu = site('douyu') as DouyuSite;
        douyu.cookie = c.cookie;
        if (c.deviceId != null) {
          douyu.deviceId = c.deviceId!;
        }
        break;
      case 'huya':
        // 虎牙当前无需 Cookie
        break;
      default:
        break;
    }
  }

  /// 获取房间详情（带缓存）。
  Future<LiveRoomDetail> getRoomDetail(
    String platform,
    String roomId, {
    bool forceRefresh = false,
  }) async {
    final key = keyOf(platform, roomId);
    final entry = _roomCache[key];
    if (!forceRefresh && entry != null && !entry.isExpired(detailTtl)) {
      _roomCache.setEntryFirst(key, entry);
      return entry.detail;
    }
    final detail = await site(platform).getRoomDetail(roomId: roomId);
    _roomCache[key] = _RoomCacheEntry(detail, DateTime.now());
    _roomCache.setEntryFirst(key, _roomCache[key]!);
    _trim(_roomCache);
    // 详情刷新后，画质/地址缓存一并失效
    _qualityCache.remove(key);
    _urlCache.remove(key);
    return detail;
  }

  /// 获取画质列表（带缓存）。
  Future<List<LivePlayQuality>> getPlayQualites(
    String platform,
    LiveRoomDetail detail,
  ) async {
    final key = keyOf(platform, detail.roomId);
    final entry = _qualityCache[key];
    if (entry != null && !entry.isExpired(qualityTtl)) {
      _qualityCache.setEntryFirst(key, entry);
      return entry.qualities;
    }
    final qualities = await site(platform).getPlayQualites(detail: detail);
    _qualityCache[key] = _QualityCacheEntry(qualities, DateTime.now());
    _qualityCache.setEntryFirst(key, _qualityCache[key]!);
    _trim(_qualityCache);
    return qualities;
  }

  /// 获取播放地址（带缓存）。
  Future<LivePlayUrl> getPlayUrls(
    String platform,
    LiveRoomDetail detail,
    LivePlayQuality quality,
  ) async {
    final key = '${keyOf(platform, detail.roomId)}#${quality.quality}';
    final entry = _urlCache[key];
    if (entry != null && !entry.isExpired(urlTtl)) {
      _urlCache.setEntryFirst(key, entry);
      return entry.url;
    }
    final url = await site(platform).getPlayUrls(detail: detail, quality: quality);
    _urlCache[key] = _UrlCacheEntry(url, DateTime.now());
    _urlCache.setEntryFirst(key, _urlCache[key]!);
    _trim(_urlCache);
    return url;
  }

  /// 房间详情缓存中的弹幕参数（供弹幕连接使用），未命中返回 null。
  LiveRoomDetail? cachedDetail(String platform, String roomId) {
    final key = keyOf(platform, roomId);
    final entry = _roomCache[key];
    if (entry == null || entry.isExpired(detailTtl)) {
      return null;
    }
    return entry.detail;
  }

  void _trim(LinkedHashMap map) {
    while (map.length > _maxCacheEntries) {
      map.remove(map.keys.first);
    }
  }

  void clearCaches() {
    _roomCache.clear();
    _qualityCache.clear();
    _urlCache.clear();
  }
}

/// 平台凭据。
class Credentials {
  final String platform;
  final String cookie;
  final int? userId;
  final String? deviceId;
  Credentials({
    required this.platform,
    this.cookie = '',
    this.userId,
    this.deviceId,
  });
}

class _RoomCacheEntry {
  final LiveRoomDetail detail;
  final DateTime cachedAt;
  _RoomCacheEntry(this.detail, this.cachedAt);
  bool isExpired(Duration ttl) =>
      DateTime.now().difference(cachedAt) > ttl;
}

class _QualityCacheEntry {
  final List<LivePlayQuality> qualities;
  final DateTime cachedAt;
  _QualityCacheEntry(this.qualities, this.cachedAt);
  bool isExpired(Duration ttl) =>
      DateTime.now().difference(cachedAt) > ttl;
}

class _UrlCacheEntry {
  final LivePlayUrl url;
  final DateTime cachedAt;
  _UrlCacheEntry(this.url, this.cachedAt);
  bool isExpired(Duration ttl) =>
      DateTime.now().difference(cachedAt) > ttl;
}

// ---------------------------------------------------------------------------
// 模型 -> JSON
// ---------------------------------------------------------------------------

/// 直播间卡片。
Map<String, Object?> roomItemJson(String platform, LiveRoomItem item) {
  return {
    'platform': platform,
    'roomId': item.roomId,
    'title': item.title,
    'cover': item.cover,
    'userName': item.userName,
    'online': item.online,
  };
}

/// 主播搜索结果。
Map<String, Object?> anchorItemJson(String platform, LiveAnchorItem item) {
  return {
    'platform': platform,
    'roomId': item.roomId,
    'userName': item.userName,
    'avatar': item.avatar,
    'liveStatus': item.liveStatus,
  };
}

/// 房间详情（不包含平台弹幕参数与内部 data，避免泄露令牌/Cookie）。
Map<String, Object?> roomDetailJson(String platform, LiveRoomDetail detail) {
  return {
    'platform': platform,
    'roomId': detail.roomId,
    'title': detail.title,
    'cover': detail.cover,
    'userName': detail.userName,
    'userAvatar': detail.userAvatar,
    'online': detail.online,
    'introduction': detail.introduction ?? '',
    'notice': detail.notice ?? '',
    'status': detail.status,
    'isRecord': detail.isRecord,
    'showTime': detail.showTime,
    'url': detail.url,
    'categoryId': detail.categoryId,
    'categoryName': detail.categoryName,
    'categoryParentId': detail.categoryParentId,
    'categoryParentName': detail.categoryParentName,
    'categoryPic': detail.categoryPic,
  };
}

/// 分类（含多级子分类）。
Map<String, Object?> categoryJson(LiveCategory category) {
  return {
    'id': category.id,
    'name': category.name,
    'pic': category.pic,
    'children': category.children.map(subCategoryJson).toList(),
  };
}

Map<String, Object?> subCategoryJson(LiveSubCategory sub) {
  return {
    'id': sub.id,
    'name': sub.name,
    'parentId': sub.parentId,
    'pic': sub.pic,
    'children': sub.children.map(subCategoryJson).toList(),
  };
}

/// 播放地址格式推断。
String detectFormat(String url) {
  final lower = url.toLowerCase();
  if (lower.contains('.m3u8')) {
    return 'hls';
  }
  if (lower.contains('.flv')) {
    return 'flv';
  }
  if (lower.contains('.mp4')) {
    return 'mp4';
  }
  if (lower.contains('.ts')) {
    return 'ts';
  }
  return 'unknown';
}

/// 画质列表 JSON（index 作为外部引用 ID）。
List<Map<String, Object?>> qualitiesJson(List<LivePlayQuality> qualities) {
  final result = <Map<String, Object?>>[];
  for (var i = 0; i < qualities.length; i++) {
    result.add({'index': i, 'quality': qualities[i].quality});
  }
  return result;
}
