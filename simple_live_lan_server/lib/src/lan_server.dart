import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_lan_server/src/auth/access_control.dart';
import 'package:simple_live_lan_server/src/danmaku/danmaku_hub.dart';
import 'package:simple_live_lan_server/src/lan_server_config.dart';
import 'package:simple_live_lan_server/src/live/live_hub.dart';
import 'package:simple_live_lan_server/src/proxy/stream_proxy.dart';
import 'package:simple_live_lan_server/src/static/static_files.dart';
import 'package:simple_live_lan_server/src/util/http_helpers.dart';
import 'package:simple_live_lan_server/src/util/ip_utils.dart';

/// 虎牙 HLS 取流 UA：实测 iPad Safari UA 可通过 hls.huya.com 的 UA 指纹校验。
const kHuyaHlsUserAgent =
    'Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

/// 服务状态。
enum LanServerStatus { stopped, starting, running, error }

/// 服务事件（供 UI 订阅刷新状态/二维码）。
class LanServerEvent {
  final String type;
  final Object? data;
  LanServerEvent(this.type, [this.data]);
}

/// SimpleLive 局域网服务器。
///
/// - HTTP：/api/*（业务接口）、/api/proxy/*（可选视频代理）、其余路径为 Web 静态资源；
/// - WebSocket：/api/danmaku 弹幕转发；
/// - 全部请求经过 [AccessControl]（令牌 + Host/Origin + 限流）。
class LanServer {
  LanServer({
    required this.config,
    required this.assetSource,
    LiveHub? hub,
    StreamProxy? proxy,
    this.followsProvider,
  })  : hub = hub ?? LiveHub(),
        proxy = proxy ?? StreamProxy() {
    accessControl = AccessControl(token: config.initialToken ?? '');
    danmakuHub = DanmakuHub(
      hub: this.hub,
      idleClose: config.danmakuIdleClose,
      maxRooms: config.maxDanmakuRooms,
    );
    staticFiles = StaticFiles(assetSource);
  }

  final LanServerConfig config;
  final AssetSource assetSource;

  late AccessControl accessControl;
  late final DanmakuHub danmakuHub;
  late final StaticFiles staticFiles;
  final LiveHub hub;
  final StreamProxy proxy;

  /// 手机端关注列表提供者（宿主注入，供 Web 客户端导入）。
  Future<List<Map<String, Object?>>> Function()? followsProvider;

  HttpServer? _server;
  LanServerStatus _status = LanServerStatus.stopped;
  int _port = 0;
  List<String> _addresses = [];
  DateTime? _startedAt;
  int _requestCount = 0;
  Timer? _addressTimer;
  final StreamController<LanServerEvent> _events =
      StreamController<LanServerEvent>.broadcast();

  LanServerStatus get status => _status;
  int get port => _port;
  List<String> get addresses => List.unmodifiable(_addresses);
  int get requestCount => _requestCount;
  int get wsClientCount => danmakuHub.sessionCount;
  DateTime? get startedAt => _startedAt;

  /// 5 分钟内活跃过的客户端数量（供手机端显示“已连接设备”）。
  int get activeClientCount {
    final now = DateTime.now();
    return accessControl
        .listClients()
        .where((c) =>
            DateTime.tryParse(c['lastSeen'] as String? ?? '') != null &&
            now.difference(
                  DateTime.parse(c['lastSeen'] as String),
                ).inMinutes <
                5)
        .length;
  }

  Stream<LanServerEvent> get events => _events.stream;

  /// 访问入口地址（含令牌，用于二维码）。
  Future<String> entryUrl({required String token}) async {
    final ip = _addresses.isNotEmpty ? _addresses.first : '';
    if (ip.isEmpty) {
      return 'http://localhost:$_port/?token=$token';
    }
    return 'http://$ip:$_port/?token=$token';
  }

  /// 启动服务。返回实际监听端口。
  Future<int> start() async {
    if (_status == LanServerStatus.running ||
        _status == LanServerStatus.starting) {
      return _port;
    }
    _status = LanServerStatus.starting;
    try {
      // 初始化令牌
      if (config.initialToken != null && config.initialToken!.isNotEmpty) {
        accessControl = AccessControl(token: config.initialToken!);
      } else {
        final saved = await config.tokenLoader?.call();
        if (saved != null && saved.isNotEmpty) {
          accessControl = AccessControl(token: saved);
        } else {
          accessControl = AccessControl(token: AccessControl.generateToken());
          await config.tokenSaver?.call(accessControl.token);
        }
      }

      // 恢复平台凭据
      await _restoreCredentials();

      HttpServer? bound;
      Object? lastError;
      for (var i = 0; i <= config.portFallbackRange; i++) {
        final tryPort = config.defaultPort + i;
        try {
          bound = await HttpServer.bind(
            InternetAddress.anyIPv4,
            tryPort,
            shared: false,
          );
          lastError = null;
          break;
        } catch (e) {
          lastError = e;
        }
      }
      if (lastError != null && bound == null && config.portFallbackRange < 0) {
        throw lastError;
      }
      bound ??= await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _server = bound;
      _port = bound.port;
      _startedAt = DateTime.now();
      _requestCount = 0;
      bound.listen(
        _handleRequest,
        onError: (Object e) {
          _events.add(LanServerEvent('error', e.toString()));
        },
        cancelOnError: false,
      );
      _status = LanServerStatus.running;
      await _refreshAddresses();
      _addressTimer?.cancel();
      _addressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        _refreshAddresses();
      });
      _events.add(
        LanServerEvent('started', {'port': _port, 'addresses': _addresses}),
      );
      return _port;
    } catch (e) {
      _status = LanServerStatus.error;
      _events.add(LanServerEvent('error', e.toString()));
      rethrow;
    }
  }

  Future<void> _restoreCredentials() async {
    for (final platform in ['bilibili', 'douyu']) {
      try {
        final provider = hub.credentialsProvider;
        if (provider == null) {
          continue;
        }
        final c = await provider(platform);
        if (c != null) {
          await hub.applyCredentials(
            Credentials(
              platform: platform,
              cookie: c.cookie,
              userId: c.userId,
              deviceId: c.deviceId,
            ),
          );
        }
      } catch (_) {
        // 凭据恢复失败不阻塞服务启动
      }
    }
  }

  Future<void> _refreshAddresses() async {
    final list = await IpUtils.lanIpv4Addresses();
    final changed =
        list.length != _addresses.length ||
            !list.every(_addresses.contains);
    _addresses = list;
    if (changed) {
      _events.add(LanServerEvent('addressesChanged', _addresses));
    }
  }

  /// 停止服务并释放全部资源。
  Future<void> stop() async {
    _addressTimer?.cancel();
    _addressTimer = null;
    await danmakuHub.disposeAll();
    await proxy.dispose();
    try {
      await _server?.close(force: true);
    } catch (_) {
      // ignore
    }
    _server = null;
    _status = LanServerStatus.stopped;
    _port = 0;
    _startedAt = null;
    _events.add(LanServerEvent('stopped'));
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final sw = Stopwatch()..start();
    _requestCount++;
    final path = request.uri.path;

    // 健康检查：无令牌（仅返回极少信息）
    if (path == '/api/health') {
      await HttpHelpers.guard(request, () async {
        await HttpHelpers.ok(request, {
          'ok': true,
          'name': config.serverName,
          'version': config.version,
        });
      });
      accessControl.completeLog(request, 200, sw.elapsedMilliseconds);
      return;
    }

    // 访问控制：API 需要令牌；静态资源仅做 Host/Origin/限流校验（配对页需无令牌可加载）
    final requireToken = path.startsWith('/api/');
    final denial = accessControl.validate(request, requireToken: requireToken);
    if (denial != null) {
      await HttpHelpers.error(request, HttpStatus.forbidden, denial);
      accessControl.completeLog(request, 403, sw.elapsedMilliseconds);
      return;
    }

    // WebSocket 弹幕
    if (path == '/api/danmaku') {
      await _handleDanmakuWs(request);
      accessControl.completeLog(request, 101, sw.elapsedMilliseconds);
      return;
    }

    if (path.startsWith('/api/proxy/')) {
      final id = path.substring('/api/proxy/'.length);
      await proxy.handle(request, id);
      accessControl.completeLog(request, 200, sw.elapsedMilliseconds);
      return;
    }

    if (path.startsWith('/api/')) {
      await HttpHelpers.guard(
        request,
        () => _handleApi(request),
        onError: (e, s) {
          _events.add(LanServerEvent('apiError', '$e'));
        },
      );
      accessControl.completeLog(
        request,
        request.response.statusCode,
        sw.elapsedMilliseconds,
      );
      return;
    }

    if (request.method != 'GET' && request.method != 'HEAD') {
      await HttpHelpers.error(request, HttpStatus.methodNotAllowed, '不支持的方法');
      accessControl.completeLog(request, 405, sw.elapsedMilliseconds);
      return;
    }

    final served = await staticFiles.handle(request);
    if (!served) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        'text/plain; charset=utf-8',
      );
      request.response.write('Not Found');
      await request.response.close();
    }
    accessControl.completeLog(
      request,
      request.response.statusCode,
      sw.elapsedMilliseconds,
    );
  }

  // ---------------------------------------------------------------------------
  // API 路由
  // ---------------------------------------------------------------------------

  Future<void> _handleApi(HttpRequest request) async {
    final path = request.uri.path;
    // /api/clients/<id>（撤销客户端）
    if (path.startsWith('/api/clients/')) {
      return _apiClients(request);
    }
    switch (path) {
      // ignore: no_default_cases — default 分支在末尾返回 404
      case '/api/platforms':
        await HttpHelpers.ok(request, hub.platforms());
        return;
      case '/api/categories':
        return _apiCategories(request);
      case '/api/recommend':
        return _apiRecommend(request);
      case '/api/rooms':
        return _apiCategoryRooms(request);
      case '/api/search':
        return _apiSearch(request);
      case '/api/room':
        return _apiRoom(request);
      case '/api/qualities':
        return _apiQualities(request);
      case '/api/stream':
        return _apiStream(request);
      case '/api/clients':
        return _apiClients(request);
      case '/api/token/reset':
        return _apiTokenReset(request);
      case '/api/server':
        return _apiServerInfo(request);
      case '/api/follows':
        return _apiFollows(request);
      case '/api/logs':
        await HttpHelpers.ok(request, accessControl.recentLogs());
        return;
      default:
        await HttpHelpers.error(request, HttpStatus.notFound, '未知接口: $path');
    }
  }

  Future<void> _apiCategories(HttpRequest request) async {
    final platform = HttpHelpers.requireParam(request, 'platform');
    final categories = await hub.site(platform).getCategores();
    await HttpHelpers.ok(
      request,
      categories.map(categoryJson).toList(),
    );
  }

  Future<void> _apiRecommend(HttpRequest request) async {
    final platform = HttpHelpers.requireParam(request, 'platform');
    final page = HttpHelpers.intParam(request, 'page', 1);
    final result = await hub.site(platform).getRecommendRooms(page: page);
    await HttpHelpers.ok(request, {
      'platform': platform,
      'page': page,
      'hasMore': result.hasMore,
      'items': result.items.map((e) => roomItemJson(platform, e)).toList(),
    });
  }

  Future<void> _apiCategoryRooms(HttpRequest request) async {
    final platform = HttpHelpers.requireParam(request, 'platform');
    final categoryId = HttpHelpers.requireParam(request, 'category');
    final parentId = HttpHelpers.optionalParam(request, 'parent') ?? '';
    final page = HttpHelpers.intParam(request, 'page', 1);
    final sub = LiveSubCategory(
      id: categoryId,
      parentId: parentId,
      name: HttpHelpers.optionalParam(request, 'name') ?? categoryId,
    );
    final result = await hub.site(platform).getCategoryRooms(sub, page: page);
    await HttpHelpers.ok(request, {
      'platform': platform,
      'page': page,
      'hasMore': result.hasMore,
      'items': result.items.map((e) => roomItemJson(platform, e)).toList(),
    });
  }

  Future<void> _apiSearch(HttpRequest request) async {
    final platform = HttpHelpers.requireParam(request, 'platform');
    final keyword = HttpHelpers.requireParam(request, 'keyword');
    final page = HttpHelpers.intParam(request, 'page', 1);
    final rooms = await hub.site(platform).searchRooms(keyword, page: page);
    final anchors = await hub.site(platform).searchAnchors(keyword, page: page);
    await HttpHelpers.ok(request, {
      'platform': platform,
      'keyword': keyword,
      'page': page,
      'rooms': rooms.items.map((e) => roomItemJson(platform, e)).toList(),
      'anchors': anchors.items.map((e) => anchorItemJson(platform, e)).toList(),
      'hasMore': rooms.hasMore || anchors.hasMore,
    });
  }

  Future<void> _apiRoom(HttpRequest request) async {
    final platform = HttpHelpers.requireParam(request, 'platform');
    final roomId = HttpHelpers.requireParam(request, 'id');
    final refresh = HttpHelpers.optionalParam(request, 'refresh') == '1';
    final detail = await hub.getRoomDetail(platform, roomId, forceRefresh: refresh);
    await HttpHelpers.ok(request, roomDetailJson(platform, detail));
  }

  Future<void> _apiQualities(HttpRequest request) async {
    final platform = HttpHelpers.requireParam(request, 'platform');
    final roomId = HttpHelpers.requireParam(request, 'id');
    final detail = await hub.getRoomDetail(platform, roomId);
    if (!detail.status) {
      await HttpHelpers.error(request, HttpStatus.conflict, '当前未开播');
      return;
    }
    final qualities = await hub.getPlayQualites(platform, detail);
    await HttpHelpers.ok(request, {
      'platform': platform,
      'roomId': roomId,
      'qualities': qualitiesJson(qualities),
    });
  }

  Future<void> _apiStream(HttpRequest request) async {
    final platform = HttpHelpers.requireParam(request, 'platform');
    final roomId = HttpHelpers.requireParam(request, 'id');
    final qualityIndex = HttpHelpers.intParam(request, 'quality', 0);
    final proxyMode = HttpHelpers.optionalParam(request, 'proxy') ?? 'auto';

    final detail = await hub.getRoomDetail(platform, roomId);
    if (!detail.status) {
      await HttpHelpers.error(request, HttpStatus.conflict, '当前未开播');
      return;
    }
    final qualities = await hub.getPlayQualites(platform, detail);
    if (qualities.isEmpty) {
      await HttpHelpers.error(request, HttpStatus.conflict, '未获取到可用画质');
      return;
    }
    final index = qualityIndex.clamp(0, qualities.length - 1);
    final quality = qualities[index];
    final playUrl = await hub.getPlayUrls(platform, detail, quality);

    // 虎牙追加 HLS 线路：分片传输更抗 CDN 切割，且 iPad Safari 可原生播放
    // （原生 HLS 不受 CORS 限制，无需经手机代理）。构造失败不影响 FLV 线路。
    final allUrls = <String>[...playUrl.urls];
    final extraHeaders = playUrl.headers;
    if (platform == 'huya') {
      try {
        final data = quality.data;
        if (data is Map && data['urls'] is List && (data['urls'] as List).isNotEmpty) {
          final line = (data['urls'] as List).first as HuyaLineModel;
          final bitRate = data['bitRate'] is int ? data['bitRate'] as int : 0;
          final anti = _buildHuyaHlsAntiCode(
            line.hlsAntiCode,
            line.streamName,
            line.presenterUid,
          );
          if (anti != null && anti.isNotEmpty) {
            var query = '$anti&codec=264';
            // 实测：hls.huya.com 拒绝原画档 ratio=20000（403），
            // 低档（2000/10000）可用；原画档不带 ratio 即为 HLS 最高码率
            if (bitRate > 0 && bitRate < 19000) {
              query += '&ratio=$bitRate';
            }
            final hlsUrls = ['al', 'tx']
                .map((h) => 'http://$h.hls.huya.com/src/${line.streamName}.m3u8?$query')
                .toList();
            allUrls.insertAll(0, hlsUrls);
          }
        }
      } catch (_) {
        // HLS 构造失败：仅保留 FLV 线路
      }
    }

    // proxy 参数语义：
    // '1'    → 仅返回代理地址
    // '0'    → 仅返回直连地址
    // 'auto' → 同时返回直连与代理地址（客户端先直连后自动回退代理）
    final String useProxy;
    switch (proxyMode) {
      case '1':
        useProxy = 'all';
        break;
      case '0':
        useProxy = 'none';
        break;
      default:
        useProxy = 'auto';
        break;
    }
    final urls = allUrls.map((url) {
      String? proxyPath;
      final fmt = detectFormat(url);
      // UA 策略：虎牙 HLS（hls.huya.com）按 UA 指纹拦截浏览器 UA，
      // 代理时强制使用移动端 UA；FLV/其他平台透传客户端 UA。
      final isHuyaHls = platform == 'huya' && fmt == 'hls';
      final uaMode = isHuyaHls ? 'fixed' : 'client';
      final entryHeaders = isHuyaHls
          ? {'user-agent': kHuyaHlsUserAgent}
          : (extraHeaders ?? const {});
      if (useProxy != 'none') {
        final id = proxy.register(url, headers: entryHeaders, uaMode: uaMode);
        proxyPath = '/api/proxy/$id';
      }
      return {
        'url': url,
        'format': fmt,
        if (proxyPath != null) 'proxy': proxyPath,
      };
    }).toList();

    await HttpHelpers.ok(request, {
      'platform': platform,
      'roomId': roomId,
      'quality': index,
      'qualityName': quality.quality,
      'availableQualities': qualitiesJson(qualities),
      'headers': playUrl.headers ?? {},
      'urls': urls,
      'defaultProxy': config.proxyByDefault,
    });
  }

  Future<void> _apiClients(HttpRequest request) async {
    if (request.method == 'GET') {
      await HttpHelpers.ok(request, accessControl.listClients());
      return;
    }
    if (request.method == 'DELETE') {
      final id = request.uri.pathSegments.length > 2
          ? request.uri.pathSegments[2]
          : HttpHelpers.requireParam(request, 'id');
      final ok = accessControl.revokeClient(id);
      _events.add(LanServerEvent('clientsChanged', activeClientCount));
      await HttpHelpers.ok(request, {'revoked': ok});
      return;
    }
    await HttpHelpers.error(request, HttpStatus.methodNotAllowed, '不支持的方法');
  }

  Future<void> _apiTokenReset(HttpRequest request) async {
    if (request.method != 'POST') {
      await HttpHelpers.error(request, HttpStatus.methodNotAllowed, '不支持的方法');
      return;
    }
    final newToken = accessControl.resetToken();
    await config.tokenSaver?.call(newToken);
    _events.add(LanServerEvent('tokenReset'));
    await HttpHelpers.ok(request, {'token': newToken});
  }

  /// 构造虎牙 HLS 防盗链参数。
  ///
  /// 逻辑与 core 的 buildAntiCode 一致，但输出时对 fm 等值做了 URL 编码：
  /// hlsAntiCode 的 fm 是 base64（含 "+"/"/" 字符），不编码会被 CDN
  /// 解析成空格导致签名校验失败（403）。经实测 iPad/移动 UA + 本构造
  /// 可直接取得 m3u8 与分片（ACAO:*），iPad Safari 可原生直连播放。
  String? _buildHuyaHlsAntiCode(
    String antiCode,
    String stream,
    int presenterUid,
  ) {
    final mapAnti = Uri(query: antiCode).queryParametersAll;
    if (!mapAnti.containsKey('fm') ||
        !mapAnti.containsKey('wsTime') ||
        !mapAnti.containsKey('fs')) {
      return null;
    }
    final ctype = mapAnti['ctype']?.first ?? 'tars_mobile';
    final platformId = int.tryParse(mapAnti['t']?.first ?? '103') ?? 103;
    final isWap = platformId == 103;
    final clacStartTime = DateTime.now().millisecondsSinceEpoch;
    final seqId = presenterUid + clacStartTime;
    final secretHash =
        md5.convert(utf8.encode('$seqId|$ctype|$platformId')).toString();
    int rotl64(int t) {
      final low = t & 0xFFFFFFFF;
      final rotatedLow = ((low << 8) | (low >> 24)) & 0xFFFFFFFF;
      final high = t & ~0xFFFFFFFF;
      return high | rotatedLow;
    }

    final convertUid = rotl64(presenterUid);
    final calcUid = isWap ? presenterUid : convertUid;
    final fm = utf8.decode(
      base64.decode(Uri.decodeComponent(mapAnti['fm']!.first)),
    );
    final secretPrefix = fm.split('_').first;
    final wsTime = mapAnti['wsTime']!.first;
    final secretStr = '${secretPrefix}_${calcUid}_${stream}_${secretHash}_${wsTime}';
    final wsSecret = md5.convert(utf8.encode(secretStr)).toString();
    final rnd = Random();
    final ct = ((int.parse(wsTime, radix: 16) + rnd.nextDouble()) * 1000)
        .toInt();
    final uuid =
        (((ct % 1e10) + rnd.nextDouble()) * 1e3 % 0xFFFFFFFF)
            .toInt()
            .toString();
    final params = <String, String>{
      'wsSecret': wsSecret,
      'wsTime': wsTime,
      'seqid': seqId.toString(),
      'ctype': ctype,
      'ver': '1',
      'fs': mapAnti['fs']!.first,
      'fm': Uri.encodeComponent(mapAnti['fm']!.first),
      't': platformId.toString(),
    };
    if (isWap) {
      params['uid'] = presenterUid.toString();
      params['uuid'] = uuid;
    } else {
      params['u'] = convertUid.toString();
    }
    return params.entries.map((e) => '${e.key}=${e.value}').join('&');
  }

  Future<void> _apiFollows(HttpRequest request) async {
    final provider = followsProvider;
    if (provider == null) {
      await HttpHelpers.ok(request, <Map<String, Object?>>[]);
      return;
    }
    final follows = await provider();
    await HttpHelpers.ok(request, follows);
  }

  Future<void> _apiServerInfo(HttpRequest request) async {
    await _refreshAddresses();
    await HttpHelpers.ok(request, {
      'name': config.serverName,
      'version': config.version,
      'status': _status.name,
      'port': _port,
      'addresses': _addresses,
      'uptimeSec':
          _startedAt == null ? 0 : DateTime.now().difference(_startedAt!).inSeconds,
      'requests': _requestCount,
      'wsClients': wsClientCount,
      'activeClients': activeClientCount,
      'danmakuRooms': danmakuHub.roomCount,
      'defaultProxy': config.proxyByDefault,
    });
  }

  // ---------------------------------------------------------------------------
  // WebSocket 弹幕
  // ---------------------------------------------------------------------------

  Future<void> _handleDanmakuWs(HttpRequest request) async {
    final platform = HttpHelpers.requireParam(request, 'platform');
    final roomId = HttpHelpers.requireParam(request, 'id');
    if (!hub.supports(platform)) {
      await HttpHelpers.error(request, HttpStatus.badRequest, '不支持的平台');
      return;
    }
    final clientId = HttpHelpers.optionalParam(request, 'client') ?? 'unknown';
    try {
      final ws = await WebSocketTransformer.upgrade(request);
      ws.pingInterval = const Duration(seconds: 20);
      final session = DanmakuSession(ws, clientId, platform, roomId);

      ws.listen(
        (data) {
          // 客户端心跳：兼容文本帧与二进制帧
          if (data is String || data is List<int>) {
            try {
              final text = data is String ? data : utf8.decode(data as List<int>);
              final msg = json.decode(text);
              if (msg is Map && msg['type'] == 'ping') {
                session.send({'type': 'pong', 'ts': DateTime.now().millisecondsSinceEpoch});
              }
            } catch (_) {
              // 忽略无法解析的消息
            }
          }
        },
        onDone: () {
          danmakuHub.unsubscribe(session);
        },
        onError: (Object e) {
          danmakuHub.unsubscribe(session);
        },
        cancelOnError: true,
      );

      await danmakuHub.subscribe(session);
    } catch (e) {
      // 升级失败等
      try {
        await HttpHelpers.error(request, HttpStatus.internalServerError, 'WebSocket 建立失败');
      } catch (_) {
        // ignore
      }
    }
  }
}
