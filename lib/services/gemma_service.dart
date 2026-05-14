import 'package:flutter/services.dart';

class TtsVoice {
  const TtsVoice({
    required this.name,
    required this.locale,
    required this.quality,
    required this.latency,
    required this.requiresNetwork,
  });

  final String name;
  final String locale;
  final int quality;
  final int latency;
  final bool requiresNetwork;

  String get label {
    return '$name ($locale)';
  }

  factory TtsVoice.fromJson(Map<dynamic, dynamic> json) {
    return TtsVoice(
      name: json['name'] as String? ?? '',
      locale: json['locale'] as String? ?? '',
      quality: json['quality'] as int? ?? 0,
      latency: json['latency'] as int? ?? 0,
      requiresNetwork: json['requiresNetwork'] as bool? ?? false,
    );
  }
}

class GemmaService {
  static const _channel = MethodChannel('com.eyuras.gemma_bite/gemma');

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  Future<String> getModelDirectory() async {
    final path = await _channel.invokeMethod<String>('getModelDirectory');
    return path ?? '';
  }

  Future<List<String>> listModels() async {
    final models = await _channel.invokeMethod<List<dynamic>>('listModels');
    return models?.cast<String>() ?? [];
  }

  Future<void> initialize(String modelPath) async {
    await _channel.invokeMethod('initializeModel', {'modelPath': modelPath});
    _isInitialized = true;
  }

  Future<String> analyzeFood(String imagePath) async {
    final result = await _channel.invokeMethod<String>('analyzeFood', {
      'imagePath': imagePath,
    });
    return result ?? '';
  }

  Future<String> extractTextFromImage(String imagePath) async {
    final result = await _channel.invokeMethod<String>('extractTextFromImage', {
      'imagePath': imagePath,
    });
    return result ?? '';
  }

  Future<String> refineMeal({
    required String currentMealJson,
    required String userAnswer,
    String? referenceImagePath,
    String? ocrText,
  }) async {
    final result = await _channel.invokeMethod<String>('refineMeal', {
      'currentMealJson': currentMealJson,
      'userAnswer': userAnswer,
      'referenceImagePath': referenceImagePath,
      'ocrText': ocrText,
    });
    return result ?? '';
  }

  Future<String> consultMeal({
    required String mealLogContext,
    required String userMessage,
    required String responseLanguage,
  }) async {
    final result = await _channel.invokeMethod<String>('consultMeal', {
      'mealLogContext': mealLogContext,
      'userMessage': userMessage,
      'responseLanguage': responseLanguage,
    });
    return result ?? '';
  }

  Future<List<TtsVoice>> listTtsVoices({required String languageCode}) async {
    final voices = await _channel.invokeMethod<List<dynamic>>('listTtsVoices', {
      'languageCode': languageCode,
    });
    return (voices ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map(TtsVoice.fromJson)
        .where((voice) => voice.name.isNotEmpty)
        .toList();
  }

  Future<void> speakText(
    String text, {
    String? voiceName,
    required String languageCode,
  }) async {
    if (text.trim().isEmpty) return;
    await _channel.invokeMethod('speakText', {
      'text': text,
      'voiceName': voiceName,
      'languageCode': languageCode,
    });
  }

  Future<void> stopSpeaking() async {
    await _channel.invokeMethod('stopSpeaking');
  }

  Future<void> dispose() async {
    try {
      await stopSpeaking();
      await _channel.invokeMethod('disposeModel');
    } catch (_) {}
    _isInitialized = false;
  }
}
