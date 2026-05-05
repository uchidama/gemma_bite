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
                                            "あなたは食事写真から栄養記録を作る専門家です。回答は必ずJSONのみで、説明文やMarkdownを含めません。\n" +
                                            "スキーマ: {\"foodName\": string, \"summary\": string, \"nutrition\": {\"caloriesKcal\": number, \"proteinG\": number, \"fatG\": number, \"carbohydrateG\": number, \"saltG\": number, \"caffeineMg\": number, \"alcoholG\": number}, \"confidence\": number, \"questions\": string[]}\n" +
                                            "nutritionは見える量から1食分として推定します。PFC、総カロリー、塩分を最優先し、カフェインとアルコールは該当しない場合0にします。\n" +
                                            "正確に判断できない食材、量、飲み物、調味料がある場合はquestionsに日本語の短い確認質問を最大3件入れます。質問が不要なら空配列にします。confidenceは0から1です。"
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
                                        Content.Text(
                                            "この食事写真を分析し、指定スキーマのJSONだけを返してください。見えない部分は推定し、不明点はquestionsに入れてください。"
                                        ),
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

                    "refineMeal" -> {
                        val currentMealJson = call.argument<String>("currentMealJson")
                        val userAnswer = call.argument<String>("userAnswer")
                        if (currentMealJson == null || userAnswer == null) {
                            result.error("INVALID_ARG", "currentMealJson and userAnswer are required", null)
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
                                        Content.Text(
                                            "現在の食事JSON: $currentMealJson\n" +
                                            "ユーザーの回答: $userAnswer\n" +
                                            "回答を反映して栄養値とsummaryとquestionsを更新し、同じスキーマのJSONだけを返してください。"
                                        ),
                                    )
                                )
                                mainHandler.post { result.success(response.toString()) }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("REFINE_ERROR", e.message, e.stackTraceToString())
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
