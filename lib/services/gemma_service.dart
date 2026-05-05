import 'package:flutter/services.dart';

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

  Future<String> refineMeal({
    required String currentMealJson,
    required String userAnswer,
  }) async {
    final result = await _channel.invokeMethod<String>('refineMeal', {
      'currentMealJson': currentMealJson,
      'userAnswer': userAnswer,
    });
    return result ?? '';
  }

  Future<void> dispose() async {
    try {
      await _channel.invokeMethod('disposeModel');
    } catch (_) {}
    _isInitialized = false;
  }
}
