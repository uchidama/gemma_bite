import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/meal_models.dart';

class MealRepository {
  Future<File> _storageFile() async {
    final directory = await getApplicationDocumentsDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File('${directory.path}/gemma_bite_meals.json');
  }

  Future<MealLog> load() async {
    final file = await _storageFile();
    if (!await file.exists()) return const MealLog();

    final text = await file.readAsString();
    if (text.trim().isEmpty) return const MealLog();

    final decoded = jsonDecode(text) as Map<String, dynamic>;
    return MealLog.fromJson(decoded);
  }

  Future<void> save(MealLog log) async {
    final file = await _storageFile();
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(log.toJson()),
    );
  }
}

class MealLog {
  const MealLog({
    this.profile = const UserProfile(heightCm: 0, weightKg: 0),
    this.meals = const [],
  });

  final UserProfile profile;
  final List<MealEntry> meals;

  MealLog copyWith({UserProfile? profile, List<MealEntry>? meals}) {
    return MealLog(
      profile: profile ?? this.profile,
      meals: meals ?? this.meals,
    );
  }

  List<MealEntry> mealsForDay(DateTime day) {
    return meals.where((meal) {
      return meal.eatenAt.year == day.year &&
          meal.eatenAt.month == day.month &&
          meal.eatenAt.day == day.day;
    }).toList()..sort((a, b) => b.eatenAt.compareTo(a.eatenAt));
  }

  NutritionTotals totalsForDay(DateTime day) {
    return mealsForDay(day).fold(
      const NutritionTotals.empty(),
      (total, meal) => total + meal.nutrition,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'profile': profile.toJson(),
      'meals': meals.map((meal) => meal.toJson()).toList(),
    };
  }

  factory MealLog.fromJson(Map<String, dynamic> json) {
    return MealLog(
      profile: UserProfile.fromJson(json['profile'] as Map<String, dynamic>?),
      meals:
          (json['meals'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(MealEntry.fromJson)
              .toList()
            ..sort((a, b) => b.eatenAt.compareTo(a.eatenAt)),
    );
  }
}
