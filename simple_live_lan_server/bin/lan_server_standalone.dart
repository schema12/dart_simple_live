/// 独立运行的局域网服务器（开发调试 / 桌面端 E2E 测试用）。
///
/// 用法：
/// ```
/// dart run simple_live_lan_server:lan_server_standalone \
///   --web-dir ../web_dist --port 8080 [--token xxx] [--proxy]
/// ```
import 'dart:io';

import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_lan_server/simple_live_lan_server.dart';

Future<void> main(List<String> args) async {
  String? webDir;
  int port = 8080;
  String? token;
  var proxy = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--web-dir':
        webDir = args[++i];
        break;
      case '--port':
        port = int.parse(args[++i]);
        break;
      case '--token':
        token = args[++i];
        break;
      case '--proxy':
        proxy = true;
        break;
      default:
        break;
    }
  }

  if (webDir == null || webDir.isEmpty) {
    stderr.writeln('必须提供 --web-dir（Web 构建产物目录）');
    exit(2);
  }

  final tokenFile = File('${Directory.systemTemp.path}/simple_live_lan_token');
  String resolvedToken = token ?? '';
  if (resolvedToken.isEmpty) {
    if (await tokenFile.exists()) {
      resolvedToken = (await tokenFile.readAsString()).trim();
    }
    if (resolvedToken.isEmpty) {
      resolvedToken = AccessControl.generateToken();
    }
  }
  await tokenFile.writeAsString(resolvedToken);

  final server = LanServer(
    config: LanServerConfig(
      defaultPort: port,
      initialToken: resolvedToken,
      tokenSaver: (t) async {
        await tokenFile.writeAsString(t);
      },
      proxyByDefault: proxy,
      version: '1.0.0-standalone',
    ),
    assetSource: DirectoryAssetSource(webDir),
  );

  server.events.listen((event) {
    stdout.writeln('[event] ${event.type} ${event.data ?? ''}');
  });

  CoreLog.enableLog = false;

  final boundPort = await server.start();
  final entry = await server.entryUrl(token: server.accessControl.token);
  stdout.writeln('SimpleLive LAN standalone server');
  stdout.writeln('Web dir : $webDir');
  stdout.writeln('Port    : $boundPort');
  stdout.writeln('LAN IP  : ${server.addresses.join(', ')}');
  stdout.writeln('Token   : ${server.accessControl.token}');
  stdout.writeln('Entry   : $entry');
  stdout.writeln('日志文件: ${tokenFile.path}（保存访问令牌）');
  stdout.writeln('Ctrl+C 退出');

  ProcessSignal.sigint.watch().listen((_) async {
    stdout.writeln('正在停止服务...');
    await server.stop();
    exit(0);
  });
}
