package com.xycz.simple_live

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/**
 * 局域网服务器前台服务：
 * - 保持进程常驻（通知栏常驻通知）；
 * - 持有 WakeLock / WifiLock，锁屏后维持网络服务能力；
 * - 通知上的「停止」按钮会回调 Dart 侧停止 HTTP 服务。
 */
class LanServerService : Service() {

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        acquireLocks()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            notifyDartStopped()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "SimpleLive 局域网服务"
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: "服务运行中"
        val notification = buildNotification(title, text)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_STICKY
    }

    override fun onDestroy() {
        releaseLocks()
        super.onDestroy()
    }

    private fun acquireLocks() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "simple_live:lan_server")
        wakeLock?.setReferenceCounted(false)
        wakeLock?.acquire(12 * 60 * 60 * 1000L)

        val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        if (wm != null) {
            @Suppress("DEPRECATION")
            wifiLock = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "simple_live:lan_wifi")
            wifiLock?.setReferenceCounted(false)
            wifiLock?.acquire()
        }
    }

    private fun releaseLocks() {
        try {
            wakeLock?.release()
            wifiLock?.release()
        } catch (_: Exception) {
        }
        wakeLock = null
        wifiLock = null
    }

    private fun createChannel() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "局域网服务",
            NotificationManager.IMPORTANCE_LOW,
        )
        channel.description = "SimpleLive 局域网服务器运行状态"
        channel.setShowBadge(false)
        nm.createNotificationChannel(channel)
    }

    private fun buildNotification(title: String, text: String): Notification {
        val stopIntent = PendingIntent.getService(
            this,
            0,
            Intent(this, LanServerService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val openIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setSmallIcon(android.R.drawable.stat_notify_sync_noanim)
            .setOngoing(true)
            .setContentIntent(openIntent)
            .addAction(Notification.Action.Builder(null, "停止服务", stopIntent).build())
            .build()
    }

    private fun notifyDartStopped() {
        val engine = FlutterEngineCache.getInstance().get(MainApplication.ENGINE_ID) ?: return
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .invokeMethod("onServiceStopped", null)
    }

    companion object {
        const val CHANNEL_ID = "simple_live_lan_server"
        const val CHANNEL_NAME = "simple_live/lan_server"
        const val ACTION_STOP = "com.xycz.simple_live.lan.STOP"
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val NOTIFICATION_ID = 20261

        fun start(context: Context, title: String, text: String) {
            val intent = Intent(context, LanServerService::class.java)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_TEXT, text)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun update(context: Context, text: String) {
            val intent = Intent(context, LanServerService::class.java)
                .putExtra(EXTRA_TEXT, text)
            context.startService(intent)
        }

        fun stop(context: Context) {
            context.startService(
                Intent(context, LanServerService::class.java).setAction(ACTION_STOP),
            )
        }
    }
}
