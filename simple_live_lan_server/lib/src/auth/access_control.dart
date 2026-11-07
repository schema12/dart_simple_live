import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:simple_live_lan_server/src/util/ip_utils.dart';

/// 局域网访问控制：
/// - 随机访问令牌（配对码）校验；
/// - Host / Origin 校验（防 DNS Rebinding）；
/// - 客户端注册与撤销；
/// - 简单的请求速率限制；
/// - 请求日志（脱敏，不记录令牌/Cookie）。
class AccessControl {
  AccessControl({
    required String token,
    this.maxClients = 64,
    this.rateLimitBurst = 120,
    this.rateLimitRefillPerSecond = 15,
  }) : _token = token {
    _refreshInterfaces();
  }

  String _token;
  final int maxClients;
  final int rateLimitBurst;
  final int rateLimitRefillPerSecond;

  static final Random _random = Random.secure();

  /// 已撤销的客户端 ID。
  final Set<String> _revokedClients = {};

  /// 已知客户端：clientId -> 信息。
  final LinkedHashMap<String, _ClientInfo> _clients =
      LinkedHashMap<String, _ClientInfo>();

  /// 速率限制桶：ip -> tokens。
  final Map<String, double> _buckets = {};
  final Map<String, int> _bucketLastRefill = {};

  /// 本机地址缓存（5 秒刷新）。
  List<String> _localHosts = ['localhost', '127.0.0.1'];
  DateTime _localHostsAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 最近请求日志（环形缓冲）。
  final Queue<Map<String, Object?>> _requestLog =
      Queue<Map<String, Object?>>();
  static const int _maxLogEntries = 200;

  String get token => _token;

  /// 重置访问令牌（撤销所有客户端的旧令牌）。
  String resetToken() {
    _token = generateToken();
    return _token;
  }

  static String generateToken() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// 撤销客户端。
  bool revokeClient(String clientId) {
    if (clientId.isEmpty) {
      return false;
    }
    _clients.remove(clientId);
    return _revokedClients.add(clientId);
  }

  List<Map<String, Object?>> listClients() {
    final now = DateTime.now();
    _clients.removeWhere((_, info) =>
        now.difference(info.lastSeen).inMinutes > 60 * 24);
    return _clients.entries
        .map((e) => {
              'id': e.key,
              'userAgent': e.value.userAgent,
              'firstSeen': e.value.firstSeen.toIso8601String(),
              'lastSeen': e.value.lastSeen.toIso8601String(),
              'requests': e.value.requests,
              'revoked': false,
            })
        .toList();
  }

  bool isRevoked(String clientId) => _revokedClients.contains(clientId);

  /// 对请求执行全部校验。返回 null 表示通过；否则返回错误描述。
  ///
  /// [requireToken] 为 false 时仅做 Host/Origin/客户端撤销检查（如 health）。
  String? validate(HttpRequest request, {bool requireToken = true}) {
    final remoteIp = request.connectionInfo?.remoteAddress.address ?? '';

    // 1. 客户端撤销检查
    final clientId = _clientIdOf(request);
    if (clientId != null && isRevoked(clientId)) {
      return '客户端已被撤销，请在手机端重新配对';
    }

    // 2. Host 校验（防 DNS Rebinding：Host 必须是本机地址或 localhost）
    final host = IpUtils.hostFromAuthority(
      request.headers.value(HttpHeaders.hostHeader) ?? '',
    );
    if (!_isLocalHost(host)) {
      return '非法访问来源（Host 校验失败）';
    }

    // 3. Origin 校验（存在时才校验；同源部署下 Origin 应为本机地址）
    final origin = request.headers.value('Origin');
    if (origin != null && origin.isNotEmpty) {
      final originUri = Uri.tryParse(origin);
      final originHost = originUri == null
          ? ''
          : IpUtils.hostFromAuthority(originUri.authority);
      if (originHost.isEmpty || !_isLocalHost(originHost)) {
        return '非法访问来源（Origin 校验失败）';
      }
    }

    // 4. 令牌校验
    if (requireToken) {
      final provided = _providedToken(request);
      if (!_constantTimeEquals(provided, _token)) {
        return '访问令牌无效，请重新配对';
      }
    }

    // 5. 速率限制（仅 /api 路径）
    if (request.uri.path.startsWith('/api/')) {
      if (!_rateAllow(remoteIp)) {
        return '请求过于频繁，请稍后再试';
      }
    }

    // 6. 客户端注册
    if (clientId != null) {
      _touchClient(clientId, request.headers.value('user-agent') ?? '');
    }

    _log(request, remoteIp);
    return null;
  }

  String _providedToken(HttpRequest request) {
    final fromQuery = request.uri.queryParameters['token'];
    if (fromQuery != null && fromQuery.isNotEmpty) {
      return fromQuery;
    }
    return request.headers.value('x-lan-token') ?? '';
  }

  String? _clientIdOf(HttpRequest request) {
    final fromQuery = request.uri.queryParameters['client'];
    if (fromQuery != null && fromQuery.isNotEmpty) {
      return fromQuery;
    }
    final fromHeader = request.headers.value('x-lan-client');
    if (fromHeader != null && fromHeader.isNotEmpty) {
      return fromHeader;
    }
    return null;
  }

  void _touchClient(String clientId, String userAgent) {
    final now = DateTime.now();
    final existing = _clients[clientId];
    if (existing != null) {
      existing
        ..lastSeen = now
        ..userAgent = userAgent.isNotEmpty ? userAgent : existing.userAgent
        ..requests += 1;
    } else {
      if (_clients.length >= maxClients) {
        // 淘汰最久未活跃的客户端
        String? oldestKey;
        DateTime? oldest;
        for (final e in _clients.entries) {
          if (oldest == null || e.value.lastSeen.isBefore(oldest)) {
            oldest = e.value.lastSeen;
            oldestKey = e.key;
          }
        }
        if (oldestKey != null) {
          _clients.remove(oldestKey);
        }
      }
      _clients[clientId] = _ClientInfo(
        userAgent: userAgent,
        firstSeen: now,
        lastSeen: now,
      );
    }
  }

  bool _isLocalHost(String host) {
    if (host.isEmpty) {
      return false;
    }
    final lower = host.toLowerCase();
    if (lower == 'localhost' || lower == '127.0.0.1' || lower == '::1') {
      return true;
    }
    _refreshInterfaces();
    return _localHosts.contains(lower);
  }

  void _refreshInterfaces() {
    final now = DateTime.now();
    if (now.difference(_localHostsAt).inSeconds < 5) {
      return;
    }
    _localHostsAt = now;
    final hosts = <String>{'localhost', '127.0.0.1'};
    try {
      NetworkInterface.list(
        includeLoopback: true,
        type: InternetAddressType.any,
      ).then((list) {
        for (final itf in list) {
          for (final addr in itf.addresses) {
            hosts.add(addr.address.toLowerCase());
          }
        }
        _localHosts = hosts.toList();
      }).catchError((Object e) {
        // 保持旧缓存
      });
      // 同步先取 IPv4 列表，保证首次调用即有结果
      NetworkInterface.list(
        includeLoopback: true,
        type: InternetAddressType.IPv4,
      ).then((list) {
        for (final itf in list) {
          for (final addr in itf.addresses) {
            hosts.add(addr.address.toLowerCase());
          }
        }
        _localHosts = hosts.toList();
      }).catchError((Object e) {
        // ignore
      });
    } catch (_) {
      // ignore
    }
  }

  bool _rateAllow(String ip) {
    if (ip.isEmpty) {
      return true;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _bucketLastRefill[ip] ?? now;
    final elapsed = (now - last) / 1000.0;
    final current =
        ((_buckets[ip] ?? rateLimitBurst.toDouble()) + elapsed * rateLimitRefillPerSecond)
            .clamp(0.0, rateLimitBurst.toDouble());
    _bucketLastRefill[ip] = now;
    if (current < 1.0) {
      _buckets[ip] = current;
      return false;
    }
    _buckets[ip] = current - 1.0;
    if (_buckets.length > 512) {
      _buckets.remove(_buckets.keys.first);
      _bucketLastRefill.remove(_buckets.keys.first);
    }
    return true;
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.isEmpty || b.isEmpty) {
      return false;
    }
    final aBytes = utf8.encode(a);
    final bBytes = utf8.encode(b);
    var diff = aBytes.length ^ bBytes.length;
    final n = aBytes.length < bBytes.length ? aBytes.length : bBytes.length;
    for (var i = 0; i < n; i++) {
      diff |= aBytes[i] ^ bBytes[i];
    }
    return diff == 0;
  }

  /// 记录请求日志（不记录 query 中的 token 与任何 Cookie）。
  void _log(HttpRequest request, String remoteIp) {
    final entry = <String, Object?>{
      'time': DateTime.now().toIso8601String(),
      'method': request.method,
      'path': request.uri.path,
      'query': _redactedQuery(request.uri.queryParameters),
      'remote': remoteIp,
      'client': _clientIdOf(request) ?? '-',
    };
    _requestLog.addLast(entry);
    while (_requestLog.length > _maxLogEntries) {
      _requestLog.removeFirst();
    }
  }

  /// 请求完成后补充状态码与耗时。
  void completeLog(HttpRequest request, int status, int elapsedMs) {
    if (_requestLog.isEmpty) {
      return;
    }
    final last = _requestLog.last;
    if (last['path'] == request.uri.path) {
      last['status'] = status;
      last['elapsedMs'] = elapsedMs;
    }
  }

  Map<String, String> _redactedQuery(Map<String, String> query) {
    final result = <String, String>{};
    query.forEach((k, v) {
      final lower = k.toLowerCase();
      if (lower == 'token' || lower.contains('cookie') || lower.contains('key')) {
        result[k] = '***';
      } else {
        result[k] = v;
      }
    });
    return result;
  }

  List<Map<String, Object?>> recentLogs() => _requestLog.toList();
}

class _ClientInfo {
  String userAgent;
  final DateTime firstSeen;
  DateTime lastSeen;
  int requests = 1;
  _ClientInfo({
    required this.userAgent,
    required this.firstSeen,
    required this.lastSeen,
  });
}
