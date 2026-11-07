import 'dart:async';

import 'package:simple_live_core/simple_live_core.dart';

/// 测试用假平台：完全实现 LiveSite 接口，不访问任何网络。
class FakeLiveSite implements LiveSite {
  @override
  String id = 'fake';

  @override
  String name = '假平台';

  final FakeDanmaku danmaku = FakeDanmaku();

  void emitChat(String user, String text, String color) {
    danmaku
      ..push(LiveMessage(
        type: LiveMessageType.chat,
        userName: user,
        message: text,
        color: LiveMessageColor.numberToColor(
          int.parse(color.substring(1), radix: 16),
        ),
      ));
  }

  @override
  LiveDanmaku getDanmaku() => danmaku;

  @override
  Future<List<LiveCategory>> getCategores() async {
    return [
      LiveCategory(id: '1', name: '游戏', children: [
        LiveSubCategory(id: '11', name: '王者荣耀', parentId: '1'),
      ]),
    ];
  }

  @override
  Future<LiveCategoryResult> getCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
    return LiveCategoryResult(hasMore: false, items: [
      LiveRoomItem(
        roomId: '1001',
        title: '分类房间',
        cover: 'http://cdn.test/cover.jpg',
        userName: '分类主播',
        online: 666,
      ),
    ]);
  }

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async {
    return LiveCategoryResult(hasMore: false, items: [
      LiveRoomItem(
        roomId: '1001',
        title: '推荐房间标题',
        cover: 'http://cdn.test/cover.jpg',
        userName: '推荐主播',
        online: 12345,
      ),
      LiveRoomItem(
        roomId: '1002',
        title: '第二间',
        cover: 'http://cdn.test/cover2.jpg',
        userName: '主播乙',
        online: 234,
      ),
    ]);
  }

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    return LiveRoomDetail(
      roomId: roomId,
      title: '测试房间 $roomId',
      cover: 'http://cdn.test/$roomId.jpg',
      userName: '测试主播',
      userAvatar: 'http://cdn.test/avatar.jpg',
      online: 888,
      status: true,
      introduction: '介绍',
      notice: '公告',
      url: 'http://test/$roomId',
      data: 'internal-play-data',
      danmakuData: FakeDanmakuArgs(roomId: roomId),
    );
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites({
    required LiveRoomDetail detail,
  }) async {
    return [
      LivePlayQuality(quality: '原画', data: '0'),
      LivePlayQuality(quality: '高清', data: '2000'),
    ];
  }

  @override
  Future<LivePlayUrl> getPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    final ext = detail.data == 'hls-test' ? 'm3u8' : 'flv';
    return LivePlayUrl(
      urls: ['http://cdn.test:1935/live/${detail.roomId}.$ext'],
      headers: {'user-agent': 'FakeUA/1.0'},
    );
  }

  @override
  Future<LiveSearchRoomResult> searchRooms(
    String keyword, {
    int page = 1,
  }) async {
    return LiveSearchRoomResult(hasMore: false, items: [
      LiveRoomItem(
        roomId: '1001',
        title: '搜索结果 $keyword',
        cover: 'http://cdn.test/search.jpg',
        userName: '搜索主播',
        online: 42,
      ),
    ]);
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(
    String keyword, {
    int page = 1,
  }) async {
    return LiveSearchAnchorResult(hasMore: false, items: [
      LiveAnchorItem(
        roomId: '1001',
        avatar: 'http://cdn.test/avatar.jpg',
        userName: '搜索主播 $keyword',
        liveStatus: true,
      ),
    ]);
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async => true;

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage({
    required String roomId,
    LiveRoomDetail? detail,
  }) async =>
      [];

  @override
  Future<List<LiveContributionRankItem>> getContributionRank({
    required String roomId,
    LiveRoomDetail? detail,
  }) async =>
      [];
}

class FakeDanmakuArgs {
  final String roomId;
  FakeDanmakuArgs({required this.roomId});
  @override
  String toString() => 'FakeDanmakuArgs($roomId)';
}

/// 可控的假弹幕：start 后 ready，push() 驱动 onMessage。
class FakeDanmaku extends LiveDanmaku {
  @override
  int heartbeatTime = 1000;

  @override
  Future<dynamic> start(dynamic args) async {
    onReady?.call();
  }

  @override
  Future<dynamic> stop() async {}

  void push(LiveMessage message) {
    onMessage?.call(message);
  }
}
