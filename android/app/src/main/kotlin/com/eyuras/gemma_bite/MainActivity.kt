package com.eyuras.gemma_bite

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.ai.edge.litertlm.*
import kotlinx.coroutines.*
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.eyuras.gemma_bite/gemma"

    private var engine: Engine? = null
    private var conversation: Conversation? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getModelDirectory" -> {
                        val dir = getModelDir()
                        dir.mkdirs()
                        result.success(dir.absolutePath)
                    }

                    "listModels" -> {
                        val dir = getModelDir()
                        val models = dir.listFiles()
                            ?.filter { it.extension == "litertlm" }
                            ?.map { it.absolutePath }
                            ?: emptyList()
                        result.success(models)
                    }

                    "initializeModel" -> {
                        val modelPath = call.argument<String>("modelPath")
                        if (modelPath == null) {
                            result.error("INVALID_ARG", "modelPath is required", null)
                            return@setMethodCallHandler
                        }
                        scope.launch {
                            try {
                                // Close existing engine if any
                                conversation?.close()
                                engine?.close()

                                val config = EngineConfig(
                                    modelPath = modelPath,
                                    backend = Backend.CPU(),
                                    visionBackend = Backend.CPU(),
                                )
                                val eng = Engine(config)
                                eng.initialize()

                                val conv = eng.createConversation(
                                    ConversationConfig(
                                        systemInstruction = Contents.of(
                                            "あなたは栄養分析の専門家です。食事や飲み物の写真が提示されたら、以下を提供してください：\n" +
                                            "1. 推定総カロリー\n" +
                                            "2. 主要栄養素の内訳（タンパク質、脂質、炭水化物をグラム単位で）\n" +
                                            "3. 含まれる主なビタミン・ミネラル\n" +
                                            "4. アルコール含有量（該当する場合、推定グラム数と標準ドリンク数）\n" +
                                            "5. この食事に関する簡潔な健康アドバイス\n" +
                                            "不確かな場合は概算範囲を使用してください。日本語で回答してください。"
                                        ),
                                        samplerConfig = SamplerConfig(
                                            topK = 40,
                                            topP = 0.95,
                                            temperature = 0.7,
                                        ),
                                    )
                                )

                                engine = eng
                                conversation = conv
                                mainHandler.post { result.success(true) }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("INIT_ERROR", e.message, e.stackTraceToString())
                                }
                            }
                        }
                    }

                    "analyzeFood" -> {
                        val imagePath = call.argument<String>("imagePath")
                        if (imagePath == null) {
                            result.error("INVALID_ARG", "imagePath is required", null)
                            return@setMethodCallHandler
                        }
                        val conv = conversation
                        if (conv == null) {
                            result.error("NOT_INITIALIZED", "モデルが初期化されていません", null)
                            return@setMethodCallHandler
                        }

                        scope.launch {
                            try {
                                val response = conv.sendMessage(
                                    Contents.of(
                                        Content.ImageFile(imagePath),
                                        Content.Text("この食事の写真を分析してください。"),
                                    )
                                )
                                mainHandler.post { result.success(response.toString()) }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("ANALYZE_ERROR", e.message, e.stackTraceToString())
                                }
                            }
                        }
                    }

                    "disposeModel" -> {
                        scope.launch {
                            try {
                                conversation?.close()
                                engine?.close()
                                conversation = null
                                engine = null
                                mainHandler.post { result.success(true) }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("DISPOSE_ERROR", e.message, null)
                                }
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun getModelDir(): File {
        return File(context.getExternalFilesDir(null), "models")
    }

    override fun onDestroy() {
        scope.cancel()
        try {
            conversation?.close()
            engine?.close()
        } catch (_: Exception) {}
        super.onDestroy()
    }
}
