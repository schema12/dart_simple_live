import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'dart:io';

import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_lan_server/src/live/live_hub.dart';
import 'package:simple_live_lan_server/src/util/map_utils.dart';

/// 统一弹幕 WebSocket 会话（一个 Web 客户端在一个房间内的连接）。
class DanmakuSession {
  DanmakuSession(this.socket, this.clientId, this.platform, this.roomId);

  final WebSocket socket;
  final String clientId;
  final String platform;
  final String roomId;
  bool closed = false;

  void send(Map<String, Object?> message) {
    if (closed) {
      return;
    }
    try {
      socket.add(utf8.encode(json.encode(message)));
    } catch (_) {
      closed = true;
    }
  }

  Future<void> close() async {
    if (closed) {
      return;
    }
    closed = true;
    try {
      await socket.close();
    } catch (_) {
      // ignore
    }
  }
}

/// 单个房间的平台弹幕连接与广播。
class DanmakuRoom {
  DanmakuRoom({
    required this.platform,
    required this.roomId,
    required this.site,
    required this.args,
  }) {
    danmaku = site.getDanmaku();
    danmaku.onMessage = _onMessage;
    danmaku.onClose = _onClose;
    danmaku.onReady = () {
      ready = true;
    };
  }

  final String platform;
  final String roomId;
  final LiveSite site;
  final dynamic args;
  late final LiveDanmaku danmaku;
  final Set<DanmakuSession> clients = {};
  bool ready = false;
  bool dead = false;
  int? lastOnline;
  DateTime createdAt = DateTime.now();

  Future<void> start() => danmaku.start(args);

  Future<void> dispose() async {
    dead = true;
    try {
      await danmaku.stop();
    } catch (_) {
      // ignore
    }
  }

  void broadcast(Map<String, Object?> message) {
    for (final session in clients.toList()) {
      session.send(message);
    }
  }

  void _onMessage(LiveMessage msg) {
    switch (msg.type) {
      case LiveMessageType.chat:
        broadcast({
          'type': 'chat',
          'user': msg.userName,
          'text': msg.message,
          'color': msg.color.toString(),
          if (msg.imageUrls != null) 'images': msg.imageUrls,
          if (msg.spans != null)
            'spans': msg.spans!
                .map((s) => s.isImage
                    ? {'img': s.imageUrl}
                    : {'text': s.text})
                .toList(),
          'ts': DateTime.now().millisecondsSinceEpoch,
        });
        break;
      case LiveMessageType.online:
        final online = msg.data is int ? msg.data as int : 0;
        lastOnline = online;
        broadcast({'type': 'online', 'online': online});
        break;
      case LiveMessageType.gift:
        broadcast({
          'type': 'gift',
          'user': msg.userName,
          'text': msg.message,
          'color': msg.color.toString(),
          'ts': DateTime.now().millisecondsSinceEpoch,
        });
        break;
      case LiveMessageType.superChat:
        final sc = msg.data;
        if (sc is LiveSuperChatMessage) {
          broadcast({
            'type': 'superChat',
            'id': sc.id,
            'user': sc.userName,
            'face': sc.face,
            'message': sc.message,
            'price': sc.price,
            'backgroundColor': sc.backgroundColor,
            'backgroundBottomColor': sc.backgroundBottomColor,
            'startTime': sc.startTime.toIso8601String(),
            'endTime': sc.endTime.toIso8601String(),
          });
        }
        break;
    }
  }

  void _onClose(String message) {
    // core 的 WebSocket 工具会自动重连；仅当其彻底放弃时才会触发 fatal。
    // 这里将重连过程中的断开广播给客户端，便于前端提示。
    broadcast({'type': 'reconnecting', 'message': message});
  }
}

/// 弹幕管理：按房间维护平台连接，向多个 Web 客户端广播统一 JSON 消息。
class DanmakuHub {
  DanmakuHub({
    required LiveHub hub,
    required this.idleClose,
    this.maxRooms = 12,
  }) : _hub = hub;

  final LiveHub _hub;
  final Duration idleClose;
  final int maxRooms;

  final LinkedHashMap<String, DanmakuRoom> _rooms =
      LinkedHashMap<String, DanmakuRoom>();

  int get roomCount => _rooms.length;

  int get sessionCount => _rooms.values.fold(0, (n, r) => n + r.clients.length);

  /// 订阅房间弹幕。返回房间（已开始或正在启动）。
  Future<DanmakuRoom> subscribe(DanmakuSession session) async {
    final key = _hub.keyOf(session.platform, session.roomId);
    var room = _rooms[key];
    if (room != null && room.dead) {
      _rooms.remove(key);
      room = null;
    }
    if (room == null) {
      final detail = _hub.cachedDetail(session.platform, session.roomId) ??
          await _hub.getRoomDetail(session.platform, session.roomId);
      final args = detail.danmakuData;
      room = DanmakuRoom(
        platform: session.platform,
        roomId: session.roomId,
        site: _hub.site(session.platform),
        args: args,
      );
      _rooms[key] = room;
      _evictIfNeeded();
      // 异步启动，不阻塞订阅
      unawaited(
        room.start().catchError((Object e) {
          room!.broadcast({'type': 'error', 'message': '弹幕连接失败: $e'});
          room.dead = true;
        }),
      );
    } else {
      _rooms.setEntryFirst(key, room);
    }
    room.clients.add(session);
    session.send({
      'type': 'hello',
      'platform': session.platform,
      'roomId': session.roomId,
      'clients': room.clients.length,
      if (room.lastOnline != null) 'online': room.lastOnline,
    });
    _broadcastRoomSize(room);
    return room;
  }

  /// 取消订阅；当房间无客户端时安排延迟关闭，避免频繁切换房间时抖动。
  void unsubscribe(DanmakuSession session) {
    final key = _hub.keyOf(session.platform, session.roomId);
    final room = _rooms[key];
    if (room == null) {
      return;
    }
    room.clients.remove(session);
    if (room.clients.isEmpty) {
      Future.delayed(idleClose, () async {
        final current = _rooms[key];
        if (current != null && current.clients.isEmpty) {
          _rooms.remove(key);
          await current.dispose();
        }
      });
    } else {
      _broadcastRoomSize(room);
    }
  }

  void _broadcastRoomSize(DanmakuRoom room) {
    room.broadcast({
      'type': 'clients',
      'clients': room.clients.length,
    });
  }

  void _evictIfNeeded() {
    while (_rooms.length > maxRooms) {
      // 淘汰最早创建且无客户端的房间；全都有客户端时淘汰最旧的。
      String? victimKey;
      for (final entry in _rooms.entries) {
        if (entry.value.clients.isEmpty) {
          victimKey = entry.key;
          break;
        }
      }
      victimKey ??= _rooms.keys.first;
      final victim = _rooms.remove(victimKey);
      unawaited(victim?.dispose());
    }
  }

  /// 服务端主动关闭某个房间（如平台连接彻底失败）。
  void markRoomDead(String platform, String roomId) {
    final key = _hub.keyOf(platform, roomId);
    final room = _rooms[key];
    if (room != null) {
      room.dead = true;
      room.broadcast({'type': 'error', 'message': '弹幕连接已断开'});
    }
  }

  Future<void> disposeAll() async {
    for (final room in _rooms.values) {
      for (final client in room.clients.toList()) {
        client.send({'type': 'bye'});
        await client.close();
      }
      await room.dispose();
    }
    _rooms.clear();
  }
}
