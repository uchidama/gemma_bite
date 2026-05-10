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
    this.imagePath,
  });

  final String role;
  final String text;
  final DateTime createdAt;
  final String? imagePath;

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
      'imagePath': imagePath,
    };
  }

  factory MealMessage.fromJson(Map<String, dynamic> json) {
    return MealMessage(
      role: json['role'] as String? ?? 'assistant',
      text: json['text'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      imagePath: (json['imagePath'] as String?)?.trim().isEmpty == true
          ? null
          : json['imagePath'] as String?,
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
    Map<String, dynamic> decoded;
    try {
      decoded = _decodeGemmaResponse(response);
    } on FormatException {
      return _fromGemmaText(
        imagePath: imagePath,
        eatenAt: eatenAt,
        response: response,
      );
    }

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

  static MealEntry _fromGemmaText({
    required String imagePath,
    required DateTime eatenAt,
    required String response,
  }) {
    final summary = _cleanResponse(response);
    final questions = _extractQuestions(summary);
    final nutrition = NutritionTotals(
      caloriesKcal:
          _extractLabeledNumber(summary, const ['総カロリー', 'カロリー', '熱量']) ??
          _extractUnitNumber(summary, 'kcal') ??
          0,
      proteinG:
          _extractLabeledNumber(summary, const [
            'タンパク質',
            'たんぱく質',
            'protein',
            'P',
          ]) ??
          0,
      fatG: _extractLabeledNumber(summary, const ['脂質', 'fat', 'F']) ?? 0,
      carbohydrateG:
          _extractLabeledNumber(summary, const [
            '炭水化物',
            '糖質',
            'carbohydrate',
            'C',
          ]) ??
          0,
      saltG: _extractLabeledNumber(summary, const ['塩分', '食塩相当量', 'salt']) ?? 0,
      caffeineMg:
          _extractLabeledNumber(summary, const ['カフェイン', 'caffeine']) ?? 0,
      alcoholG: _extractLabeledNumber(summary, const ['アルコール', 'alcohol']) ?? 0,
    );

    final fallbackQuestion = questions.isEmpty
        ? ['Gemmaの回答が文章形式でした。食材や量に補足があれば入力してください。']
        : questions;
    final foodName = _extractFoodName(summary);

    return MealEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      imagePath: imagePath,
      eatenAt: eatenAt,
      foodName: foodName,
      summary: summary.isEmpty ? 'Gemmaの分析結果を暫定記録しました。' : summary,
      nutrition: nutrition,
      confidence: 0.35,
      questions: fallbackQuestion,
      messages: [
        MealMessage(
          role: 'assistant',
          text: fallbackQuestion.join('\n'),
          createdAt: DateTime.now(),
        ),
      ],
      rawGemmaResponse: response,
    );
  }

  static String _cleanResponse(String response) {
    return response
        .replaceAll(RegExp(r'```(?:json)?'), '')
        .replaceAll('```', '')
        .trim();
  }

  static String _extractFoodName(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return '食事';

    final first = lines.first
        .replaceFirst(RegExp(r'^[#*\-\d.、\s]+'), '')
        .replaceFirst(RegExp(r'^(料理名|食事名|内容)[:：]\s*'), '')
        .trim();
    if (first.isEmpty) return '食事';
    return first.length > 32 ? '${first.substring(0, 32)}...' : first;
  }

  static List<String> _extractQuestions(String text) {
    return text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.endsWith('？') || line.endsWith('?'))
        .toList();
  }

  static double? _extractLabeledNumber(String text, List<String> labels) {
    for (final label in labels) {
      final escaped = RegExp.escape(label);
      final match = RegExp(
        '$escaped[^0-9０-９.,．，-]{0,24}([0-9０-９]+(?:[.,．，][0-9０-９]+)?)',
        caseSensitive: false,
      ).firstMatch(text);
      final value = match == null ? null : _parseLooseNumber(match.group(1));
      if (value != null) return value;
    }
    return null;
  }

  static double? _extractUnitNumber(String text, String unit) {
    final match = RegExp(
      '([0-9０-９]+(?:[.,．，][0-9０-９]+)?)\\s*$unit',
      caseSensitive: false,
    ).firstMatch(text);
    return match == null ? null : _parseLooseNumber(match.group(1));
  }

  static double? _parseLooseNumber(String? text) {
    if (text == null) return null;
    final normalized = text
        .trim()
        .replaceAll('，', '.')
        .replaceAll(',', '.')
        .replaceAll('．', '.')
        .replaceAll('０', '0')
        .replaceAll('１', '1')
        .replaceAll('２', '2')
        .replaceAll('３', '3')
        .replaceAll('４', '4')
        .replaceAll('５', '5')
        .replaceAll('６', '6')
        .replaceAll('７', '7')
        .replaceAll('８', '8')
        .replaceAll('９', '9');
    return double.tryParse(normalized);
  }

  static String? _extractJsonObject(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end <= start) return null;
    return text.substring(start, end + 1);
  }
}

class UserProfile {
  const UserProfile({
    required this.heightCm,
    required this.weightKg,
    this.weightHistory = const [],
    this.birthDate,
    this.gender = genderNoAnswer,
    this.notes = '',
  });

  static const genderMale = 'male';
  static const genderFemale = 'female';
  static const genderNoAnswer = 'noAnswer';

  final double heightCm;
  final double weightKg;
  final List<WeightEntry> weightHistory;
  final DateTime? birthDate;
  final String gender;
  final String notes;

  bool get isComplete => heightCm > 0 && weightKg > 0 && birthDate != null;

  Map<String, dynamic> toJson() {
    return {
      'heightCm': heightCm,
      'weightKg': weightKg,
      'weightHistory': weightHistory.map((entry) => entry.toJson()).toList(),
      'birthDate': birthDate?.toIso8601String(),
      'gender': gender,
      'notes': notes,
    };
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

    final gender = json['gender'] as String? ?? genderNoAnswer;
    final weightHistory =
        (json['weightHistory'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(WeightEntry.fromJson)
            .where((entry) => entry.weightKg > 0)
            .toList()
          ..sort((a, b) => a.enteredAt.compareTo(b.enteredAt));

    return UserProfile(
      heightCm: number('heightCm'),
      weightKg: number('weightKg'),
      weightHistory: weightHistory,
      birthDate: DateTime.tryParse(json['birthDate'] as String? ?? ''),
      gender: switch (gender) {
        genderMale || genderFemale || genderNoAnswer => gender,
        _ => genderNoAnswer,
      },
      notes: json['notes'] as String? ?? '',
    );
  }
}

class WeightEntry {
  const WeightEntry({required this.enteredAt, required this.weightKg});

  final DateTime enteredAt;
  final double weightKg;

  Map<String, dynamic> toJson() {
    return {'enteredAt': enteredAt.toIso8601String(), 'weightKg': weightKg};
  }

  factory WeightEntry.fromJson(Map<String, dynamic> json) {
    double number(String key) {
      final value = json[key];
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0;
      return 0;
    }

    return WeightEntry(
      enteredAt:
          DateTime.tryParse(json['enteredAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      weightKg: number('weightKg'),
    );
  }
}
