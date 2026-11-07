import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/services/lan_server_service.dart';
import 'package:simple_live_lan_server/simple_live_lan_server.dart' show LanServerStatus;

/// 局域网服务器控制页。
class LanServerPage extends StatelessWidget {
  LanServerPage({Key? key}) : super(key: key);

  final LanServerService service = LanServerService.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("局域网服务器"),
      ),
      body: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          _buildStatusCard(context),
          AppStyle.vGap12,
          _buildQrCard(context),
          AppStyle.vGap12,
          _buildClientsCard(context),
          AppStyle.vGap12,
          _buildKeepAliveCard(context),
          AppStyle.vGap12,
          _buildHelpCard(context),
        ],
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    return _card(
      context,
      child: Obx(
        () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.lan,
                  color: service.isRunning
                      ? Colors.green
                      : Theme.of(context).colorScheme.primary,
                ),
                AppStyle.hGap8,
                Text(
                  _statusText(),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (service.isRunning)
                  TextButton(
                    onPressed: () => service.stop(),
                    child: const Text("停止服务"),
                  ),
              ],
            ),
            AppStyle.vGap8,
            if (service.isRunning) ...[
              _infoRow(
                "服务地址",
                service.entryUrl.value.isEmpty
                    ? "http://${service.addresses.isNotEmpty ? service.addresses.first : "?"}:${service.port}"
                    : service.entryUrl.value.split('?').first,
              ),
              _infoRow("端口", "${service.port}"),
              _infoRow("已连接设备", "${service.activeClients.value} 台"),
              _infoRow("弹幕房间", "${service.danmakuRooms.value} 个 · WebSocket ${service.wsClients.value} 连接"),
              if (service.addresses.length > 1)
                _infoRow(
                  "其它网卡地址",
                  service.addresses.skip(1).map((a) => "http://$a:${service.port}").join("\n"),
                ),
            ] else ...[
              Text(
                service.status.value == LanServerStatus.error
                    ? "启动失败：${service.errorText.value}"
                    : "在同一 Wi-Fi 下提供网页服务，iPad/电脑浏览器直接访问即可观看直播。",
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              AppStyle.vGap8,
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: service.status.value == LanServerStatus.starting
                      ? null
                      : () => service.start(),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    service.status.value == LanServerStatus.starting
                        ? "正在启动…"
                        : "启动服务",
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _statusText() {
    switch (service.status.value) {
      case LanServerStatus.stopped:
        return "服务未启动";
      case LanServerStatus.starting:
        return "正在启动…";
      case LanServerStatus.running:
        return "服务运行中";
      case LanServerStatus.error:
        return "服务异常";
    }
  }

  Widget _buildQrCard(BuildContext context) {
    return Obx(
      () => _card(
        context,
        child: service.isRunning
            ? Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: AppStyle.radius12,
                    ),
                    child: QrImageView(
                      data: service.entryUrl.value,
                      size: 220,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  AppStyle.vGap8,
                  const Text(
                    "用 iPad 相机扫描二维码打开直播页面",
                    style: TextStyle(fontSize: 12.5, color: Colors.grey),
                  ),
                  AppStyle.vGap8,
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: service.entryUrl.value),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("已复制访问地址")),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text("复制地址"),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final t = await service.resetToken();
                          _showTokenDialog(context, t);
                        },
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text("重置令牌"),
                      ),
                    ],
                  ),
                ],
              )
            : const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  "启动服务后，这里会显示配对二维码与访问令牌。",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ),
      ),
    );
  }

  void _showTokenDialog(BuildContext context, String token) {
    Get.defaultDialog(
      title: "新的访问令牌",
      content: Column(
        children: [
          SelectableText(
            token,
            style: const TextStyle(fontFamily: "monospace", fontSize: 15),
          ),
          AppStyle.vGap8,
          const Text(
            "重置后所有已配对设备需要重新扫码配对。",
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      textConfirm: "复制并关闭",
      onConfirm: () {
        Clipboard.setData(ClipboardData(text: token));
        Get.back();
      },
      textCancel: "关闭",
      onCancel: Get.back,
    );
  }

  Widget _buildClientsCard(BuildContext context) {
    return Obx(
      () => _card(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "已配对客户端",
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            AppStyle.vGap8,
            if (!service.isRunning)
              const Text(
                "启动服务后可在此查看与撤销已连接的设备。",
                style: TextStyle(fontSize: 13, color: Colors.grey),
              )
            else if (service.activeClients.value == 0)
              const Text(
                "暂无设备连接",
                style: TextStyle(fontSize: 13, color: Colors.grey),
              )
            else
              Text(
                "共 ${service.activeClients.value} 台设备在线（5 分钟内活跃）。\n连接过的设备保存在服务端，重置令牌可全部撤销。",
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeepAliveCard(BuildContext context) {
    return _card(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "后台保活助手",
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          AppStyle.vGap4,
          const Text(
            "部分厂商系统会积极清理后台。若锁屏后服务断开，可尝试以下设置：",
            style: TextStyle(fontSize: 12.5, color: Colors.grey, height: 1.5),
          ),
          AppStyle.vGap8,
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.battery_saver),
            title: const Text("请求忽略电池优化"),
            subtitle: const Text("将本应用加入电池优化白名单"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => service.requestIgnoreBatteryOptimizations(),
          ),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.settings_applications),
            title: const Text("自启动管理"),
            subtitle: const Text("跳转到系统自启动设置页（支持 MIUI/EMUI/ColorOS/OriginOS 等）"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => service.openAutoStartSettings(),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpCard(BuildContext context) {
    return _card(
      context,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "使用说明",
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 6),
          Text(
            "1. 手机与观看设备连接同一个 Wi-Fi；\n"
            "2. 点击「启动服务」，用 iPad 扫描二维码（或手动输入地址和令牌）；\n"
            "3. 手机只负责提供页面、解析直播地址与转发弹幕，视频由观看设备直接连接平台 CDN 播放；\n"
            "4. 服务在前台通知中持续运行，锁屏后仍可访问；\n"
            "5. 点击通知中的「停止」或页面上的「停止服务」关闭。",
            style: TextStyle(fontSize: 13, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: AppStyle.radius12,
      ),
      child: child,
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 13.5, fontFamily: "monospace"),
            ),
          ),
        ],
      ),
    );
  }
}
