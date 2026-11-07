import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

/// 视频代理：把 /api/stream 解析出的 CDN 地址登记为短期代理 ID，
/// 浏览器通过 /api/proxy/<id> 回源取流。
///
/// 安全约束：只能代理本服务器颁发过的地址，避免成为开放代理。
class StreamProxy {
  StreamProxy({
    this.entryTtl = const Duration(minutes: 30),
    this.maxEntries = 256,
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
  String register(String url, {Map<String, String>? headers}) {
    _gc();
    final id = _newId();
    _entries[id] = ProxyEntry(
      id: id,
      url: url,
      headers: headers ?? const {},
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
    return _entries[id];
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
      // 平台要求的请求头（UA/Referer 等）
      entry.headers.forEach(req.headers.set);
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
      _copyHeader(resp, response, HttpHeaders.contentLengthHeader);
      _copyHeader(resp, response, HttpHeaders.contentRangeHeader);
      _copyHeader(resp, response, HttpHeaders.acceptRangesHeader);
      response.headers.set(
        HttpHeaders.acceptEncodingHeader,
        'identity',
      );
      response.bufferOutput = false;

      // 客户端断开时取消上游请求
      unawaited(
        response.done.catchError((Object e) {
          upstream?.abort();
        }).whenComplete(() {
          upstream?.abort();
        }),
      );

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
  final DateTime createdAt;
  ProxyEntry({
    required this.id,
    required this.url,
    required this.headers,
    required this.createdAt,
  });
}
