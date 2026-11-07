import 'dart:io';

import 'package:simple_live_core/simple_live_core.dart';
import 'package:test/test.dart';

void testSite(LiveSite site) async {
  var rooms = <LiveRoomItem>[];
  test('getRecommendRooms', () async {
    final result = await site.getRecommendRooms();
    expect(result, isNotNull);
    expect(result.items, isNotEmpty);
    rooms = result.items;
    for (var item in rooms) {
      expect(item.roomId, isNotEmpty);
      expect(item.title, isNotEmpty);
      expect(item.cover, isNotEmpty);
      expect(item.userName, isNotEmpty);
      print(item);
    }
  });

  var categores = <LiveCategory>[];
  test('getCategores', () async {
    categores = await site.getCategores();
    expect(categores, isNotEmpty);
    for (var item in categores) {
      expect(item.name, isNotEmpty);
      for (var subItem in item.children) {
        expect(subItem.name, isNotEmpty);
        expect(subItem.id, isNotEmpty);
        expect(subItem.parentId, isNotEmpty);
      }
      print('${item.name}\n${item.children}');
    }
  });

  test('getCategoryRooms', () async {
    var result = await site.getCategoryRooms(categores.first.children.first);
    expect(result, isNotNull);
    expect(result.items, isNotEmpty);
    for (var item in result.items) {
      expect(item.roomId, isNotEmpty);
      expect(item.title, isNotEmpty);
      expect(item.cover, isNotEmpty);
      expect(item.userName, isNotEmpty);
      print(item);
    }
  });

  test('searchRooms', () async {
    var result = await site.searchRooms('LOL');
    expect(result, isNotNull);
    expect(result.items, isNotEmpty);
    for (var item in result.items) {
      expect(item.roomId, isNotEmpty);
      expect(item.title, isNotEmpty);
      expect(item.cover, isNotEmpty);
      expect(item.userName, isNotEmpty);
      print(item);
    }
  });

  test('searchAnchors', () async {
    // 跳过抖音测试此项
    if (site is DouyinSite) {
      return;
    }
    var result = await site.searchAnchors('联盟');
    expect(result, isNotNull);
    expect(result.items, isNotEmpty);
    for (var item in result.items) {
      expect(item.roomId, isNotEmpty);
      expect(item.userName, isNotEmpty);
      print(item);
    }
  });

  LiveRoomDetail? roomDetail;
  test('getRoomDetail', () async {
    roomDetail = await site.getRoomDetail(roomId: rooms.first.roomId);
    expect(roomDetail, isNotNull);
    expect(roomDetail?.roomId, isNotEmpty);
    expect(roomDetail?.danmakuData, isNotNull);
    print(roomDetail);
  });

  List<LivePlayQuality> playQualities = [];
  test('getPlayQuality', () async {
    playQualities = await site.getPlayQualites(detail: roomDetail!);
    expect(playQualities, isNotEmpty);
    for (var item in playQualities) {
      expect(item.quality, isNotEmpty);
      expect(item.data, isNotNull);
      print(item);
    }
  });

  test('getPlayUrls', () async {
    var url = await site.getPlayUrls(
        detail: roomDetail!, quality: playQualities.first);
    expect(url, isNotNull);
    expect(url.urls, isNotEmpty);
    print(url.urls.join('\n\n'));
  });

  test('getDanmaku', () async {
    var danmaku = site.getDanmaku();
    expect(danmaku, isNotNull);
    expect(danmaku, isA<LiveDanmaku>());
    var closed = false;
    var ready = false;
    danmaku.onReady = () {
      print('ready');
      ready = true;
    };
    danmaku.onClose = (msg) {
      print('onClose $msg');
      closed = true;
    };
    var msgCount = 0;
    danmaku.onMessage = (LiveMessage msg) {
      print('onMessage ${msg.type} ${msg.message}');
      msgCount++;
    };
    await danmaku.start(roomDetail!.danmakuData);
    // 接收30秒的弹幕
    await Future.delayed(const Duration(seconds: 30));
    expect(ready, isTrue);
    expect(closed, isFalse);
    expect(msgCount, greaterThan(0));
    await danmaku.stop();
  }, timeout: const Timeout(Duration(seconds: 40)), retry: 2);
}

void main() {
  CoreLog.requestLogType = RequestLogType.short;

  group('bilibili tests', () {
    testSite(BiliBiliSite());
  });

  group('douyu tests', () {
    testSite(DouyuSite());
  });

  group('huya tests', () {
    testSite(HuyaSite());
  });

  // 抖音对数据中心 IP 有风控（GitHub Actions runner 上返回 404），
  // CI 中通过 LAN_SKIP_DOUYIN=1 跳过；本地/真机环境仍然执行。
  if (Platform.environment['LAN_SKIP_DOUYIN'] == '1') {
    test('douyin tests skipped (LAN_SKIP_DOUYIN=1)', () {
      markTestSkipped('数据中心 IP 被抖音风控拦截，CI 环境跳过');
    });
  } else {
    group('douyin tests', () {
      testSite(DouyinSite());
    });
  }
}
