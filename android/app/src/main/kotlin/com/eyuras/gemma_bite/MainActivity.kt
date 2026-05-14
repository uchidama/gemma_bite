package com.eyuras.gemma_bite

import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import com.google.android.gms.tasks.Task
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.ai.edge.litertlm.*
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import java.io.File
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.eyuras.gemma_bite/gemma"

    private var engine: Engine? = null
    private var conversation: Conversation? = null
    private var conversationConfig: ConversationConfig? = null
    private val inferenceMutex = Mutex()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val mainHandler = Handler(Looper.getMainLooper())
    private var textToSpeech: TextToSpeech? = null
    private var isTextToSpeechReady = false

    /**
     * 推論ごとに新しい Conversation を作って KV キャッシュ累積による OOM を防ぐ。
     * Engine は重い（モデルロード）ので使い回し、Conversation だけ毎回作り直す。
     */
    private suspend fun <T> withFreshConversation(
        configOverride: ConversationConfig? = null,
        block: suspend (Conversation) -> T
    ): T {
        val eng = engine ?: error("モデルが初期化されていません")
        val cfg = configOverride ?: conversationConfig ?: error("モデルが初期化されていません")
        return inferenceMutex.withLock {
            var conv: Conversation? = null
            try {
                conv = eng.createConversation(cfg)
                conversation = conv
                block(conv)
            } finally {
                try { conv?.close() } catch (_: Exception) {}
                if (conversation === conv) conversation = null
            }
        }
    }

    private suspend fun extractTextFromImage(imagePath: String): String {
        val recognizer = TextRecognition.getClient(
            JapaneseTextRecognizerOptions.Builder().build()
        )
        return try {
            val image = InputImage.fromFilePath(this, Uri.fromFile(File(imagePath)))
            recognizer.process(image).awaitResult().text
        } finally {
            recognizer.close()
        }
    }

    private suspend fun <T> Task<T>.awaitResult(): T = suspendCancellableCoroutine { cont ->
        addOnSuccessListener { value -> if (cont.isActive) cont.resume(value) }
        addOnFailureListener { error -> if (cont.isActive) cont.resumeWithException(error) }
        addOnCanceledListener { if (cont.isActive) cont.cancel() }
    }

    @OptIn(ExperimentalApi::class)
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

                                // Gemma 4 MTP (speculative decoding) を有効化
                                ExperimentalFlags.enableSpeculativeDecoding = true

                                val config = EngineConfig(
                                    modelPath = modelPath,
                                    backend = Backend.CPU(),
                                    visionBackend = Backend.CPU(),
                                )
                                val eng = Engine(config)
                                eng.initialize()

                                val convCfg = ConversationConfig(
                                    systemInstruction = Contents.of(
                                        "あなたは食事写真から栄養記録を作る専門家です。回答は必ず単一のJSONオブジェクトのみで、配列、説明文、Markdownを含めません。\n" +
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

                                engine = eng
                                conversationConfig = convCfg
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
                        if (engine == null || conversationConfig == null) {
                            result.error("NOT_INITIALIZED", "モデルが初期化されていません", null)
                            return@setMethodCallHandler
                        }

                        scope.launch {
                            try {
                                val response = withFreshConversation { conv ->
                                    conv.sendMessage(
                                        Contents.of(
                                            Content.ImageFile(imagePath),
                                            Content.Text(
                                                "この食事写真を分析し、指定スキーマの単一JSONオブジェクトだけを返してください。配列では返さないでください。見えない部分は推定し、不明点はquestionsに入れてください。"
                                            ),
                                        )
                                    )
                                }
                                mainHandler.post { result.success(response.toString()) }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("ANALYZE_ERROR", e.message, e.stackTraceToString())
                                }
                            }
                        }
                    }

                    "extractTextFromImage" -> {
                        val imagePath = call.argument<String>("imagePath")
                        if (imagePath.isNullOrBlank()) {
                            result.error("INVALID_ARG", "imagePath is required", null)
                            return@setMethodCallHandler
                        }
                        scope.launch {
                            try {
                                val text = extractTextFromImage(imagePath)
                                mainHandler.post { result.success(text) }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("OCR_ERROR", e.message, e.stackTraceToString())
                                }
                            }
                        }
                    }

                    "refineMeal" -> {
                        val currentMealJson = call.argument<String>("currentMealJson")
                        val userAnswer = call.argument<String>("userAnswer")
                        val referenceImagePath = call.argument<String>("referenceImagePath")
                        val ocrText = call.argument<String>("ocrText")
                        if (currentMealJson == null || userAnswer == null) {
                            result.error("INVALID_ARG", "currentMealJson and userAnswer are required", null)
                            return@setMethodCallHandler
                        }
                        if (engine == null || conversationConfig == null) {
                            result.error("NOT_INITIALIZED", "モデルが初期化されていません", null)
                            return@setMethodCallHandler
                        }

                        scope.launch {
                            try {
                                val response = withFreshConversation { conv ->
                                    val userPrompt =
                                        "現在の食事JSON: $currentMealJson\n" +
                                        "ユーザーの回答: $userAnswer\n" +
                                        if (ocrText.isNullOrBlank()) "" else "OCR抽出テキスト: $ocrText\n" +
                                        if (referenceImagePath.isNullOrBlank()) {
                                            "回答を反映して栄養値とsummaryとquestionsを更新し、同じスキーマのJSONだけを返してください。summaryには更新根拠を1-2文で含めてください。OCR抽出テキストがある場合はそちらを優先して数値を解釈してください。"
                                        } else {
                                            "追加で成分表やパッケージ写真を渡します。画像の文字情報も読み取り、回答へ反映してください。回答を反映して栄養値とsummaryとquestionsを更新し、同じスキーマのJSONだけを返してください。summaryには、画像またはOCRテキストから読み取った主要な数値（例: エネルギー, P/F/C, 塩分）を日本語で1-2文に要約して必ず含めてください。OCR抽出テキストがある場合はそちらを優先して数値を解釈してください。"
                                        }

                                    val requestContents = if (referenceImagePath.isNullOrBlank()) {
                                        Contents.of(Content.Text(userPrompt))
                                    } else {
                                        Contents.of(
                                            Content.ImageFile(referenceImagePath),
                                            Content.Text(userPrompt),
                                        )
                                    }

                                    conv.sendMessage(
                                        requestContents
                                    )
                                }
                                mainHandler.post { result.success(response.toString()) }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("REFINE_ERROR", e.message, e.stackTraceToString())
                                }
                            }
                        }
                    }

                    "consultMeal" -> {
                        val mealLogContext = call.argument<String>("mealLogContext")
                        val userMessage = call.argument<String>("userMessage")
                        val responseLanguage = call.argument<String>("responseLanguage") ?: "ja"
                        if (mealLogContext == null || userMessage == null) {
                            result.error("INVALID_ARG", "mealLogContext and userMessage are required", null)
                            return@setMethodCallHandler
                        }
                        if (engine == null) {
                            result.error("NOT_INITIALIZED", "モデルが初期化されていません", null)
                            return@setMethodCallHandler
                        }

                        scope.launch {
                            try {
                                val isEnglish = responseLanguage == "en"
                                val consultConfig = ConversationConfig(
                                    systemInstruction = Contents.of(
                                        if (isEnglish) {
                                            "You are a friendly nutrition coach that suggests the next meal and helps balance nutrition from a meal log.\n" +
                                            "Do not provide medical diagnosis. Answer as general food guidance with practical menu ideas, reasons, and adjustment points.\n" +
                                            "Return readable English prose, not JSON."
                                        } else {
                                            "あなたは食事ログをもとに、次の食事や栄養バランスを日本語で提案する管理栄養士風のAI相談役です。\n" +
                                            "医療診断はせず、一般的な食事提案として答えてください。具体的なメニュー案、理由、調整ポイントを短く実用的に示します。\n" +
                                            "回答はJSONではなく、読みやすい日本語の文章で返してください。"
                                        }
                                    ),
                                    samplerConfig = SamplerConfig(
                                        topK = 40,
                                        topP = 0.95,
                                        temperature = 0.7,
                                    ),
                                )
                                val response = withFreshConversation(consultConfig) { conv ->
                                    conv.sendMessage(
                                        Contents.of(
                                            Content.Text(
                                                if (isEnglish) {
                                                    "Meal log summary:\n$mealLogContext\n\nUser question:\n$userMessage"
                                                } else {
                                                    "食事ログの要約:\n$mealLogContext\n\nユーザーの相談:\n$userMessage"
                                                }
                                            ),
                                        )
                                    )
                                }
                                mainHandler.post { result.success(response.toString()) }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("CONSULT_ERROR", e.message, e.stackTraceToString())
                                }
                            }
                        }
                    }

                    "listTtsVoices" -> {
                        val languageCode = call.argument<String>("languageCode") ?: "ja"
                        listTtsVoices(languageCode, result)
                    }

                    "speakText" -> {
                        val text = call.argument<String>("text")
                        val voiceName = call.argument<String>("voiceName")
                        val languageCode = call.argument<String>("languageCode") ?: "ja"
                        if (text.isNullOrBlank()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        speakText(text, voiceName, languageCode, result)
                    }

                    "stopSpeaking" -> {
                        mainHandler.post {
                            textToSpeech?.stop()
                            result.success(true)
                        }
                    }

                    "disposeModel" -> {
                        scope.launch {
                            try {
                                conversation?.close()
                                engine?.close()
                                conversation = null
                                conversationConfig = null
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

    private fun listTtsVoices(languageCode: String, result: MethodChannel.Result) {
        val locale = ttsLocale(languageCode)
        ensureTextToSpeechReady(
            onReady = { tts ->
                val voices = tts.voices
                    ?.filter { it.locale.language == locale.language }
                    ?.filterNot { it.isNetworkConnectionRequired }
                    ?.sortedWith(compareBy({ it.isNetworkConnectionRequired }, { it.name }))
                    ?.map {
                        mapOf(
                            "name" to it.name,
                            "locale" to it.locale.toLanguageTag(),
                            "quality" to it.quality,
                            "latency" to it.latency,
                            "requiresNetwork" to it.isNetworkConnectionRequired,
                        )
                    }
                    ?: emptyList()
                result.success(voices)
            },
            onError = { code, message -> result.error(code, message, null) },
        )
    }

    private fun speakText(
        text: String,
        voiceName: String?,
        languageCode: String,
        result: MethodChannel.Result
    ) {
        val locale = ttsLocale(languageCode)
        ensureTextToSpeechReady(
            onReady = { tts ->
                applyTtsVoice(tts, voiceName, locale)
                tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "consult_reply")
                result.success(true)
            },
            onError = { code, message -> result.error(code, message, null) },
        )
    }

    private fun ensureTextToSpeechReady(
        onReady: (TextToSpeech) -> Unit,
        onError: (String, String) -> Unit,
    ) {
        mainHandler.post {
            val currentTts = textToSpeech
            if (currentTts != null && isTextToSpeechReady) {
                onReady(currentTts)
                return@post
            }

            textToSpeech?.shutdown()
            isTextToSpeechReady = false
            textToSpeech = TextToSpeech(this) { status ->
                mainHandler.post {
                    val tts = textToSpeech
                    if (status != TextToSpeech.SUCCESS || tts == null) {
                        onError("TTS_INIT_ERROR", "音声読み上げを初期化できませんでした")
                        return@post
                    }

                    if (!applyTtsVoice(tts, null, Locale.JAPANESE)) {
                        onError("TTS_LANG_ERROR", "日本語の音声読み上げに対応していません")
                        return@post
                    }

                    isTextToSpeechReady = true
                    onReady(tts)
                }
            }
        }
    }

    private fun applyTtsVoice(tts: TextToSpeech, voiceName: String?, locale: Locale): Boolean {
        if (!voiceName.isNullOrBlank()) {
            val voice = tts.voices?.firstOrNull { it.name == voiceName }
            if (voice != null && tts.setVoice(voice) == TextToSpeech.SUCCESS) {
                return true
            }
        }

        val availability = tts.setLanguage(locale)
        return availability != TextToSpeech.LANG_MISSING_DATA &&
            availability != TextToSpeech.LANG_NOT_SUPPORTED
    }

    private fun ttsLocale(languageCode: String): Locale {
        return if (languageCode == "en") Locale.ENGLISH else Locale.JAPANESE
    }

    override fun onDestroy() {
        scope.cancel()
        try {
            conversation?.close()
            engine?.close()
            textToSpeech?.stop()
            textToSpeech?.shutdown()
        } catch (_: Exception) {}
        super.onDestroy()
    }
}
