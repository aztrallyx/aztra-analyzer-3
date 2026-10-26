package PLACEHOLDER

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aztra/analysis_service")
            .setMethodCallHandler { call, result ->
                val title = call.argument<String>("title") ?: ""
                val text = call.argument<String>("text") ?: ""
                val progress = call.argument<Int>("progress") ?: -1
                val max = call.argument<Int>("max") ?: 0

                when (call.method) {
                    "start" -> {
                        val intent = Intent(this, AnalysisService::class.java)
                        intent.putExtra("title", title)
                        intent.putExtra("text", text)
                        intent.putExtra("progress", progress)
                        intent.putExtra("max", max)
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "update" -> {
                        AnalysisService.instance?.update(title, text, progress, max)
                        result.success(true)
                    }
                    "finish" -> {
                        val service = AnalysisService.instance
                        if (service != null) {
                            service.finishWith(title, text)
                        } else {
                            stopService(Intent(this, AnalysisService::class.java))
                        }
                        result.success(true)
                    }
                    "stop" -> {
                        stopService(Intent(this, AnalysisService::class.java))
                        result.success(true)
                    }
                    "moveToBack" -> {
                        moveTaskToBack(true)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
