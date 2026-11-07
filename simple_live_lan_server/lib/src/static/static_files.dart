import 'dart:async';
import 'dart:io';

/// Web 静态资源来源抽象。
///
/// Flutter 宿主用 rootBundle 读取 APK 内资源；CLI 宿主读取本地目录。
abstract class AssetSource {
  /// 返回资源字节；不存在时返回 null。
  Future<List<int>?> load(String path);
}

/// 文件目录实现（开发 / E2E 测试用）。
class DirectoryAssetSource implements AssetSource {
  DirectoryAssetSource(this.root);

  final String root;

  @override
  Future<List<int>?> load(String path) async {
    final normalized = _normalize(path);
    if (normalized == null) {
      return null;
    }
    final file = File('$root/$normalized');
    if (!await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  String? _normalize(String path) {
    var p = path;
    if (p.startsWith('/')) {
      p = p.substring(1);
    }
    if (p.isEmpty || p.endsWith('/')) {
      p += 'index.html';
    }
    if (p.contains('..') || p.contains('\\')) {
      return null;
    }
    return p;
  }
}

/// Web 静态资源处理器。
class StaticFiles {
  StaticFiles(this.source);

  final AssetSource source;

  static const Map<String, String> _contentTypes = {
    'html': 'text/html; charset=utf-8',
    'js': 'text/javascript; charset=utf-8',
    'mjs': 'text/javascript; charset=utf-8',
    'css': 'text/css; charset=utf-8',
    'json': 'application/json; charset=utf-8',
    'svg': 'image/svg+xml',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'ico': 'image/x-icon',
    'woff': 'font/woff',
    'woff2': 'font/woff2',
    'ttf': 'font/ttf',
    'map': 'application/json; charset=utf-8',
    'txt': 'text/plain; charset=utf-8',
  };

  /// 处理静态资源请求。返回 true 表示已响应。
  Future<bool> handle(HttpRequest request) async {
    var path = request.uri.path;
    if (path == '/') {
      path = '/index.html';
    }
    // 防目录穿越
    if (path.contains('..') || path.contains('//')) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return true;
    }
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;

    var data = await source.load(cleanPath);
    var servedPath = cleanPath;
    // SPA：未知"页面路径"回退 index.html（配合前端 hash 路由，仅在无扩展名时回退）
    if (data == null && !cleanPath.contains('.')) {
      data = await source.load('index.html');
      servedPath = 'index.html';
    }
    if (data == null) {
      return false;
    }

    final ext = servedPath.contains('.')
        ? servedPath.split('.').last.toLowerCase()
        : 'html';
    final contentType = _contentTypes[ext] ?? 'application/octet-stream';
    final response = request.response;
    response.headers
      ..set(HttpHeaders.contentTypeHeader, contentType)
      ..set('X-Content-Type-Options', 'nosniff')
      // 带 hash 的资源（assets/ 下）可缓存，入口 html 不缓存
      ..set(
        HttpHeaders.cacheControlHeader,
        ext == 'html'
            ? 'no-cache'
            : 'public, max-age=86400',
      );
    response.statusCode = HttpStatus.ok;
    response.add(data);
    await response.close();
    return true;
  }
}
