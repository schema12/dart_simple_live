import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 统一的 JSON 响应结构与错误处理工具。
class HttpHelpers {
  HttpHelpers._();

  /// 成功响应：{"code":0,"message":"ok","data":...}
  static Future<void> ok(
    HttpRequest request,
    Object? data, {
    int status = HttpStatus.ok,
  }) async {
    await _sendJson(request, status, {
      'code': 0,
      'message': 'ok',
      'data': data,
    });
  }

  /// 错误响应：{"code":<status>,"message":...}
  static Future<void> error(
    HttpRequest request,
    int status,
    String message,
  ) async {
    await _sendJson(request, status, {
      'code': status,
      'message': message,
    });
  }

  static Future<void> _sendJson(
    HttpRequest request,
    int status,
    Map<String, Object?> body,
  ) async {
    if (request.response.statusCode != HttpStatus.ok &&
        !request.response.bufferOutput) {
      // 已被提前响应
      return;
    }
    try {
      request.response.statusCode = status;
      request.response.headers
        ..set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8')
        ..set('X-Content-Type-Options', 'nosniff');
      request.response.add(utf8.encode(json.encode(body)));
      await request.response.close();
    } catch (_) {
      // 客户端已断开等情况，忽略
    }
  }

  /// 带超时执行 handler，超时返回 504，异常统一转换为 JSON 错误。
  static Future<void> guard(
    HttpRequest request,
    Future<void> Function() handler, {
    Duration timeout = const Duration(seconds: 25),
    void Function(Object error, StackTrace stack)? onError,
  }) async {
    try {
      await handler().timeout(timeout);
    } on TimeoutException {
      await error(request, HttpStatus.gatewayTimeout, '请求上游超时，请稍后重试');
    } catch (e, s) {
      if (request.response.headers.contentType == null &&
          !request.response.bufferOutput) {
        // ignore
      }
      if (e is ApiError) {
        await error(request, e.status, e.message);
        return;
      }
      onError?.call(e, s);
      if (!_responseClosed(request)) {
        await error(request, HttpStatus.internalServerError, '服务器内部错误');
      }
    }
  }

  static bool _responseClosed(HttpRequest request) {
    try {
      return request.response.headers.contentType != null &&
          request.response.statusCode != HttpStatus.ok;
    } catch (_) {
      return true;
    }
  }

  /// 必需查询参数。
  static String requireParam(HttpRequest request, String name) {
    final v = request.uri.queryParameters[name];
    if (v == null || v.trim().isEmpty) {
      throw ApiError(
        HttpStatus.badRequest,
        '缺少参数 $name',
      );
    }
    return v.trim();
  }

  /// 可选查询参数。
  static String? optionalParam(HttpRequest request, String name) {
    final v = request.uri.queryParameters[name];
    if (v == null || v.trim().isEmpty) {
      return null;
    }
    return v.trim();
  }

  static int intParam(HttpRequest request, String name, int def) {
    final v = optionalParam(request, name);
    return int.tryParse(v ?? '') ?? def;
  }
}

/// 带语义 HTTP 状态的 API 错误，guard 会将其转换为 JSON 响应。
class ApiError implements Exception {
  final int status;
  final String message;
  ApiError(this.status, this.message);

  @override
  String toString() => 'ApiError($status): $message';
}
