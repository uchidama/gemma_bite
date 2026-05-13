import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class AppSettings {
  const AppSettings({this.themeMode = ThemeMode.light, this.ttsVoiceName});

  final ThemeMode themeMode;
  final String? ttsVoiceName;

  Map<String, dynamic> toJson() {
    return {
      'themeMode': themeMode == ThemeMode.dark ? 'dark' : 'light',
      'ttsVoiceName': ttsVoiceName,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final ttsVoiceName = json['ttsVoiceName'] as String?;
    return AppSettings(
      themeMode: json['themeMode'] == 'dark' ? ThemeMode.dark : ThemeMode.light,
      ttsVoiceName: ttsVoiceName?.trim().isEmpty == true ? null : ttsVoiceName,
    );
  }
}

class AppSettingsRepository {
  Future<File> _storageFile() async {
    final directory = await getApplicationDocumentsDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File('${directory.path}/gemma_bite_settings.json');
  }

  Future<AppSettings> load() async {
    final file = await _storageFile();
    if (!await file.exists()) return const AppSettings();

    final text = await file.readAsString();
    if (text.trim().isEmpty) return const AppSettings();

    final decoded = jsonDecode(text) as Map<String, dynamic>;
    return AppSettings.fromJson(decoded);
  }

  Future<ThemeMode> loadThemeMode() async {
    return (await load()).themeMode;
  }

  Future<void> save(AppSettings settings) async {
    final file = await _storageFile();
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
    );
  }

  Future<void> saveThemeMode(ThemeMode themeMode) async {
    final settings = await load();
    await save(
      AppSettings(themeMode: themeMode, ttsVoiceName: settings.ttsVoiceName),
    );
  }

  Future<void> saveTtsVoiceName(String? ttsVoiceName) async {
    final settings = await load();
    await save(
      AppSettings(themeMode: settings.themeMode, ttsVoiceName: ttsVoiceName),
    );
  }
}
