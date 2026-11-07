import 'dart:io';

/// 局域网地址工具：枚举本机网卡上的局域网 IPv4 地址。
class IpUtils {
  IpUtils._();

  /// 返回所有非回环的 IPv4 地址（含端口由调用方拼接）。
  ///
  /// [preferWifi] 为 true 时优先返回常见 Wi-Fi/以太网网卡（wlan/eth/enp/wlp）
  /// 上的地址，热点/VPN（ap、rmnet、tun 等）排在后面。
  static Future<List<String>> lanIpv4Addresses({bool preferWifi = true}) async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );

    final wifi = <String>[];
    final others = <String>[];
    for (final itf in interfaces) {
      final name = itf.name.toLowerCase();
      final isWifiLike = name.startsWith('wlan') ||
          name.startsWith('eth') ||
          name.startsWith('enp') ||
          name.startsWith('wlp') ||
          name.startsWith('en0');
      for (final addr in itf.addresses) {
        final host = addr.address;
        if (addr.isLoopback || addr.isMulticast) {
          continue;
        }
        if (!host.startsWith('169.254.') && !_isPrivateIpv4(host)) {
          // 排除链路本地地址；公网地址（极少见的直连场景）也排除，
          // 避免把服务器地址广播到不可达的网段。
          continue;
        }
        if (preferWifi && isWifiLike) {
          wifi.add(host);
        } else {
          others.add(host);
        }
      }
    }
    return [...wifi, ...others];
  }

  /// 判断是否为 RFC1918 私网地址。
  static bool _isPrivateIpv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) {
      return false;
    }
    final n = parts.map((p) => int.tryParse(p) ?? -1).toList();
    bool inRange(int v, int lo, int hi) => v >= lo && v <= hi;
    if (n[0] == 10) {
      return true;
    }
    if (n[0] == 192 && n[1] == 168) {
      return true;
    }
    if (n[0] == 172 && inRange(n[1], 16, 31)) {
      return true;
    }
    return false;
  }

  /// 从 Host/Origin 头中提取主机部分（去掉端口与方括号）。
  static String hostFromAuthority(String authority) {
    var host = authority.trim();
    if (host.startsWith('[')) {
      final end = host.indexOf(']');
      return end > 0 ? host.substring(1, end) : host;
    }
    final idx = host.lastIndexOf(':');
    if (idx > 0 && !host.contains(']')) {
      host = host.substring(0, idx);
    }
    return host;
  }
}
