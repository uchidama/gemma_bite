import 'dart:convert';

class NutritionTotals {
  const NutritionTotals({
    required this.caloriesKcal,
    required this.proteinG,
    required this.fatG,
    required this.carbohydrateG,
    required this.saltG,
    required this.caffeineMg,
    required this.alcoholG,
  });

  const NutritionTotals.empty()
    : caloriesKcal = 0,
      proteinG = 0,
      fatG = 0,
      carbohydrateG = 0,
      saltG = 0,
      caffeineMg = 0,
      alcoholG = 0;

  final double caloriesKcal;
  final double proteinG;
  final double fatG;
  final double carbohydrateG;
  final double saltG;
  final double caffeineMg;
  final double alcoholG;

  NutritionTotals operator +(NutritionTotals other) {
    return NutritionTotals(
      caloriesKcal: caloriesKcal + other.caloriesKcal,
      proteinG: proteinG + other.proteinG,
      fatG: fatG + other.fatG,
      carbohydrateG: carbohydrateG + other.carbohydrateG,
      saltG: saltG + other.saltG,
      caffeineMg: caffeineMg + other.caffeineMg,
      alcoholG: alcoholG + other.alcoholG,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'caloriesKcal': caloriesKcal,
      'proteinG': proteinG,
      'fatG': fatG,
      'carbohydrateG': carbohydrateG,
      'saltG': saltG,
      'caffeineMg': caffeineMg,
      'alcoholG': alcoholG,
    };
  }

  factory NutritionTotals.fromJson(Map<String, dynamic> json) {
    double number(String key) {
      final value = json[key];
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0;
      return 0;
    }

    return NutritionTotals(
      caloriesKcal: number('caloriesKcal'),
      proteinG: number('proteinG'),
      fatG: number('fatG'),
      carbohydrateG: number('carbohydrateG'),
      saltG: number('saltG'),
      caffeineMg: number('caffeineMg'),
      alcoholG: number('alcoholG'),
    );
  }
}

class MealMessage {
  const MealMessage({
    required this.role,
    required this.text,
    required this.createdAt,
  });

  final String role;
  final String text;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory MealMessage.fromJson(Map<String, dynamic> json) {
    return MealMessage(
      role: json['role'] as String? ?? 'assistant',
      text: json['text'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class MealEntry {
  const MealEntry({
    required this.id,
    required this.imagePath,
    required this.eatenAt,
    required this.foodName,
    required this.summary,
    required this.nutrition,
    required this.confidence,
    required this.questions,
    required this.messages,
    required this.rawGemmaResponse,
  });

  final String id;
  final String imagePath;
  final DateTime eatenAt;
  final String foodName;
  final String summary;
  final NutritionTotals nutrition;
  final double confidence;
  final List<String> questions;
  final List<MealMessage> messages;
  final String rawGemmaResponse;

  bool get needsClarification => questions.isNotEmpty;

  MealEntry copyWith({
    String? foodName,
    String? summary,
    NutritionTotals? nutrition,
    double? confidence,
    List<String>? questions,
    List<MealMessage>? messages,
    String? rawGemmaResponse,
  }) {
    return MealEntry(
      id: id,
      imagePath: imagePath,
      eatenAt: eatenAt,
      foodName: foodName ?? this.foodName,
      summary: summary ?? this.summary,
      nutrition: nutrition ?? this.nutrition,
      confidence: confidence ?? this.confidence,
      questions: questions ?? this.questions,
      messages: messages ?? this.messages,
      rawGemmaResponse: rawGemmaResponse ?? this.rawGemmaResponse,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imagePath': imagePath,
      'eatenAt': eatenAt.toIso8601String(),
      'foodName': foodName,
      'summary': summary,
      'nutrition': nutrition.toJson(),
      'confidence': confidence,
      'questions': questions,
      'messages': messages.map((message) => message.toJson()).toList(),
      'rawGemmaResponse': rawGemmaResponse,
    };
  }

  factory MealEntry.fromJson(Map<String, dynamic> json) {
    return MealEntry(
      id:
          json['id'] as String? ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      imagePath: json['imagePath'] as String? ?? '',
      eatenAt:
          DateTime.tryParse(json['eatenAt'] as String? ?? '') ?? DateTime.now(),
      foodName: json['foodName'] as String? ?? '食事',
      summary: json['summary'] as String? ?? '',
      nutrition: NutritionTotals.fromJson(
        json['nutrition'] as Map<String, dynamic>? ?? const {},
      ),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
      questions: (json['questions'] as List<dynamic>? ?? const [])
          .map((question) => question.toString())
          .where((question) => question.trim().isNotEmpty)
          .toList(),
      messages: (json['messages'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MealMessage.fromJson)
          .toList(),
      rawGemmaResponse: json['rawGemmaResponse'] as String? ?? '',
    );
  }

  static MealEntry fromGemmaJson({
    required String imagePath,
    required DateTime eatenAt,
    required String response,
  }) {
    final decoded = _decodeGemmaResponse(response);
    final questions = (decoded['questions'] as List<dynamic>? ?? const [])
        .map((question) => question.toString())
        .where((question) => question.trim().isNotEmpty)
        .toList();
    final summary = decoded['summary'] as String? ?? '';

    return MealEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      imagePath: imagePath,
      eatenAt: eatenAt,
      foodName: decoded['foodName'] as String? ?? '食事',
      summary: summary,
      nutrition: NutritionTotals.fromJson(
        decoded['nutrition'] as Map<String, dynamic>? ?? const {},
      ),
      confidence:
          (decoded['confidence'] as num?)?.toDouble().clamp(0, 1) ?? 0.5,
      questions: questions,
      messages: [
        if (questions.isNotEmpty)
          MealMessage(
            role: 'assistant',
            text: questions.join('\n'),
            createdAt: DateTime.now(),
          )
        else
          MealMessage(
            role: 'assistant',
            text: summary.isEmpty ? '分析を記録しました。' : summary,
            createdAt: DateTime.now(),
          ),
      ],
      rawGemmaResponse: response,
    );
  }

  static Map<String, dynamic> _decodeGemmaResponse(String response) {
    final trimmed = response.trim();
    final fenced = RegExp(
      r'```(?:json)?\s*([\s\S]*?)\s*```',
      multiLine: true,
    ).firstMatch(trimmed);
    final jsonText = fenced?.group(1) ?? _extractJsonObject(trimmed) ?? trimmed;
    final decoded = jsonDecode(jsonText);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const FormatException('Gemma response is not a JSON object');
  }

  static String? _extractJsonObject(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end <= start) return null;
    return text.substring(start, end + 1);
  }
}

class UserProfile {
  const UserProfile({required this.heightCm, required this.weightKg});

  final double heightCm;
  final double weightKg;

  bool get isComplete => heightCm > 0 && weightKg > 0;

  Map<String, dynamic> toJson() {
    return {'heightCm': heightCm, 'weightKg': weightKg};
  }

  factory UserProfile.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const UserProfile(heightCm: 0, weightKg: 0);
    }
    double number(String key) {
      final value = json[key];
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0;
      return 0;
    }

    return UserProfile(
      heightCm: number('heightCm'),
      weightKg: number('weightKg'),
    );
  }
}
