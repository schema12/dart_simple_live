/// 真实平台 API 集成测试（需要外网，通过环境变量 LAN_INTEGRATION=1 开启）。
///
/// 覆盖：虎牙 / 斗鱼 / B站的分类、推荐、搜索、房间详情、画质、播放地址与弹幕连接。
/// CI 中以 `LAN_INTEGRATION=1 dart test --tags integration` 运行。
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import 'package:simple_live_core/simple_live_core.dart';

void main() {
  CoreLog.enableLog = false;
  if (Platform.environment['LAN_INTEGRATION'] != '1') {
    test('集成测试已跳过（未设置 LAN_INTEGRATION=1）', () {
      markTestSkipped('需要真实网络，设置 LAN_INTEGRATION=1 后运行');
    });
    return;
  }

  final cases = <String, (String, String)>{
    'huya': ('huya', '660124'), // 虎牙示例房间号（实际以推荐接口结果兜底）
    'douyu': ('douyu', '606118'),
    'bilibili': ('bilibili', '213'),
  };

  for (final entry in cases.entries) {
    final platform = entry.value.$1;
    final hintRoom = entry.value.$2;

    group('平台 $platform', () {
      late LiveSite site;

      setUp(() {
        switch (platform) {
          case 'huya':
            site = HuyaSite();
            break;
          case 'douyu':
            site = DouyuSite();
            break;
          case 'bilibili':
            site = BiliBiliSite();
            break;
        }
      });

      test('分类列表非空', () async {
        final categories = await site.getCategores();
        expect(categories, isNotEmpty);
        expect(categories.first.children, isNotEmpty);
      });

      test('推荐直播非空', () async {
        final result = await site.getRecommendRooms(page: 1);
        expect(result.items, isNotEmpty);
        expect(result.items.first.roomId, isNotEmpty);
      });

      test('搜索房间非空', () async {
        final result = await site.searchRooms('英雄联盟', page: 1);
        expect(result.items, isNotEmpty);
      });

      test('房间详情→画质→播放地址全链路', () async {
        final recommend = await site.getRecommendRooms(page: 1);
        final roomId = recommend.items.first.roomId;
        final detail = await site.getRoomDetail(roomId: roomId);
        expect(detail.roomId, isNotEmpty);
        expect(detail.title, isNotEmpty);

        if (!detail.status) {
          // 直播间未开播时跳过画质/地址
          return;
        }
        final qualities = await site.getPlayQualites(detail: detail);
        expect(qualities, isNotEmpty);
        final urls = await site.getPlayUrls(
          detail: detail,
          quality: qualities.first,
        );
        expect(urls.urls, isNotEmpty);
        for (final url in urls.urls) {
          expect(url.startsWith('http'), isTrue, reason: '非法播放地址: $url');
        }
      });

      test('弹幕连接能收到消息', () async {
        // 数据中心 IP 对部分平台弹幕有风控（CI 环境可按平台跳过）
        final skipList =
            Platform.environment['LAN_SKIP_DANMAKU_FOR']?.split(',') ?? const [];
        if (skipList.contains(platform)) {
          markTestSkipped('CI 环境跳过 $platform 弹幕连接（数据中心 IP 限制）');
          return;
        }
        // 依次尝试推荐列表前 3 个房间，避免单个房间偶发无弹幕
        final recommend = await site.getRecommendRooms(page: 1);
        final roomIds = [
          hintRoom,
          ...recommend.items.map((r) => r.roomId),
        ].take(3).toSet().toList();
        var gotAny = false;
        for (final roomId in roomIds) {
          final detail = await site.getRoomDetail(roomId: roomId);
          final danmaku = site.getDanmaku();
          final gotMessage = Completer<bool>();
          danmaku.onMessage = (msg) {
            if (!gotMessage.isCompleted) {
              gotMessage.complete(true);
            }
          };
          danmaku.onClose = (e) {
            if (!gotMessage.isCompleted) {
              gotMessage.complete(false);
            }
          };
          await danmaku.start(detail.danmakuData);
          final result = await gotMessage.future.timeout(
            const Duration(seconds: 15),
            onTimeout: () => false,
          );
          await danmaku.stop();
          if (result) {
            gotAny = true;
            break;
          }
        }
        expect(gotAny, isTrue, reason: '多个房间均未收到弹幕/人气消息');
      }, timeout: const Timeout(Duration(minutes: 3)));
    });
  }
}
