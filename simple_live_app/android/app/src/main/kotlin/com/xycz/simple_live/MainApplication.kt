package com.xycz.simple_live

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * 自定义 Application：启动时创建并缓存 FlutterEngine。
 *
 * 引擎与 Activity 解耦后，用户从最近任务划掉界面时，
 * Dart 侧的局域网 HTTP 服务可以随前台服务继续存活；
 * 再次打开 App 会重新附加到同一个引擎，状态不丢失。
 */
class MainApplication : Application() {

    override fun onCreate() {
        super.onCreate()
        val engine = FlutterEngineGroup(this)
            .createAndRunEngine(this, DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
    }

    companion object {
        const val ENGINE_ID = "simple_live_main_engine"
    }
}
