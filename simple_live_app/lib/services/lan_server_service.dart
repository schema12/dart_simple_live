import 'dart:async';

import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_lan_server/simple_live_lan_server.dart';

/// 局域网服务器服务：管理 LanServer 生命周期与 Android 前台服务。
class LanServerService extends GetxService {
  static LanServerService get instance => Get.find<LanServerService>();

  static const MethodChannel _channel = MethodChannel('simple_live/lan_server');

  /// 服务状态
  final status = LanServerStatus.stopped.obs;
  final port = 0.obs;
  final addresses = <String>[].obs;
  final activeClients = 0.obs;
  final wsClients = 0.obs;
  final danmakuRooms = 0.obs;
  final token = ''.obs;
  final entryUrl = ''.obs;
  final errorText = ''.obs;

  LanServer? _server;
  StreamSubscription<LanServerEvent>? _eventSub;
  Timer? _statsTimer;

  bool get isRunning => status.value == LanServerStatus.running;

  /// 构建共享 App 站点实例的 LiveHub（Cookie/BUVID/WBI 缓存与 App 内一致）。
  LiveHub buildHub() {
    LiveSite? siteOf(String id) => Sites.allSites[id]?.liveSite;
    return LiveHub(
      sites: {
        'huya': siteOf('huya') ?? HuyaSite(),
        'douyu': siteOf('douyu') ?? DouyuSite(),
        'bilibili': siteOf('bilibili') ?? BiliBiliSite(),
        'douyin': siteOf('douyin') ?? DouyinSite(),
        'kuaishou': siteOf('kuaishou') ?? KuaishouSite(),
      },
    );
  }

  Future<void> start() async {
    if (isRunning || status.value == LanServerStatus.starting) {
      return;
    }
    status.value = LanServerStatus.starting;
    errorText.value = '';
    try {
      final savedToken = LocalStorageService.instance
          .getValue<String>(LocalStorageService.kLanServerToken, "");
      _server ??= LanServer(
        config: LanServerConfig(
          defaultPort: 8080,
          version: Utils.packageInfo.version,
          serverName: 'SimpleLive LAN',
          initialToken: savedToken.isNotEmpty ? savedToken : null,
          tokenSaver: (t) async {
            LocalStorageService.instance.setValue(
              LocalStorageService.kLanServerToken,
              t,
            );
          },
        ),
        assetSource: FlutterAssetSource(),
        hub: buildHub(),
      );

      _eventSub ??= _server!.events.listen(_onEvent);
      final boundPort = await _server!.start();

      _statsTimer?.cancel();
      _statsTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        refreshStats();
      });

      status.value = LanServerStatus.running;
      port.value = boundPort;
      token.value = _server!.accessControl.token;
      addresses.assignAll(_server!.addresses);
      entryUrl.value = await _server!.entryUrl(token: token.value);

      await _startForegroundService();
      Log.writeLog('局域网服务器已启动: $entryUrl');
    } catch (e) {
      status.value = LanServerStatus.error;
      errorText.value = e.toString();
      Log.writeLog('LAN: $e');
    }
  }

  Future<void> stop() async {
    _statsTimer?.cancel();
    _statsTimer = null;
    try {
      await _channel.invokeMethod('stopService');
    } catch (_) {}
    try {
      await _server?.stop();
    } catch (_) {}
    status.value = LanServerStatus.stopped;
    port.value = 0;
    activeClients.value = 0;
    wsClients.value = 0;
    danmakuRooms.value = 0;
    entryUrl.value = '';
    Log.writeLog('局域网服务器已停止');
  }

  /// 重置访问令牌（撤销全部已配对客户端）。
  Future<String> resetToken() async {
    final newToken = _server?.accessControl.resetToken() ?? '';
    token.value = newToken;
    LocalStorageService.instance.setValue(
      LocalStorageService.kLanServerToken,
      newToken,
    );
    entryUrl.value = await _server!.entryUrl(token: newToken);
    return newToken;
  }

  /// 撤销指定客户端。
  Future<void> revokeClient(String clientId) async {
    _server?.accessControl.revokeClient(clientId);
    refreshStats();
  }

  void refreshStats() {
    activeClients.value = _server?.activeClientCount ?? 0;
    wsClients.value = _server?.wsClientCount ?? 0;
    danmakuRooms.value = _server?.danmakuHub.roomCount ?? 0;
    _updateNotification();
  }

  void _onEvent(LanServerEvent event) {
    switch (event.type) {
      case 'started':
        break;
      case 'addressesChanged':
        if (_server != null) {
          addresses.assignAll(_server!.addresses);
          _updateEntryUrl();
        }
        break;
      case 'tokenReset':
        _updateEntryUrl();
        break;
      case 'stopped':
        status.value = LanServerStatus.stopped;
        break;
      case 'error':
      case 'apiError':
        Log.writeLog('LAN 事件 ${event.type}: ${event.data}');
        break;
    }
  }

  Future<void> _updateEntryUrl() async {
    if (_server == null) return;
    entryUrl.value = await _server!.entryUrl(token: token.value);
    _updateNotification();
  }

  // ---------------------------------------------------------------------------
  // 原生前台服务
  // ---------------------------------------------------------------------------

  Future<void> _startForegroundService() async {
    try {
      await _channel.invokeMethod('startService', {
        'title': 'SimpleLive 局域网服务',
        'text': '正在运行 · http://${addresses.first}:$port',
      });
    } catch (e) {
      Log.writeLog('前台服务启动失败: $e');
    }
  }

  Future<void> _updateNotification() async {
    if (!isRunning) return;
    try {
      await _channel.invokeMethod('update', {
        'text': '运行中 · 已连接设备 ${activeClients.value} 台\n访问地址：http://${addresses.isNotEmpty ? addresses.first : ""}:$port',
      });
    } catch (_) {}
  }

  /// 打开电池优化设置（帮助后台保活）。
  Future<void> requestIgnoreBatteryOptimizations() async {
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (e) {
      Log.writeLog('LAN: $e');
    }
  }

  Future<void> openAutoStartSettings() async {
    try {
      await _channel.invokeMethod('openAutoStartSettings');
    } catch (e) {
      Log.writeLog('LAN: $e');
    }
  }

  @override
  void onClose() {
    _statsTimer?.cancel();
    _eventSub?.cancel();
    _server?.stop();
    super.onClose();
  }
}

/// 从 Flutter 资源包读取 Web 静态文件。
class FlutterAssetSource implements AssetSource {
  static final Map<String, List<int>> _cache = {};

  @override
  Future<List<int>?> load(String path) async {
    if (path.isEmpty || path.contains('..')) {
      return null;
    }
    final cached = _cache[path];
    if (cached != null) {
      return cached;
    }
    try {
      final data = await rootBundle.load('assets/web/$path');
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      _cache[path] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }
}
