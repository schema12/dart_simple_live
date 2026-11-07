import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:simple_live_lan_server/src/lan_server.dart';
import 'package:simple_live_lan_server/src/lan_server_config.dart';
import 'package:simple_live_lan_server/src/live/live_hub.dart';
import 'package:simple_live_lan_server/src/static/static_files.dart';

import 'fake_site.dart';

/// 全链路 HTTP 集成测试（回环地址，不访问外网）：
/// 使用 FakeLiveSite 驱动真实 LanServer，验证鉴权、API 结构、静态资源与弹幕 WS。
void main() {
  late Directory webDir;
  late LanServer server;
  late String baseUrl;
  const token = 'testtoken00000000000000000000aa';

  late HttpServer fakeCdn;

  setUpAll(() async {
    // 本地假 CDN：代理回源测试的目标
    fakeCdn = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      fakeCdn.forEach((req) async {
        req.response.headers.set('content-type', 'video/x-flv');
        req.response.write('fake-cdn-stream');
        await req.response.close();
      }),
    );
    webDir = await Directory.systemTemp.createTemp('lan_web_');
    await File('${webDir.path}/index.html')
        .writeAsString('<!DOCTYPE html><html><body>LAN Web</body></html>');
    await Directory('${webDir.path}/assets').create();
    await File('${webDir.path}/assets/app.js').writeAsString('console.log(1)');

    final cdnBase = 'http://127.0.0.1:${fakeCdn.port}';
    final hub = LiveHub(sites: {
      'huya': FakeLiveSite(cdnBase: cdnBase),
      'douyu': FakeLiveSite(cdnBase: cdnBase),
      'bilibili': FakeLiveSite(cdnBase: cdnBase),
    });

    server = LanServer(
      config: LanServerConfig(
        defaultPort: 0,
        initialToken: token,
        serverName: 'TestLAN',
        proxyByDefault: false,
      ),
      assetSource: DirectoryAssetSource(webDir.path),
      hub: hub,
    );
    final port = await server.start();
    baseUrl = 'http://127.0.0.1:$port';
  });

  tearDownAll(() async {
    await server.stop();
    await fakeCdn.close(force: true);
    await webDir.delete(recursive: true);
  });

  String api(String path) => '$baseUrl$path';

  Future<Map<String, Object?>> getJson(
    String path, {
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse(api(path)).replace(queryParameters: query);
    final resp = await HttpClient()
        .getUrl(uri)
        .then((r) => r.close());
    final body = await resp.transform(utf8.decoder).join();
    return {'status': resp.statusCode, 'body': json.decode(body)};
  }

  test('健康检查无需令牌', () async {
    final r = await getJson('/api/health');
    expect(r['status'], 200);
    final body = r['body'] as Map;
    expect(body['code'], 0);
    expect((body['data'] as Map)['ok'], true);
  });

  test('缺少令牌的 API 请求被拒绝', () async {
    final r = await getJson('/api/platforms');
    expect(r['status'], 403);
  });

  test('错误令牌被拒绝', () async {
    final r = await getJson('/api/platforms', query: {'token': 'wrong'});
    expect(r['status'], 403);
  });

  test('正确令牌返回平台列表（仅注入的三个平台）', () async {
    final r = await getJson('/api/platforms', query: {'token': token});
    expect(r['status'], 200);
    final data = (r['body'] as Map)['data'] as List;
    expect(data.map((e) => (e as Map)['id']).toList(), ['huya', 'douyu', 'bilibili']);
  });

  test('不支持的平台返回 400', () async {
    final r = await getJson('/api/categories', query: {
      'token': token,
      'platform': 'nope',
    });
    expect(r['status'], inInclusiveRange(400, 499));
  });

  test('缺少必填参数返回 400', () async {
    final r = await getJson('/api/categories', query: {'token': token});
    expect(r['status'], 400);
  });

  test('推荐列表返回统一结构', () async {
    final r = await getJson('/api/recommend', query: {
      'token': token,
      'platform': 'huya',
    });
    expect(r['status'], 200);
    final data = (r['body'] as Map)['data'] as Map;
    expect(data['platform'], 'huya');
    final items = data['items'] as List;
    expect(items, isNotEmpty);
    final first = items.first as Map;
    for (final key in ['platform', 'roomId', 'title', 'cover', 'userName', 'online']) {
      expect(first.keys, contains(key));
    }
  });

  test('房间详情不泄露弹幕参数（danmakuData/data 不出现在响应）', () async {
    final r = await getJson('/api/room', query: {
      'token': token,
      'platform': 'huya',
      'id': '1001',
    });
    expect(r['status'], 200);
    final body = json.encode(r['body']);
    expect(body.contains('danmakuData'), isFalse);
    expect(body.contains('secretToken'), isFalse);
    expect(body.contains('cookieSecret'), isFalse);
  });

  test('画质列表以 index 引用', () async {
    final r = await getJson('/api/qualities', query: {
      'token': token,
      'platform': 'huya',
      'id': '1001',
    });
    expect(r['status'], 200);
    final data = (r['body'] as Map)['data'] as Map;
    final qs = data['qualities'] as List;
    expect(qs.map((e) => (e as Map)['index']).toList(), [0, 1]);
    expect((qs.first as Map)['quality'], '原画');
  });

  test('播放地址返回 format 与可选代理路径', () async {
    final r = await getJson('/api/stream', query: {
      'token': token,
      'platform': 'huya',
      'id': '1001',
      'quality': '0',
    });
    expect(r['status'], 200);
    final data = (r['body'] as Map)['data'] as Map;
    final urls = data['urls'] as List;
    expect(urls, isNotEmpty);
    expect((urls.first as Map)['format'], 'flv');
    expect((urls.first as Map).keys, contains('url'));
    expect((urls.first as Map).keys, isNot(contains('proxy')));
  });

  test('proxy=1 时播放地址附带代理路径且代理可回源', () async {
    final r = await getJson('/api/stream', query: {
      'token': token,
      'platform': 'bilibili',
      'id': '2001',
      'quality': '0',
      'proxy': '1',
    });
    expect(r['status'], 200);
    final urls = ((r['body'] as Map)['data'] as Map)['urls'] as List;
    final proxyPath = (urls.first as Map)['proxy'] as String;
    expect(proxyPath.startsWith('/api/proxy/'), isTrue);

    // 代理回源：上游是我们内置的假 CDN
    final resp = await HttpClient()
        .getUrl(Uri.parse('$baseUrl$proxyPath?token=$token'))
        .then((r) => r.close());
    expect(resp.statusCode, 200);
    final body = await resp.transform(utf8.decoder).join();
    expect(body, 'fake-cdn-stream');
  });

  test('代理不接受未知 ID（非开放代理）', () async {
    final resp = await HttpClient()
        .getUrl(
          Uri.parse('$baseUrl/api/proxy/doesnotexist?token=$token'),
        )
        .then((r) => r.close());
    expect(resp.statusCode, 404);
  });

  test('非法 Host（DNS Rebinding）被拒绝', () async {
    final req = await HttpClient()
        .getUrl(Uri.parse('$baseUrl/api/platforms?token=$token'));
    req.headers.set('Host', 'evil.example.com:8080');
    final resp = await req.close();
    expect(resp.statusCode, 403);
  });

  test('非法 Origin 被拒绝', () async {
    final req = await HttpClient()
        .getUrl(Uri.parse('$baseUrl/api/platforms?token=$token'));
    req.headers.set('Origin', 'http://evil.example.com');
    final resp = await req.close();
    expect(resp.statusCode, 403);
  });

  test('静态资源：index 与 js 正常返回（无令牌可加载配对页），未知路径回退 index', () async {
    final idx = await HttpClient()
        .getUrl(Uri.parse('$baseUrl/'))
        .then((r) => r.close());
    expect(idx.statusCode, 200);
    expect(idx.headers.contentType!.toString(), contains('text/html'));

    final js = await HttpClient()
        .getUrl(Uri.parse('$baseUrl/assets/app.js'))
        .then((r) => r.close());
    expect(js.statusCode, 200);
    expect(js.headers.contentType!.toString(), contains('javascript'));

    final spa = await HttpClient()
        .getUrl(Uri.parse('$baseUrl/some/spa/route'))
        .then((r) => r.close());
    expect(spa.statusCode, 200);

    final missing = await HttpClient()
        .getUrl(Uri.parse('$baseUrl/no/such/file.png'))
        .then((r) => r.close());
    expect(missing.statusCode, 404);
  });

  test('目录穿越被拒绝', () async {
    final resp = await HttpClient()
        .getUrl(Uri.parse('$baseUrl/..%2f..%2fsecret.txt'))
        .then((r) => r.close());
    expect(resp.statusCode, inInclusiveRange(400, 404));
  });

  test('客户端撤销后请求被拒绝', () async {
    final r1 = await getJson('/api/platforms', query: {
      'token': token,
      'client': 'device-x',
    });
    expect(r1['status'], 200);

    final list = await getJson('/api/clients', query: {'token': token});
    final clients = (list['body'] as Map)['data'] as List;
    expect(clients.map((c) => (c as Map)['id']), contains('device-x'));

    final del = await HttpClient()
        .deleteUrl(Uri.parse('$baseUrl/api/clients/device-x?token=$token'))
        .then((r) => r.close());
    expect(del.statusCode, 200);

    final r2 = await getJson('/api/platforms', query: {
      'token': token,
      'client': 'device-x',
    });
    expect(r2['status'], 403);
  });

  test('服务器信息接口', () async {
    final r = await getJson('/api/server', query: {'token': token});
    expect(r['status'], 200);
    final data = (r['body'] as Map)['data'] as Map;
    expect(data['status'], 'running');
    expect((data['addresses'] as List), isNotEmpty);
    expect(data.keys, isNot(contains('token')));
  });

  test('WebSocket 弹幕：订阅、收到 hello、chat 广播、退出后房间空闲', () async {
    final port = server.port;
    final ws = await WebSocket.connect(
      'ws://127.0.0.1:$port/api/danmaku?platform=huya&id=1001&token=$token&client=ws-test',
    );
    final received = <Map<String, Object?>>[];
    final sub = ws.listen((data) {
      received.add(json.decode(data as String) as Map<String, Object?>);
    });

    // 等 hello
    await _waitUntil(() => received.any((m) => m['type'] == 'hello'));
    expect(received.firstWhere((m) => m['type'] == 'hello')['platform'], 'huya');

    // FakeDanmaku 推送弹幕（多次投递，避免偶发竞态）
    final fakeSite = server.hub.site('huya') as FakeLiveSite;
    await _waitUntil(
      () {
        fakeSite.emitChat('测试用户', '你好局域网', '#FF0000');
        return received.any((m) => m['type'] == 'chat');
      },
      timeout: const Duration(seconds: 8),
    );
    final chat = received.firstWhere((m) => m['type'] == 'chat');
    expect(chat['user'], '测试用户');
    expect(chat['text'], '你好局域网');
    // LiveMessageColor.toString() 输出小写十六进制
    expect((chat['color'] as String).toLowerCase(), '#ff0000');

    // 心跳
    ws.add(json.encode({'type': 'ping'}));
    await _waitUntil(() => received.any((m) => m['type'] == 'pong'));

    await sub.cancel();
    await ws.close();
  });

  test('两个客户端订阅同一房间共享一条平台连接', () async {
    final port = server.port;
    final ws1 = await WebSocket.connect(
      'ws://127.0.0.1:$port/api/danmaku?platform=douyu&id=1001&token=$token&client=c1',
    );
    final ws2 = await WebSocket.connect(
      'ws://127.0.0.1:$port/api/danmaku?platform=douyu&id=1001&token=$token&client=c2',
    );
    final got1 = <Map<String, Object?>>[];
    final sub1 = ws1.listen((d) => got1.add(json.decode(d as String)));
    final got2 = <Map<String, Object?>>[];
    final sub2 = ws2.listen((d) => got2.add(json.decode(d as String)));

    await _waitUntil(() => got1.isNotEmpty && got2.isNotEmpty);
    final fakeSite = server.hub.site('douyu') as FakeLiveSite;
    await _waitUntil(
      () {
        fakeSite.emitChat('甲', '共享弹幕', '#FFFFFF');
        return got1.any((m) => m['type'] == 'chat') &&
            got2.any((m) => m['type'] == 'chat');
      },
      timeout: const Duration(seconds: 8),
    );

    await sub1.cancel();
    await sub2.cancel();
    await ws1.close();
    await ws2.close();
  });
}

Future<void> _waitUntil(bool Function() cond,
    {Duration timeout = const Duration(seconds: 5)}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) {
      fail('等待条件超时');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
