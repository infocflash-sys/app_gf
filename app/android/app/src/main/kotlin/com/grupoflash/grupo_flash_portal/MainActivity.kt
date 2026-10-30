package com.grupoflash.grupo_flash_portal

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // "minimize" manda la app a segundo plano SIN cerrarla: al volver a abrirla queda como estaba.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.grupoflash.portal/app")
            .setMethodCallHandler { call, result ->
                if (call.method == "minimize") {
                    moveTaskToBack(true)
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }
    }
}
