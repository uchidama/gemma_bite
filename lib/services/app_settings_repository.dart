import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class AppSettingsRepository {
  Future<File> _storageFile() async {
    final directory = await getApplicationDocumentsDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File('${directory.path}/gemma_bite_settings.json');
  }

  Future<ThemeMode> loadThemeMode() async {
    final file = await _storageFile();
    if (!await file.exists()) return ThemeMode.light;

    final text = await file.readAsString();
    if (text.trim().isEmpty) return ThemeMode.light;

    final decoded = jsonDecode(text) as Map<String, dynamic>;
    return decoded['themeMode'] == 'dark' ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> saveThemeMode(ThemeMode themeMode) async {
    final file = await _storageFile();
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    await file.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert({'themeMode': themeMode == ThemeMode.dark ? 'dark' : 'light'}),
    );
  }
}
