import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'package:simple_live_lan_server/src/util/map_utils.dart';

/// 视频代理：把 /api/stream 解析出的 CDN 地址登记为短期代理 ID，
/// 浏览器通过 /api/proxy/<id> 回源取流。
///
/// 安全约束：只能代理本服务器颁发过的地址，避免成为开放代理。
class StreamProxy {
  StreamProxy({
    this.entryTtl = const Duration(minutes: 30),
    this.maxEntries = 1024,
  }) {
    _client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..autoUncompress = false
      ..maxConnectionsPerHost = 8;
  }

  final Duration entryTtl;
  final int maxEntries;
  late final HttpClient _client;

  final LinkedHashMap<String, ProxyEntry> _entries =
      LinkedHashMap<String, ProxyEntry>();

  /// 登记一个上游地址，返回代理 ID。
  String register(String url, {Map<String, String>? headers, String uaMode = 'client'}) {
    _gc();
    final id = _newId();
    _entries[id] = ProxyEntry(
      id: id,
      url: url,
      headers: headers ?? const {},
      uaMode: uaMode,
      createdAt: DateTime.now(),
    );
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    return id;
  }

  String _newId() {
    final bytes = List<int>.generate(
      12,
      (_) => DateTime.now().microsecondsSinceEpoch.isEven
          ? _rnd.nextInt(256)
          : _rnd.nextInt(255) + 1,
    );
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static final Random _rnd = Random.secure();

  ProxyEntry? find(String id) {
    _gc();
    final entry = _entries[id];
    if (entry != null) {
      // LRU touch：活跃条目（如正在刷新的 m3u8）不被滚动淘汰，并续期
      _entries.setEntryFirst(id, entry);
      entry.createdAt = DateTime.now();
    }
    return entry;
  }

  void _gc() {
    final now = DateTime.now();
    final expired = _entries.entries
        .where((e) => now.difference(e.value.createdAt) > entryTtl)
        .map((e) => e.key)
        .toList();
    for (final id in expired) {
      _entries.remove(id);
    }
  }

  /// 处理代理请求：透传 Range，流式转发，客户端断开时取消上游。
  Future<void> handle(HttpRequest request, String id) async {
    final entry = find(id);
    if (entry == null) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        'text/plain; charset=utf-8',
      );
      await request.response.close();
      return;
    }

    final uri = Uri.tryParse(entry.url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
      return;
    }

    HttpClientRequest? upstream;
    try {
      final req = await _client.openUrl('GET', uri);
      // 平台要求的请求头（Referer 等）
      entry.headers.forEach(req.headers.set);
      // UA 策略：fixed=强制使用登记时的 UA（虎牙 HLS 按 UA 指纹拦截浏览器）；
      // client=透传客户端 UA（虎牙 FLV：浏览器 UA 才放行）。
      final clientUa = request.headers.value(HttpHeaders.userAgentHeader);
      if (entry.uaMode == 'client' && clientUa != null && clientUa.isNotEmpty) {
        req.headers.set(HttpHeaders.userAgentHeader, clientUa);
      }
      // 透传 Range
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null && range.isNotEmpty) {
        req.headers.set(HttpHeaders.rangeHeader, range);
      }
      req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      upstream = req;
      final resp = await req.close();

      final response = request.response;
      response.deadline = const Duration(minutes: 5);
      response.statusCode = resp.statusCode;
      // 透传关键响应头
      _copyHeader(resp, response, HttpHeaders.contentTypeHeader);
      _copyHeader(resp, response, HttpHeaders.contentRangeHeader);
      _copyHeader(resp, response, HttpHeaders.acceptRangesHeader);

      // 客户端断开时取消上游请求
      unawaited(
        response.done.catchError((Object e) {
          upstream?.abort();
        }).whenComplete(() {
          upstream?.abort();
        }),
      );

      final contentType = resp.headers.value(HttpHeaders.contentTypeHeader) ?? '';
      final isPlaylist =
          contentType.contains('mpegurl') || uri.path.toLowerCase().endsWith('.m3u8');
      if (isPlaylist) {
        // m3u8 重写：把分片/子播放列表地址替换为本服务代理路径，
        // 使浏览器播放器（hls.js）能全程同源取流（规避 CDN CORS）
        final body = await resp.transform(utf8.decoder).join();
        final rewritten = _rewritePlaylist(body, uri, entry.headers);
        final bytes = utf8.encode(rewritten);
        response.headers.set(
          HttpHeaders.contentTypeHeader,
          contentType.contains('mpegurl')
              ? contentType
              : 'application/vnd.apple.mpegurl',
        );
        response.headers.set(HttpHeaders.contentLengthHeader, bytes.length);
        response.bufferOutput = false;
        response.add(bytes);
        await response.close();
        return;
      }

      _copyHeader(resp, response, HttpHeaders.contentLengthHeader);
      response.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      response.bufferOutput = false;

      await response.addStream(resp);
      await response.close();
    } on SocketException {
      await _safeError(request, HttpStatus.badGateway, '上游连接失败');
    } on HttpException {
      await _safeError(request, HttpStatus.badGateway, '上游请求失败');
    } catch (e) {
      if (!_isClosed(request)) {
        await _safeError(request, HttpStatus.badGateway, '代理流错误: $e');
      }
    }
  }

  /// 重写 HLS 播放列表：每个分片/子列表/密钥地址注册为代理并替换为同源路径。
  String _rewritePlaylist(
    String body,
    Uri baseUri,
    Map<String, String> headers,
  ) {
    final base = baseUri;
    final lines = body.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      if (trimmed.startsWith('#')) {
        // EXT-X-KEY / EXT-X-MAP 的 URI="..." 属性
        if (trimmed.contains('URI="')) {
          lines[i] = line.replaceAllMapped(RegExp('URI="([^"]+)"'), (m) {
            final abs = base.resolve(m.group(1)!).toString();
            final id = register(abs, headers: headers);
            return 'URI="/api/proxy/$id"';
          });
        }
        continue;
      }
      final abs = base.resolve(trimmed).toString();
      final id = register(abs, headers: headers);
      lines[i] = '/api/proxy/$id';
    }
    return lines.join('\n');
  }

  bool _isClosed(HttpRequest request) {
    try {
      return request.response.headers.contentType != null &&
          request.response.statusCode != HttpStatus.ok;
    } catch (_) {
      return true;
    }
  }

  Future<void> _safeError(HttpRequest request, int status, String message) async {
    try {
      if (request.response.headers.contentType != null) {
        return;
      }
      request.response.statusCode = status;
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        'text/plain; charset=utf-8',
      );
      request.response.write(message);
      await request.response.close();
    } catch (_) {
      // ignore
    }
  }

  void _copyHeader(
    HttpClientResponse from,
    HttpResponse to,
    String name,
  ) {
    final v = from.headers.value(name);
    if (v != null && v.isNotEmpty) {
      to.headers.set(name, v);
    }
  }

  Future<void> dispose() async {
    _entries.clear();
    _client.close(force: true);
  }
}

class ProxyEntry {
  final String id;
  final String url;
  final Map<String, String> headers;

  /// UA 策略：client=透传客户端 UA（FLV：浏览器 UA 可通过）；
  /// fixed=强制使用 headers 里的 UA（HLS：虎牙按 UA 指纹拦截浏览器）。
  final String uaMode;
  DateTime createdAt;
  ProxyEntry({
    required this.id,
    required this.url,
    required this.headers,
    required this.uaMode,
    required this.createdAt,
  });
}
