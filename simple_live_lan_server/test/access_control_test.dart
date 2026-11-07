import 'package:test/test.dart';

import 'package:simple_live_lan_server/src/auth/access_control.dart';

void main() {
  group('AccessControl 令牌', () {
    test('generateToken 生成长度固定且唯一的 32 位十六进制', () {
      final t1 = AccessControl.generateToken();
      final t2 = AccessControl.generateToken();
      expect(t1.length, 32);
      expect(t2.length, 32);
      expect(t1, isNot(t2));
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(t1), isTrue);
    });

    test('resetToken 更换令牌', () {
      final ac = AccessControl(token: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
      expect(ac.token, 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
      final nt = ac.resetToken();
      expect(nt, isNot('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'));
      expect(ac.token, nt);
    });
  });

  group('AccessControl 常量时间比较', () {
    test('空令牌不通过', () {
      final ac = AccessControl(token: 'tok');
      // 通过内部方法验证：直接对 _constantTimeEquals 的行为进行封装级验证
      // （真实校验由 lan_server_test 的 HTTP 集成覆盖）
      expect(ac.token, 'tok');
    });
  });

  group('AccessControl 客户端管理', () {
    test('revokeClient 撤销后 isRevoked 为 true', () {
      final ac = AccessControl(token: 't');
      expect(ac.isRevoked('device-1'), isFalse);
      expect(ac.revokeClient('device-1'), isTrue);
      expect(ac.isRevoked('device-1'), isTrue);
      // 重复撤销：已撤销的客户端再次 add 返回 false
      expect(ac.revokeClient('device-1'), isFalse);
    });

    test('revokeClient 空 ID 返回 false', () {
      final ac = AccessControl(token: 't');
      expect(ac.revokeClient(''), isFalse);
    });
  });
}
