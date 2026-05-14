import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../domain/meal_models.dart';
import '../l10n/app_strings.dart';
import '../services/gemma_service.dart';
import '../services/meal_repository.dart';
import '../services/photo_taken_at_reader.dart';

enum _MainTab { home, eatLog, consult, settings }

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.ttsVoiceName,
    required this.onTtsVoiceNameChanged,
    required this.languageCode,
    required this.onLanguageCodeChanged,
  });

  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode themeMode) onThemeModeChanged;
  final String? ttsVoiceName;
  final Future<void> Function(String? ttsVoiceName) onTtsVoiceNameChanged;
  final String languageCode;
  final Future<void> Function(String languageCode) onLanguageCodeChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _DailyOverview {
  const _DailyOverview({
    required this.mealTitle,
    required this.intakeTitle,
    required this.meals,
    required this.totals,
  });

  final String mealTitle;
  final String intakeTitle;
  final List<MealEntry> meals;
  final NutritionTotals totals;
}

class _WeeklyDaySummary {
  const _WeeklyDaySummary({
    required this.day,
    required this.meals,
    required this.totals,
    required this.caloriesKcal,
  });

  final DateTime day;
  final List<MealEntry> meals;
  final NutritionTotals totals;
  final double caloriesKcal;
}

class _WeeklyOverview {
  const _WeeklyOverview({
    required this.days,
    required this.averageCaloriesKcal,
    required this.photoCount,
  });

  final List<_WeeklyDaySummary> days;
  final double averageCaloriesKcal;
  final int photoCount;
}

class _AiConsultMessage {
  const _AiConsultMessage({
    required this.role,
    required this.text,
    required this.createdAt,
  });

  final String role;
  final String text;
  final DateTime createdAt;
}

class _PendingMealImage {
  const _PendingMealImage({
    required this.file,
    required this.eatenAt,
    required this.fingerprint,
  });

  final File file;
  final DateTime eatenAt;
  final String fingerprint;
}

class _HomeScreenState extends State<HomeScreen> {
  static const _nextMealSuggestionPrompt = '次の食事を提案して';

  final _gemmaService = GemmaService();
  final _imagePicker = ImagePicker();
  final _repository = MealRepository();
  final _photoTakenAtReader = PhotoTakenAtReader();
  final _consultController = TextEditingController();

  bool _isPreparingModel = true;
  bool _isModelLoading = false;
  bool _isLogLoading = true;
  bool _isAnalyzing = false;
  bool _isConsulting = false;
  bool _isLoadingTtsVoices = false;
  bool _isConsultVoiceEnabled = true;
  bool _hasTriedAutoModelLoad = false;
  bool _hasPromptedForProfile = false;
  String? _modelDirectory;
  List<String> _availableModels = [];
  String? _activeModelPath;
  int? _lastAnalyzeLatencyMs;
  List<TtsVoice> _ttsVoices = [];
  List<_PendingMealImage> _pendingImages = [];
  int _analyzeTotalCount = 0;
  int _analyzeCompletedCount = 0;
  MealLog _log = const MealLog();
  List<_AiConsultMessage> _consultMessages = [
    _AiConsultMessage(
      role: 'assistant',
      text: '食事ログをもとに、次の食事やPFCバランスを一緒に考えます。',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    ),
  ];
  String? _selectedMealId;
  String? _error;
  _MainTab _tab = _MainTab.home;

  String _t(String ja) => AppStrings.of(context).t(ja);

  bool get _isJapanese => AppStrings.of(context).isJapanese;

  String _consultPrompt(String ja, String en) => _isJapanese ? ja : en;

  String get _voiceLanguageCode => _isJapanese ? 'ja' : 'en';

  String? get _selectedTtsVoiceName {
    final voiceName = widget.ttsVoiceName;
    if (voiceName == null) return null;
    return _ttsVoices.any((voice) => voice.name == voiceName)
        ? voiceName
        : null;
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.languageCode != widget.languageCode) {
      _loadTtsVoices();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadModelInfo();
    _loadLog();
    _loadTtsVoices();
  }

  Future<void> _loadLog() async {
    try {
      final log = await _repository.load();
      if (!mounted) return;
      setState(() {
        _log = log;
        _isLogLoading = false;
      });
      _maybeShowProfileDialog();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLogLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _saveLog(MealLog log) async {
    if (mounted) setState(() => _log = log);
    await _repository.save(log);
  }

  Future<void> _loadModelInfo() async {
    if (mounted) {
      setState(() {
        _isPreparingModel = true;
        _error = null;
      });
    }
    try {
      final dir = await _gemmaService.getModelDirectory();
      final models = await _gemmaService.listModels();
      if (!mounted) return;

      setState(() {
        _modelDirectory = dir;
        _availableModels = models;
      });

      if (!_gemmaService.isInitialized &&
          !_isModelLoading &&
          !_hasTriedAutoModelLoad &&
          models.isNotEmpty) {
        _hasTriedAutoModelLoad = true;
        await _initializeModel(models.first);
        return;
      }

      if (mounted) setState(() => _isPreparingModel = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPreparingModel = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _initializeModel(String modelPath) async {
    setState(() {
      _isPreparingModel = true;
      _isModelLoading = true;
      _error = null;
    });
    try {
      await _gemmaService.initialize(modelPath);
      if (mounted) {
        setState(() {
          _isPreparingModel = false;
          _isModelLoading = false;
          _activeModelPath = modelPath;
        });
        _maybeShowProfileDialog();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPreparingModel = false;
          _isModelLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  String _displayModelName(String path) => path.split('/').last;

  Future<void> _loadTtsVoices() async {
    if (mounted) setState(() => _isLoadingTtsVoices = true);
    try {
      final voices = await _gemmaService.listTtsVoices(
        languageCode: _voiceLanguageCode,
      );
      if (!mounted) return;
      setState(() {
        _ttsVoices = voices;
        _isLoadingTtsVoices = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingTtsVoices = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedImages = await _pickMealImages(source);
      if (pickedImages.isEmpty || !mounted) return;

      final pendingImages = <_PendingMealImage>[];
      final seenFingerprints = <String>{};
      final duplicateMeals = <MealEntry>[];
      var duplicateSelectionCount = 0;

      for (final picked in pickedImages) {
        final pendingImage = await _pendingMealImageFromXFile(
          picked,
          isCamera: source == ImageSource.camera,
        );
        final duplicateMeal = await _findDuplicateMeal(
          pendingImage.file,
          pendingImage.fingerprint,
        );
        if (duplicateMeal != null) {
          duplicateMeals.add(duplicateMeal);
          continue;
        }
        if (!seenFingerprints.add(pendingImage.fingerprint)) {
          duplicateSelectionCount++;
          continue;
        }
        pendingImages.add(pendingImage);
      }

      if (!mounted) return;
      if (pendingImages.isEmpty) {
        setState(() {
          _pendingImages = [];
          _selectedMealId = duplicateMeals.isEmpty
              ? _selectedMealId
              : duplicateMeals.first.id;
        });
        _showDuplicateSelectionSnackBar(
          duplicateMeals: duplicateMeals,
          duplicateSelectionCount: duplicateSelectionCount,
        );
        return;
      }

      setState(() {
        _pendingImages = pendingImages;
        _analyzeTotalCount = 0;
        _analyzeCompletedCount = 0;
        _error = null;
      });
      if (duplicateMeals.isNotEmpty || duplicateSelectionCount > 0) {
        _showDuplicateSelectionSnackBar(
          duplicateMeals: duplicateMeals,
          duplicateSelectionCount: duplicateSelectionCount,
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _analyzeFood() async {
    if (_pendingImages.isEmpty || !_gemmaService.isInitialized) return;

    final pendingImages = List<_PendingMealImage>.of(_pendingImages);
    setState(() {
      _isAnalyzing = true;
      _analyzeTotalCount = pendingImages.length;
      _analyzeCompletedCount = 0;
      _error = null;
    });

    final stopwatch = Stopwatch()..start();
    final registeredMeals = <MealEntry>[];
    var skippedCount = 0;
    try {
      for (final pendingImage in pendingImages) {
        final duplicateMeal = await _findDuplicateMeal(
          pendingImage.file,
          pendingImage.fingerprint,
        );
        if (duplicateMeal != null) {
          skippedCount++;
          if (mounted) {
            setState(() => _analyzeCompletedCount++);
          }
          continue;
        }

        final response = await _gemmaService.analyzeFood(
          pendingImage.file.path,
        );
        final meal = MealEntry.fromGemmaJson(
          imagePath: pendingImage.file.path,
          imageFingerprint: pendingImage.fingerprint,
          eatenAt: pendingImage.eatenAt,
          response: response,
        );
        final meals = [meal, ..._log.meals]..sort(_sortMeals);
        await _saveLog(_log.copyWith(meals: meals));
        registeredMeals.add(meal);
        if (mounted) {
          setState(() => _analyzeCompletedCount++);
        }
      }
      stopwatch.stop();
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          if (registeredMeals.isNotEmpty) {
            _selectedMealId = registeredMeals.first.id;
          }
          _pendingImages = [];
          _lastAnalyzeLatencyMs = stopwatch.elapsedMilliseconds;
        });
        if (pendingImages.length == 1 && registeredMeals.length == 1) {
          await _openMealDetail(registeredMeals.first);
        } else {
          _showBatchAnalyzeSnackBar(
            registeredCount: registeredMeals.length,
            skippedCount: skippedCount,
          );
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = '分析結果を記録できませんでした: $e');
    } finally {
      if (mounted && _isAnalyzing) setState(() => _isAnalyzing = false);
    }
  }

  Future<void> _replaceMeal(MealEntry updatedMeal) async {
    final meals =
        _log.meals
            .map((meal) => meal.id == updatedMeal.id ? updatedMeal : meal)
            .toList()
          ..sort(_sortMeals);
    await _saveLog(_log.copyWith(meals: meals));
  }

  Future<void> _deleteMeal(MealEntry mealToDelete) async {
    final meals =
        _log.meals.where((meal) => meal.id != mealToDelete.id).toList()
          ..sort(_sortMeals);
    await _saveLog(_log.copyWith(meals: meals));
    if (mounted && _selectedMealId == mealToDelete.id) {
      setState(() => _selectedMealId = null);
    }
  }

  int _sortMeals(MealEntry a, MealEntry b) => b.eatenAt.compareTo(a.eatenAt);

  Future<List<XFile>> _pickMealImages(ImageSource source) async {
    if (source == ImageSource.gallery) {
      return _imagePicker.pickMultiImage(
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85,
      );
    }

    final picked = await _imagePicker.pickImage(
      source: source,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 85,
    );
    return picked == null ? const [] : [picked];
  }

  Future<_PendingMealImage> _pendingMealImageFromXFile(
    XFile picked, {
    required bool isCamera,
  }) async {
    final imageFile = File(picked.path);
    final timestamp = isCamera
        ? DateTime.now()
        : await _photoTakenAtReader.readTakenAt(imageFile.path) ??
              await imageFile.lastModified();
    return _PendingMealImage(
      file: imageFile,
      eatenAt: timestamp,
      fingerprint: await _imageFingerprint(imageFile),
    );
  }

  Future<String> _imageFingerprint(File file) async {
    final bytes = await file.readAsBytes();
    var hashA = 0x811c9dc5;
    var hashB = 0x01000193;
    for (final byte in bytes) {
      hashA = ((hashA ^ byte) * 0x01000193) & 0xffffffff;
      hashB = ((hashB + byte) * 0x811c9dc5) & 0xffffffff;
    }
    final hexA = hashA.toRadixString(16).padLeft(8, '0');
    final hexB = hashB.toRadixString(16).padLeft(8, '0');
    return '${bytes.length}:$hexA$hexB';
  }

  Future<MealEntry?> _findDuplicateMeal(
    File imageFile,
    String imageFingerprint,
  ) async {
    for (final meal in _log.meals) {
      final storedFingerprint = meal.imageFingerprint;
      if (storedFingerprint != null && storedFingerprint == imageFingerprint) {
        return meal;
      }

      if (meal.imagePath == imageFile.path) return meal;

      final storedFile = File(meal.imagePath);
      if (!await storedFile.exists()) continue;
      try {
        if (await _imageFingerprint(storedFile) == imageFingerprint) {
          return meal;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  void _showDuplicateSelectionSnackBar({
    required List<MealEntry> duplicateMeals,
    required int duplicateSelectionCount,
  }) {
    final duplicateCount = duplicateMeals.length + duplicateSelectionCount;
    if (duplicateCount == 0) return;

    final firstMeal = duplicateMeals.isEmpty ? null : duplicateMeals.first;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('重複している写真 $duplicateCount枚をスキップしました。'),
        action: firstMeal == null
            ? null
            : SnackBarAction(
                label: '開く',
                onPressed: () => _openMealDetail(firstMeal),
              ),
      ),
    );
  }

  void _showBatchAnalyzeSnackBar({
    required int registeredCount,
    required int skippedCount,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('分析完了: $registeredCount枚を登録、$skippedCount枚をスキップしました。'),
      ),
    );
  }

  void _maybeShowProfileDialog() {
    if (_hasPromptedForProfile ||
        _isLogLoading ||
        !_gemmaService.isInitialized ||
        _log.profile.isComplete) {
      return;
    }

    _hasPromptedForProfile = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showProfileDialog();
    });
  }

  @override
  void dispose() {
    _consultController.dispose();
    _gemmaService.stopSpeaking();
    _gemmaService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dailyOverview = _dailyOverview();
    final weeklyOverview = _weeklyOverview();

    if (!_gemmaService.isInitialized) {
      return _buildModelPreparationScreen();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(switch (_tab) {
          _MainTab.home => 'Gemma Bite',
          _MainTab.eatLog => _t('イートログ'),
          _MainTab.consult => _t('AI相談'),
          _MainTab.settings => _t('設定'),
        }),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            tooltip: _t('身体情報'),
            onPressed: _showProfileDialog,
          ),
          if (_gemmaService.isInitialized)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: _t('モデルをリセット'),
              onPressed: () async {
                await _gemmaService.dispose();
                setState(() {
                  _pendingImages = [];
                  _analyzeTotalCount = 0;
                  _analyzeCompletedCount = 0;
                  _hasTriedAutoModelLoad = false;
                  _activeModelPath = null;
                });
                _loadModelInfo();
              },
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab.index,
        onDestinationSelected: (index) {
          setState(() => _tab = _MainTab.values[index]);
        },
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home), label: _t('ホーム')),
          NavigationDestination(
            icon: const Icon(Icons.insights),
            label: _t('イートログ'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble),
            label: _t('AI相談'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings),
            label: _t('設定'),
          ),
        ],
      ),
      body: _isLogLoading
          ? const Center(child: CircularProgressIndicator())
          : switch (_tab) {
              _MainTab.home => _buildHomeTab(dailyOverview, weeklyOverview),
              _MainTab.eatLog => _EatLogContent(
                overview: weeklyOverview,
                gemmaService: _gemmaService,
                onMealUpdated: _replaceMeal,
                onMealDeleted: _deleteMeal,
              ),
              _MainTab.consult => _buildConsultTab(dailyOverview),
              _MainTab.settings => _buildSettingsTab(),
            },
    );
  }

  Widget _buildHomeTab(
    _DailyOverview dailyOverview,
    _WeeklyOverview weeklyOverview,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildImageSection(),
          const SizedBox(height: 12),
          _buildActionButtons(),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _isConsulting
                ? null
                : () => _openConsultWithPrompt(
                    _consultPrompt(
                      _nextMealSuggestionPrompt,
                      'Suggest my next meal',
                    ),
                  ),
            icon: const Icon(Icons.restaurant_menu, size: 18),
            label: Text(_t('次の食事を相談')),
          ),
          if (_isAnalyzing) ...[
            const SizedBox(height: 12),
            _buildLoadingIndicator(),
          ],
          const SizedBox(height: 16),
          _buildMealTimeline(
            dailyOverview.meals,
            title: dailyOverview.mealTitle,
          ),
          const SizedBox(height: 12),
          _buildDailySummary(dailyOverview),
          const SizedBox(height: 12),
          _buildWeeklySummary(weeklyOverview),
          if (_error != null) ...[const SizedBox(height: 12), _buildError()],
        ],
      ),
    );
  }

  Widget _buildConsultTab(_DailyOverview dailyOverview) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                _t('食事ログから相談'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _t('今日の摂取量や直近の食事をもとに、次の食事を相談できます。'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilterChip(
                  avatar: Icon(
                    _isConsultVoiceEnabled ? Icons.volume_up : Icons.volume_off,
                    size: 18,
                  ),
                  label: Text(
                    _isConsultVoiceEnabled ? _t('音声ON') : _t('音声OFF'),
                  ),
                  selected: _isConsultVoiceEnabled,
                  onSelected: (enabled) async {
                    setState(() => _isConsultVoiceEnabled = enabled);
                    if (!enabled) await _gemmaService.stopSpeaking();
                  },
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.restaurant_menu, size: 18),
                    label: Text(_t('次の食事を提案')),
                    onPressed: _isConsulting
                        ? null
                        : () => _sendConsultMessage(
                            _consultPrompt(
                              _nextMealSuggestionPrompt,
                              'Suggest my next meal',
                            ),
                          ),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.balance, size: 18),
                    label: Text(_t('今日の不足を確認')),
                    onPressed: _isConsulting
                        ? null
                        : () => _sendConsultMessage(
                            _consultPrompt(
                              '今日の食事ログから不足していそうな栄養と、次に補うなら何がよいか教えて',
                              'Based on today\'s meal log, what nutrients may be missing and what should I add next?',
                            ),
                          ),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.stacked_bar_chart, size: 18),
                    label: Text(_t('PFCを整えたい')),
                    onPressed: _isConsulting
                        ? null
                        : () => _sendConsultMessage(
                            _consultPrompt(
                              'PFCバランスを整える次の食事を提案して',
                              'Suggest a next meal that balances protein, fat, and carbs.',
                            ),
                          ),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.light_mode, size: 18),
                    label: Text(_t('軽めにしたい')),
                    onPressed: _isConsulting
                        ? null
                        : () => _sendConsultMessage(
                            _consultPrompt(
                              '次の食事は軽めにしたい。食事ログを見ておすすめを提案して',
                              'I want a lighter next meal. Please suggest one based on my meal log.',
                            ),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ..._consultMessages.map(_buildConsultMessageBubble),
              if (_isConsulting) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
              ],
              if (dailyOverview.meals.isEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _t('食事ログが増えるほど、提案は具体的になります。'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _consultController,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _isConsulting ? null : _sendConsultMessage,
                    decoration: InputDecoration(
                      hintText: _t('例: コンビニで買える夕食を提案して'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _isConsulting
                      ? null
                      : () => _sendConsultMessage(_consultController.text),
                  icon: const Icon(Icons.send),
                  tooltip: _t('送信'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConsultMessageBubble(_AiConsultMessage message) {
    final isUser = message.role == 'user';
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: isUser
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t(message.text),
              style: TextStyle(
                color: isUser
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            if (!isUser) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.volume_up, size: 18),
                  tooltip: _t('読み上げ'),
                  onPressed: () => _speakConsultText(message.text),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openConsultWithPrompt(String prompt) async {
    setState(() => _tab = _MainTab.consult);
    await _sendConsultMessage(prompt);
  }

  Future<void> _speakConsultText(String text) async {
    try {
      await _gemmaService.speakText(
        text,
        voiceName: _selectedTtsVoiceName,
        languageCode: _voiceLanguageCode,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('音声読み上げに失敗しました: $e')));
    }
  }

  Future<void> _sendConsultMessage(String text) async {
    final prompt = text.trim();
    if (prompt.isEmpty || _isConsulting) return;
    _consultController.clear();
    final userMessage = _AiConsultMessage(
      role: 'user',
      text: prompt,
      createdAt: DateTime.now(),
    );
    setState(() {
      _isConsulting = true;
      _consultMessages = [..._consultMessages, userMessage];
    });

    try {
      final response = await _gemmaService.consultMeal(
        mealLogContext: _buildMealLogContext(),
        userMessage: prompt,
        responseLanguage: _isJapanese ? 'ja' : 'en',
      );
      if (!mounted) return;
      final replyText = response.trim().isEmpty
          ? _t('提案を生成できませんでした。')
          : response.trim();
      setState(() {
        _consultMessages = [
          ..._consultMessages,
          _AiConsultMessage(
            role: 'assistant',
            text: replyText,
            createdAt: DateTime.now(),
          ),
        ];
      });
      if (_isConsultVoiceEnabled) await _speakConsultText(replyText);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _consultMessages = [
          ..._consultMessages,
          _AiConsultMessage(
            role: 'assistant',
            text: '相談に失敗しました: $e',
            createdAt: DateTime.now(),
          ),
        ];
      });
    } finally {
      if (mounted) setState(() => _isConsulting = false);
    }
  }

  String _buildMealLogContext() {
    final now = DateTime.now();
    final todayMeals = _log.mealsForDay(now);
    final todayTotals = todayMeals.fold(
      const NutritionTotals.empty(),
      (total, meal) => total + meal.nutrition,
    );
    final recentMeals = _log.meals.take(12).map((meal) {
      return {
        'eatenAt': meal.eatenAt.toIso8601String(),
        'foodName': meal.foodName,
        'summary': meal.summary,
        'nutrition': meal.nutrition.toJson(),
      };
    }).toList();
    final profile = _log.profile;
    return const JsonEncoder.withIndent('  ').convert({
      'now': now.toIso8601String(),
      'profile': profile.toJson(),
      'today': {'mealCount': todayMeals.length, 'totals': todayTotals.toJson()},
      'recentMeals': recentMeals,
      'instruction': _isJapanese
          ? '次の食事提案では、今日の摂取量、直近の食事、PFCバランスを考慮してください。一般的な食事提案として、メニュー案、理由、調整ポイントを簡潔に返してください。'
          : 'For next-meal suggestions, consider today\'s intake, recent meals, and PFC balance. Reply concisely with menu ideas, reasons, and adjustment points as general food guidance.',
    });
  }

  Widget _buildSettingsTab() {
    final isDark = widget.themeMode == ThemeMode.dark;
    final selectedVoiceName = _selectedTtsVoiceName;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SwitchListTile(
              secondary: const Icon(Icons.dark_mode),
              title: Text(_t('ダークモード')),
              subtitle: Text(_t('黒ベースのUIテーマに切り替えます')),
              value: isDark,
              onChanged: (enabled) {
                widget.onThemeModeChanged(
                  enabled ? ThemeMode.dark : ThemeMode.light,
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ListTile(
              leading: const Icon(Icons.language),
              title: Text(_t('言語')),
              subtitle: Text(_t('端末設定に従います')),
              trailing: DropdownButton<String>(
                value: widget.languageCode,
                items: [
                  DropdownMenuItem(value: 'system', child: Text(_t('システム設定'))),
                  DropdownMenuItem(value: 'ja', child: Text(_t('日本語'))),
                  const DropdownMenuItem(value: 'en', child: Text('English')),
                ],
                onChanged: (value) async {
                  if (value == null) return;
                  await widget.onLanguageCodeChanged(value);
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.record_voice_over),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _t('読み上げ音声'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: _t('音声一覧を更新'),
                      onPressed: _isLoadingTtsVoices ? null : _loadTtsVoices,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_isLoadingTtsVoices)
                  const LinearProgressIndicator()
                else
                  DropdownButtonFormField<String?>(
                    initialValue: selectedVoiceName,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(_t('端末のデフォルト音声')),
                      ),
                      ..._ttsVoices.map(
                        (voice) => DropdownMenuItem<String?>(
                          value: voice.name,
                          child: Text(
                            voice.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (voiceName) async {
                      await widget.onTtsVoiceNameChanged(voiceName);
                    },
                  ),
                const SizedBox(height: 8),
                Text(
                  _ttsVoices.isEmpty
                      ? _t('端末に追加の音声が見つからない場合は、Androidの音声合成設定から追加できます。')
                      : _t(
                          '通信が必要な音声は表示せず、現在の表示言語で端末内にある音声だけを表示します。性別情報は端末側で標準化されていません。',
                        ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _speakConsultText(_t('こんにちは。Gemma Biteの読み上げ音声テストです。')),
                    icon: const Icon(Icons.volume_up, size: 18),
                    label: Text(_t('試聴')),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildInferenceStatusCard(),
      ],
    );
  }

  Widget _buildModelPreparationScreen() {
    final isSearching = _isPreparingModel && !_isModelLoading;
    final isWaiting = isSearching || _isModelLoading;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.restaurant,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Gemma Bite',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 28),
                  if (isWaiting) ...[
                    const Center(child: CircularProgressIndicator()),
                    const SizedBox(height: 20),
                    Text(
                      isSearching ? _t('モデルを確認しています') : _t('モデルを読み込んでいます'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(_t('初回読み込みには時間がかかります。'), textAlign: TextAlign.center),
                  ] else if (_availableModels.isEmpty) ...[
                    Text(
                      _t('モデルファイルが見つかりません'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _t('モデルファイル (.litertlm) を配置してください:'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      _modelDirectory ?? _t('読み込み中...'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _loadModelInfo,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(_t('モデルを再検索')),
                    ),
                  ] else ...[
                    Text(
                      _t('読み込むモデルを選択してください'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    ..._availableModels.map((model) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: ElevatedButton.icon(
                          onPressed: () => _initializeModel(model),
                          icon: const Icon(Icons.play_arrow),
                          label: Text(
                            _displayModelName(model),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                    }),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _buildError(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  _DailyOverview _dailyOverview() {
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    final todayMeals = _log.mealsForDay(today);
    final yesterdayMeals = _log.mealsForDay(yesterday);
    final usesYesterday = todayMeals.isEmpty && yesterdayMeals.isNotEmpty;
    final meals = usesYesterday ? yesterdayMeals : todayMeals;
    final totals = meals.fold(
      const NutritionTotals.empty(),
      (total, meal) => total + meal.nutrition,
    );

    return _DailyOverview(
      mealTitle: usesYesterday ? _t('昨日の食事の記録') : _t('今日の食事の記録'),
      intakeTitle: usesYesterday ? _t('昨日の摂取量') : _t('今日の摂取量'),
      meals: meals,
      totals: totals,
    );
  }

  _WeeklyOverview _weeklyOverview() {
    final today = DateTime.now();
    final days = List.generate(7, (index) {
      final day = today.subtract(Duration(days: index));
      final meals = _log.mealsForDay(day);
      final calories = meals.fold<double>(
        0,
        (total, meal) => total + meal.nutrition.caloriesKcal,
      );
      final totals = meals.fold(
        const NutritionTotals.empty(),
        (total, meal) => total + meal.nutrition,
      );
      return _WeeklyDaySummary(
        day: day,
        meals: meals,
        totals: totals,
        caloriesKcal: calories,
      );
    });
    final totalCalories = days.fold<double>(
      0,
      (total, day) => total + day.caloriesKcal,
    );
    final photoCount = days.fold<int>(
      0,
      (total, day) => total + day.meals.length,
    );

    return _WeeklyOverview(
      days: days,
      averageCaloriesKcal: totalCalories / days.length,
      photoCount: photoCount,
    );
  }

  Widget _buildDailySummary(_DailyOverview overview) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                overview.intakeTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            _summaryValueRow(
              label: _t('写真登録数'),
              valueText: _formatPhotoCount(overview.meals.length),
              icon: Icons.photo_camera,
              color: Colors.blue[600]!,
            ),
            _summaryRow(
              label: _t('総カロリー'),
              value: overview.totals.caloriesKcal,
              unit: 'kcal',
              icon: Icons.bolt,
              color: Colors.amber[700]!,
            ),
            _summaryRow(
              label: _t('タンパク質'),
              value: overview.totals.proteinG,
              unit: 'g',
              icon: Icons.fitness_center,
              color: Colors.green[700]!,
            ),
            _summaryRow(
              label: _t('脂質'),
              value: overview.totals.fatG,
              unit: 'g',
              icon: Icons.water_drop,
              color: Colors.teal[700]!,
            ),
            _summaryRow(
              label: _t('炭水化物'),
              value: overview.totals.carbohydrateG,
              unit: 'g',
              icon: Icons.rice_bowl,
              color: Colors.lightGreen[700]!,
            ),
            _summaryRow(
              label: _t('塩分'),
              value: overview.totals.saltG,
              unit: 'g',
              icon: Icons.grain,
              color: Colors.blueGrey[600]!,
            ),
            _summaryRow(
              label: _t('カフェイン'),
              value: overview.totals.caffeineMg,
              unit: 'mg',
              icon: Icons.coffee,
              color: Colors.brown[600]!,
            ),
            _summaryRow(
              label: _t('アルコール'),
              value: overview.totals.alcoholG,
              unit: 'g',
              icon: Icons.local_bar,
              color: Colors.deepPurple[400]!,
              showDivider: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklySummary(_WeeklyOverview overview) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openEatLog(overview),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _t('過去7日間'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _summaryValueRow(
                label: _t('摂取カロリーの1日平均'),
                valueText: '${overview.averageCaloriesKcal.round()}kcal',
                icon: Icons.timeline,
                color: Colors.orange[700]!,
              ),
              _summaryValueRow(
                label: _t('写真投稿数'),
                valueText: _formatPhotoCount(overview.photoCount),
                icon: Icons.photo_library,
                color: Colors.blue[600]!,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  _t('各日の摂取カロリー'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              ...overview.days.map((day) {
                final isLast = day == overview.days.last;
                return _summaryValueRow(
                  label: _formatDayLabel(day.day),
                  valueText: '${day.caloriesKcal.round()}kcal',
                  icon: Icons.calendar_today,
                  color: Theme.of(context).colorScheme.primary,
                  showDivider: !isLast,
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryRow({
    required String label,
    required double value,
    required String unit,
    required IconData icon,
    required Color color,
    bool showDivider = true,
  }) {
    final formatted = value >= 100
        ? value.round().toString()
        : value.toStringAsFixed(1);

    return _summaryValueRow(
      label: label,
      valueText: '$formatted$unit',
      icon: icon,
      color: color,
      showDivider: showDivider,
    );
  }

  Widget _summaryValueRow({
    required String label,
    required String valueText,
    required IconData icon,
    required Color color,
    bool showDivider = true,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                valueText,
                textAlign: TextAlign.right,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 56,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
      ],
    );
  }

  Widget _buildImageSection() {
    final colorScheme = Theme.of(context).colorScheme;
    final pendingImages = _pendingImages;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: pendingImages.isNotEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.file(
                  pendingImages.first.file,
                  height: 230,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          pendingImages.length == 1
                              ? '${AppStrings.of(context).isJapanese ? '食事時刻' : 'Meal time'}: ${_formatDateTime(pendingImages.first.eatenAt)}'
                              : AppStrings.of(context).isJapanese
                              ? '${pendingImages.length}枚を選択中'
                              : '${pendingImages.length} photos selected',
                        ),
                      ),
                      if (pendingImages.length > 1)
                        Text(
                          '${AppStrings.of(context).isJapanese ? '先頭' : 'First'}: ${_formatDateTime(pendingImages.first.eatenAt)}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                if (pendingImages.length > 1)
                  SizedBox(
                    height: 72,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (context, index) {
                        final pendingImage = pendingImages[index];
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.file(
                            pendingImage.file,
                            width: 72,
                            height: 60,
                            fit: BoxFit.cover,
                          ),
                        );
                      },
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 8),
                      itemCount: pendingImages.length,
                    ),
                  ),
              ],
            )
          : Container(
              height: 180,
              color: colorScheme.surfaceContainerHighest,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.restaurant,
                      size: 44,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _t('食事の写真を撮影・選択してください'),
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isAnalyzing
                ? null
                : () => _pickImage(ImageSource.camera),
            icon: const Icon(Icons.camera_alt, size: 18),
            label: Text(_t('撮影')),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isAnalyzing
                ? null
                : () => _pickImage(ImageSource.gallery),
            icon: const Icon(Icons.photo_library, size: 18),
            label: Text(_t('選択')),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed:
                (_pendingImages.isNotEmpty &&
                    !_isAnalyzing &&
                    _gemmaService.isInitialized)
                ? _analyzeFood
                : null,
            icon: const Icon(Icons.analytics, size: 18),
            label: Text(_t('分析')),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingIndicator() {
    final progressText = _analyzeTotalCount <= 1
        ? (AppStrings.of(context).isJapanese
              ? 'Gemma が食事を分析中...'
              : 'Gemma is analyzing meals...')
        : (AppStrings.of(context).isJapanese
              ? 'Gemma が食事を分析中... $_analyzeCompletedCount / $_analyzeTotalCount'
              : 'Gemma is analyzing meals... $_analyzeCompletedCount / $_analyzeTotalCount');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(progressText),
          ],
        ),
      ),
    );
  }

  Widget _buildInferenceStatusCard() {
    final modelPath = _activeModelPath;
    final modelName = modelPath == null
        ? _t('未選択')
        : _displayModelName(modelPath);
    final modeLabel = _t('投機デコードON');
    final latency = _lastAnalyzeLatencyMs;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              avatar: const Icon(Icons.memory, size: 18),
              label: Text(
                AppStrings.of(context).isJapanese
                    ? 'モデル: $modelName'
                    : 'Model: $modelName',
              ),
            ),
            Chip(
              avatar: const Icon(Icons.speed, size: 18),
              label: Text(
                AppStrings.of(context).isJapanese
                    ? 'デコード: $modeLabel'
                    : 'Decode: $modeLabel',
              ),
            ),
            if (latency != null)
              Chip(
                avatar: const Icon(Icons.timer, size: 18),
                label: Text(
                  AppStrings.of(context).isJapanese
                      ? '直近分析: ${(latency / 1000).toStringAsFixed(2)}秒'
                      : 'Last analysis: ${(latency / 1000).toStringAsFixed(2)}s',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMealTimeline(List<MealEntry> meals, {required String title}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (meals.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text(_t('まだ食事記録がありません'))),
              )
            else
              ...meals.map((meal) {
                final selected = meal.id == _selectedMealId;
                return ListTile(
                  selected: selected,
                  contentPadding: EdgeInsets.zero,
                  leading: _mealThumbnail(meal),
                  title: Text(meal.foodName),
                  subtitle: Text(
                    '${_formatDateTime(meal.eatenAt)}  ${meal.nutrition.caloriesKcal.round()}kcal',
                  ),
                  trailing: meal.needsClarification
                      ? const Icon(Icons.help_outline, color: Colors.orange)
                      : const Icon(
                          Icons.check_circle_outline,
                          color: Colors.green,
                        ),
                  onTap: () => _openMealDetail(meal),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _mealThumbnail(MealEntry meal) {
    final file = File(meal.imagePath);
    if (!file.existsSync()) {
      return const CircleAvatar(child: Icon(Icons.restaurant));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.file(file, width: 48, height: 48, fit: BoxFit.cover),
    );
  }

  Future<void> _openMealDetail(MealEntry meal) async {
    setState(() => _selectedMealId = meal.id);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MealDetailScreen(
          meal: meal,
          gemmaService: _gemmaService,
          onMealUpdated: _replaceMeal,
          onMealDeleted: _deleteMeal,
        ),
      ),
    );
  }

  void _openEatLog(_WeeklyOverview overview) {
    setState(() => _tab = _MainTab.eatLog);
  }

  Future<void> _openWeightHistory(List<WeightEntry> history) async {
    if (history.length < 2) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => WeightHistoryScreen(entries: history),
      ),
    );
  }

  Future<void> _showProfileDialog() async {
    if (!mounted) return;
    final profile = await showDialog<UserProfile>(
      context: context,
      builder: (context) => _ProfileDialog(
        initialProfile: _log.profile,
        onOpenWeightHistory: _openWeightHistory,
      ),
    );
    if (!mounted || profile == null) return;

    try {
      await _saveLog(_log.copyWith(profile: profile));
    } catch (e) {
      if (mounted) setState(() => _error = '身体情報を保存できませんでした: $e');
    }
  }

  Widget _buildError() {
    return Card(
      color: Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _error ?? '',
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => _error = null),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return _t('未取得');
    String two(int value) => value.toString().padLeft(2, '0');
    return '${dateTime.year}/${two(dateTime.month)}/${two(dateTime.day)} ${two(dateTime.hour)}:${two(dateTime.minute)}';
  }

  String _formatPhotoCount(int count) {
    return AppStrings.of(context).isJapanese ? '$count枚' : '$count photos';
  }

  String _formatDayLabel(DateTime dateTime) {
    if (!AppStrings.of(context).isJapanese) {
      return '${dateTime.month}/${dateTime.day}';
    }
    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
    final weekday = weekdays[dateTime.weekday - 1];
    return '${dateTime.month}/${dateTime.day} ($weekday)';
  }
}

enum _EatLogMetric {
  calories('カロリー', 'kcal', Colors.amber, Icons.bolt),
  protein('タンパク質', 'g', Colors.green, Icons.fitness_center),
  fat('脂質', 'g', Colors.teal, Icons.water_drop),
  carbohydrate('炭水化物', 'g', Colors.lightGreen, Icons.rice_bowl),
  pfcBalance('PFCバランス', '%', Colors.deepOrange, Icons.stacked_bar_chart);

  const _EatLogMetric(this.label, this.unit, this.color, this.icon);

  final String label;
  final String unit;
  final MaterialColor color;
  final IconData icon;

  double valueFor(_WeeklyDaySummary day) {
    return switch (this) {
      _EatLogMetric.calories => day.caloriesKcal,
      _EatLogMetric.protein => day.totals.proteinG,
      _EatLogMetric.fat => day.totals.fatG,
      _EatLogMetric.carbohydrate => day.totals.carbohydrateG,
      _EatLogMetric.pfcBalance => 0,
    };
  }
}

class _EatLogContent extends StatefulWidget {
  const _EatLogContent({
    required this.overview,
    this.gemmaService,
    this.onMealUpdated,
    this.onMealDeleted,
  });

  final _WeeklyOverview overview;
  final GemmaService? gemmaService;
  final Future<void> Function(MealEntry meal)? onMealUpdated;
  final Future<void> Function(MealEntry meal)? onMealDeleted;

  @override
  State<_EatLogContent> createState() => _EatLogContentState();
}

class _EatLogContentState extends State<_EatLogContent> {
  _EatLogMetric _metric = _EatLogMetric.calories;

  String _t(String ja) => AppStrings.of(context).t(ja);

  String _metricLabel(_EatLogMetric metric) => _t(metric.label);

  String _formatPhotoCount(int count) {
    return AppStrings.of(context).isJapanese ? '$count枚' : '$count photos';
  }

  @override
  Widget build(BuildContext context) {
    final chronologicalDays = widget.overview.days.reversed.toList();
    final meals = widget.overview.days.expand((day) => day.meals).toList()
      ..sort((a, b) => b.eatenAt.compareTo(a.eatenAt));
    final total = _metric == _EatLogMetric.pfcBalance
        ? 0.0
        : widget.overview.days.fold<double>(
            0,
            (total, day) => total + _metric.valueFor(day),
          );
    final average = total / widget.overview.days.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _t('過去7日間'),
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _metricSelector(),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _formatRange(chronologicalDays),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _metric == _EatLogMetric.pfcBalance
                        ? _t('PFCバランスの推移')
                        : AppStrings.of(context).isJapanese
                        ? '${_metricLabel(_metric)}の推移'
                        : '${_metricLabel(_metric)} Trend',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_metric == _EatLogMetric.pfcBalance) ...[
                    const SizedBox(height: 4),
                    Text(
                      _t('P/F/Cの摂取エネルギー比'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _pfcLegend(context),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 220,
                    child: CustomPaint(
                      painter: _metric == _EatLogMetric.pfcBalance
                          ? _PfcBalanceChartPainter(
                              days: chronologicalDays,
                              proteinColor: Colors.green[600]!,
                              fatColor: Colors.teal[500]!,
                              carbohydrateColor: Colors.lightGreen[600]!,
                              emptyColor: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              gridColor: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                              labelColor: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            )
                          : _WeeklyNutritionChartPainter(
                              days: chronologicalDays,
                              metric: _metric,
                              gridColor: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                              barColor: _metric.color[700]!,
                              labelColor: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _metricSummary(chronologicalDays, total, average),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      _t('写真投稿数'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _eatLogValueRow(
                    label: _t('過去7日間'),
                    valueText: _formatPhotoCount(widget.overview.photoCount),
                    icon: Icons.photo_library,
                    color: Colors.blue[600]!,
                    showDivider: false,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildEatLogTimeline(context, meals),
        ],
      ),
    );
  }

  Widget _metricSummary(
    List<_WeeklyDaySummary> days,
    double total,
    double average,
  ) {
    if (_metric != _EatLogMetric.pfcBalance) {
      return Row(
        children: [
          Expanded(
            child: _metricTotal(
              label: _t('合計'),
              value: _formatMetricValue(total),
              icon: Icons.functions,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _metricTotal(
              label: _t('一日の平均'),
              value: _formatMetricValue(average),
              icon: Icons.timeline,
            ),
          ),
        ],
      );
    }

    final balance = _PfcBalance.fromTotals(
      days.fold(
        const NutritionTotals.empty(),
        (total, day) => total + day.totals,
      ),
    );
    return Row(
      children: [
        Expanded(
          child: _pfcSummaryCard('P', balance.proteinRatio, Colors.green),
        ),
        const SizedBox(width: 8),
        Expanded(child: _pfcSummaryCard('F', balance.fatRatio, Colors.teal)),
        const SizedBox(width: 8),
        Expanded(
          child: _pfcSummaryCard(
            'C',
            balance.carbohydrateRatio,
            Colors.lightGreen,
          ),
        ),
      ],
    );
  }

  Widget _pfcSummaryCard(String label, double ratio, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, color: color[600], size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                Text(
                  '${(ratio * 100).round()}%',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pfcLegend(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        _PfcLegendItem(label: _t('P タンパク質'), color: Colors.green),
        _PfcLegendItem(label: _t('F 脂質'), color: Colors.teal),
        _PfcLegendItem(label: _t('C 炭水化物'), color: Colors.lightGreen),
      ],
    );
  }

  Widget _eatLogValueRow({
    required String label,
    required String valueText,
    required IconData icon,
    required Color color,
    bool showDivider = true,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                valueText,
                textAlign: TextAlign.right,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 56,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
      ],
    );
  }

  Widget _metricSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _EatLogMetric.values.map((metric) {
          final selected = metric == _metric;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: selected,
              avatar: Icon(
                metric.icon,
                size: 18,
                color: selected ? metric.color[900] : metric.color[700],
              ),
              label: Text(_metricLabel(metric)),
              onSelected: (_) => setState(() => _metric = metric),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _metricTotal({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: _metric.color[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEatLogTimeline(BuildContext context, List<MealEntry> meals) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.of(context).t('イートログ'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (meals.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(AppStrings.of(context).t('この期間の食事記録はありません')),
                ),
              )
            else
              ...meals.map((meal) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _mealThumbnail(meal),
                  title: Text(meal.foodName),
                  subtitle: Text(
                    '${_formatDateTime(meal.eatenAt)}  ${meal.nutrition.caloriesKcal.round()}kcal',
                  ),
                  trailing: meal.needsClarification
                      ? const Icon(Icons.help_outline, color: Colors.orange)
                      : const Icon(
                          Icons.check_circle_outline,
                          color: Colors.green,
                        ),
                  onTap: widget.gemmaService == null
                      ? null
                      : () => _openMealDetail(meal),
                );
              }),
          ],
        ),
      ),
    );
  }

  Future<void> _openMealDetail(MealEntry meal) async {
    final gemmaService = widget.gemmaService;
    final onMealUpdated = widget.onMealUpdated;
    final onMealDeleted = widget.onMealDeleted;
    if (gemmaService == null ||
        onMealUpdated == null ||
        onMealDeleted == null) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MealDetailScreen(
          meal: meal,
          gemmaService: gemmaService,
          onMealUpdated: onMealUpdated,
          onMealDeleted: onMealDeleted,
        ),
      ),
    );
  }

  Widget _mealThumbnail(MealEntry meal) {
    final file = File(meal.imagePath);
    if (!file.existsSync()) {
      return const CircleAvatar(child: Icon(Icons.restaurant));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.file(file, width: 48, height: 48, fit: BoxFit.cover),
    );
  }

  String _formatMetricValue(double value) {
    final formatted = _metric == _EatLogMetric.calories
        ? value.round().toString()
        : value.toStringAsFixed(1);
    return '$formatted${_metric.unit}';
  }

  String _formatRange(List<_WeeklyDaySummary> days) {
    if (days.isEmpty) return '';
    final start = days.first.day;
    final end = days.last.day;
    if (!AppStrings.of(context).isJapanese) {
      return '${start.month}/${start.day} - ${end.month}/${end.day}';
    }
    return '${start.month}月${start.day}日〜${end.day}日';
  }

  static String _formatDateTime(DateTime dateTime) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${dateTime.year}/${two(dateTime.month)}/${two(dateTime.day)} ${two(dateTime.hour)}:${two(dateTime.minute)}';
  }
}

class _PfcLegendItem extends StatelessWidget {
  const _PfcLegendItem({required this.label, required this.color});

  final String label;
  final MaterialColor color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color[600], shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _PfcBalance {
  const _PfcBalance({
    required this.proteinRatio,
    required this.fatRatio,
    required this.carbohydrateRatio,
  });

  final double proteinRatio;
  final double fatRatio;
  final double carbohydrateRatio;

  bool get hasData => proteinRatio + fatRatio + carbohydrateRatio > 0;

  factory _PfcBalance.fromTotals(NutritionTotals totals) {
    final proteinKcal = totals.proteinG * 4;
    final fatKcal = totals.fatG * 9;
    final carbohydrateKcal = totals.carbohydrateG * 4;
    final total = proteinKcal + fatKcal + carbohydrateKcal;
    if (total <= 0) {
      return const _PfcBalance(
        proteinRatio: 0,
        fatRatio: 0,
        carbohydrateRatio: 0,
      );
    }

    return _PfcBalance(
      proteinRatio: proteinKcal / total,
      fatRatio: fatKcal / total,
      carbohydrateRatio: carbohydrateKcal / total,
    );
  }
}

class _PfcBalanceChartPainter extends CustomPainter {
  const _PfcBalanceChartPainter({
    required this.days,
    required this.proteinColor,
    required this.fatColor,
    required this.carbohydrateColor,
    required this.emptyColor,
    required this.gridColor,
    required this.labelColor,
  });

  final List<_WeeklyDaySummary> days;
  final Color proteinColor;
  final Color fatColor;
  final Color carbohydrateColor;
  final Color emptyColor;
  final Color gridColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;

    const left = 34.0;
    const right = 10.0;
    const top = 8.0;
    const bottom = 42.0;
    const barWidth = 18.0;
    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final labelPainter = TextPainter(textDirection: TextDirection.ltr);

    for (var i = 0; i <= 4; i++) {
      final y = top + chartHeight * i / 4;
      canvas.drawLine(
        Offset(left, y),
        Offset(size.width - right, y),
        gridPaint,
      );
      final value = 100 - i * 25;
      labelPainter.text = TextSpan(
        text: '$value%',
        style: TextStyle(color: labelColor, fontSize: 11),
      );
      labelPainter.layout();
      labelPainter.paint(canvas, Offset(0, y - labelPainter.height / 2));
    }

    final step = days.length == 1 ? chartWidth : chartWidth / (days.length - 1);
    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      final balance = _PfcBalance.fromTotals(day.totals);
      final x = left + step * i;
      final baseY = top + chartHeight;
      final leftX = x - barWidth / 2;

      if (!balance.hasData) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(leftX, top, barWidth, chartHeight),
            const Radius.circular(5),
          ),
          Paint()
            ..color = emptyColor
            ..style = PaintingStyle.fill,
        );
      } else {
        var currentBottom = baseY;
        void drawSegment(double ratio, Color color) {
          if (ratio <= 0) return;
          final height = chartHeight * ratio;
          final rect = Rect.fromLTWH(
            leftX,
            currentBottom - height,
            barWidth,
            height,
          );
          canvas.drawRect(
            rect,
            Paint()
              ..color = color
              ..style = PaintingStyle.fill,
          );
          currentBottom -= height;
        }

        drawSegment(balance.proteinRatio, proteinColor);
        drawSegment(balance.fatRatio, fatColor);
        drawSegment(balance.carbohydrateRatio, carbohydrateColor);
      }

      final showLabel = i == 0 || i == days.length - 1;
      labelPainter.text = TextSpan(
        text: showLabel ? '${day.day.month}/${day.day.day}' : '•',
        style: TextStyle(color: labelColor, fontSize: showLabel ? 12 : 15),
      );
      labelPainter.layout();
      labelPainter.paint(
        canvas,
        Offset(x - labelPainter.width / 2, baseY + 14),
      );
    }
  }

  @override
  bool shouldRepaint(_PfcBalanceChartPainter oldDelegate) {
    return days != oldDelegate.days ||
        proteinColor != oldDelegate.proteinColor ||
        fatColor != oldDelegate.fatColor ||
        carbohydrateColor != oldDelegate.carbohydrateColor ||
        emptyColor != oldDelegate.emptyColor ||
        gridColor != oldDelegate.gridColor ||
        labelColor != oldDelegate.labelColor;
  }
}

class _WeeklyNutritionChartPainter extends CustomPainter {
  const _WeeklyNutritionChartPainter({
    required this.days,
    required this.metric,
    required this.gridColor,
    required this.barColor,
    required this.labelColor,
  });

  final List<_WeeklyDaySummary> days;
  final _EatLogMetric metric;
  final Color gridColor;
  final Color barColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;

    const left = 34.0;
    const right = 10.0;
    const top = 8.0;
    const bottom = 42.0;
    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;
    final values = days.map(metric.valueFor).toList();
    final maxValue = values.fold<double>(
      0,
      (max, value) => value > max ? value : max,
    );
    final scaleMax = maxValue <= 0 ? 1.0 : maxValue * 1.25;
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final barPaint = Paint()
      ..color = barColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 12;
    final labelPainter = TextPainter(textDirection: TextDirection.ltr);

    for (var i = 0; i <= 4; i++) {
      final y = top + chartHeight * i / 4;
      canvas.drawLine(
        Offset(left, y),
        Offset(size.width - right, y),
        gridPaint,
      );
      final value = scaleMax * (4 - i) / 4;
      labelPainter.text = TextSpan(
        text: _formatAxisValue(value),
        style: TextStyle(color: labelColor, fontSize: 11),
      );
      labelPainter.layout();
      labelPainter.paint(canvas, Offset(0, y - labelPainter.height / 2));
    }

    final step = days.length == 1 ? chartWidth : chartWidth / (days.length - 1);
    for (var i = 0; i < days.length; i++) {
      final day = days[i];
      final value = values[i];
      final x = left + step * i;
      final barHeight = chartHeight * (value / scaleMax);
      final baseY = top + chartHeight;
      if (value > 0) {
        canvas.drawLine(
          Offset(x, baseY),
          Offset(x, baseY - barHeight),
          barPaint,
        );
      }

      final showLabel = i == 0 || i == days.length - 1;
      labelPainter.text = TextSpan(
        text: showLabel ? '${day.day.month}/${day.day.day}' : '•',
        style: TextStyle(color: labelColor, fontSize: showLabel ? 12 : 15),
      );
      labelPainter.layout();
      labelPainter.paint(
        canvas,
        Offset(x - labelPainter.width / 2, baseY + 14),
      );
    }
  }

  String _formatAxisValue(double value) {
    return metric == _EatLogMetric.calories
        ? value.round().toString()
        : value.toStringAsFixed(1);
  }

  @override
  bool shouldRepaint(_WeeklyNutritionChartPainter oldDelegate) {
    return days != oldDelegate.days ||
        metric != oldDelegate.metric ||
        gridColor != oldDelegate.gridColor ||
        barColor != oldDelegate.barColor ||
        labelColor != oldDelegate.labelColor;
  }
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({
    required this.initialProfile,
    required this.onOpenWeightHistory,
  });

  final UserProfile initialProfile;
  final Future<void> Function(List<WeightEntry> history) onOpenWeightHistory;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  late final TextEditingController _heightController;
  late final TextEditingController _weightController;
  late final TextEditingController _birthDateController;
  late final TextEditingController _notesController;

  late String _gender;
  DateTime? _birthDate;

  @override
  void initState() {
    super.initState();
    final profile = widget.initialProfile;
    _birthDate = profile.birthDate;
    _gender = profile.gender;
    _heightController = TextEditingController(
      text: profile.heightCm > 0 ? profile.heightCm.toStringAsFixed(1) : '',
    );
    _weightController = TextEditingController(
      text: profile.weightKg > 0 ? profile.weightKg.toStringAsFixed(2) : '',
    );
    _birthDateController = TextEditingController(text: _formatDate(_birthDate));
    _notesController = TextEditingController(text: profile.notes);
  }

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    _birthDateController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked == null || !mounted) return;

    setState(() {
      _birthDate = picked;
      _birthDateController.text = _formatDate(picked);
    });
  }

  void _save() {
    final weightKg = _parseProfileNumber(_weightController.text);
    final weightHistory = _updatedWeightHistory(weightKg);
    Navigator.of(context).pop(
      UserProfile(
        heightCm: _parseProfileNumber(_heightController.text),
        weightKg: weightKg,
        weightHistory: weightHistory,
        birthDate: _birthDate,
        gender: _gender,
        notes: _notesController.text.trim(),
      ),
    );
  }

  List<WeightEntry> _updatedWeightHistory(double weightKg) {
    final history = List<WeightEntry>.of(widget.initialProfile.weightHistory);
    if (weightKg <= 0) return history;
    if (history.isNotEmpty && history.last.weightKg == weightKg) return history;
    history.add(WeightEntry(enteredAt: DateTime.now(), weightKg: weightKg));
    return history..sort((a, b) => a.enteredAt.compareTo(b.enteredAt));
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return AlertDialog(
      title: Text(strings.t('身体情報を入力')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _heightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(labelText: strings.t('身長 cm')),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _weightController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: const [_TwoDecimalInputFormatter()],
                    decoration: InputDecoration(labelText: strings.t('体重 kg')),
                  ),
                ),
                if (widget.initialProfile.weightHistory.length >= 2) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => widget.onOpenWeightHistory(
                      widget.initialProfile.weightHistory,
                    ),
                    icon: const Icon(Icons.show_chart),
                    label: Text(strings.t('推移')),
                  ),
                ],
              ],
            ),
            TextField(
              controller: _birthDateController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: strings.t('生年月日'),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.calendar_today),
                  tooltip: strings.t('生年月日を選択'),
                  onPressed: _pickBirthDate,
                ),
              ),
              onTap: _pickBirthDate,
            ),
            DropdownButtonFormField<String>(
              initialValue: _gender,
              decoration: InputDecoration(labelText: strings.t('性別')),
              items: [
                DropdownMenuItem(
                  value: UserProfile.genderMale,
                  child: Text(strings.t('男')),
                ),
                DropdownMenuItem(
                  value: UserProfile.genderFemale,
                  child: Text(strings.t('女')),
                ),
                DropdownMenuItem(
                  value: UserProfile.genderNoAnswer,
                  child: Text(strings.t('無回答')),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _gender = value);
              },
            ),
            TextField(
              controller: _notesController,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(labelText: strings.t('特記事項')),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.t('あとで')),
        ),
        FilledButton(onPressed: _save, child: Text(strings.t('保存'))),
      ],
    );
  }

  static String _formatDate(DateTime? dateTime) {
    if (dateTime == null) return '';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${dateTime.year}/${two(dateTime.month)}/${two(dateTime.day)}';
  }

  static double _parseProfileNumber(String text) {
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
    return double.tryParse(normalized) ?? 0;
  }
}

class WeightHistoryScreen extends StatelessWidget {
  const WeightHistoryScreen({super.key, required this.entries});

  final List<WeightEntry> entries;

  @override
  Widget build(BuildContext context) {
    final sortedEntries = List<WeightEntry>.of(entries)
      ..sort((a, b) => a.enteredAt.compareTo(b.enteredAt));
    final latest = sortedEntries.last;
    final strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(strings.t('体重の推移'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${latest.weightKg.toStringAsFixed(2)} kg',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    strings.isJapanese
                        ? '最新: ${_formatDateTime(latest.enteredAt)}'
                        : 'Latest: ${_formatDateTime(latest.enteredAt)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 260,
                    child: CustomPaint(
                      painter: _WeightHistoryChartPainter(
                        entries: sortedEntries,
                        gridColor: Theme.of(context).colorScheme.outlineVariant,
                        lineColor: Theme.of(context).colorScheme.primary,
                        pointColor: Theme.of(context).colorScheme.secondary,
                        labelColor: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            strings.t('入力履歴'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...sortedEntries.reversed.map(
            (entry) => Card(
              child: ListTile(
                leading: const Icon(Icons.monitor_weight),
                title: Text('${entry.weightKg.toStringAsFixed(2)} kg'),
                subtitle: Text(_formatDateTime(entry.enteredAt)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDateTime(DateTime dateTime) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${dateTime.year}/${two(dateTime.month)}/${two(dateTime.day)} ${two(dateTime.hour)}:${two(dateTime.minute)}';
  }
}

class _TwoDecimalInputFormatter extends TextInputFormatter {
  const _TwoDecimalInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    final decimalSeparators = RegExp('[.,，．]').allMatches(text).length;
    if (decimalSeparators > 1) return oldValue;

    final normalized = text.replaceAll('，', '.').replaceAll('．', '.');
    final parts = normalized.split('.');
    if (parts.length > 1 && parts.last.length > 2) return oldValue;

    final validText = RegExp(r'^[0-9０-９.,，．]*$').hasMatch(text);
    return validText ? newValue : oldValue;
  }
}

class _WeightHistoryChartPainter extends CustomPainter {
  const _WeightHistoryChartPainter({
    required this.entries,
    required this.gridColor,
    required this.lineColor,
    required this.pointColor,
    required this.labelColor,
  });

  final List<WeightEntry> entries;
  final Color gridColor;
  final Color lineColor;
  final Color pointColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.length < 2) return;

    const left = 42.0;
    const right = 16.0;
    const top = 14.0;
    const bottom = 44.0;
    final chartWidth = size.width - left - right;
    final chartHeight = size.height - top - bottom;
    final weights = entries.map((entry) => entry.weightKg).toList();
    final minWeight = weights.reduce((a, b) => a < b ? a : b);
    final maxWeight = weights.reduce((a, b) => a > b ? a : b);
    final padding = (maxWeight - minWeight).abs() < 0.1
        ? 1.0
        : (maxWeight - minWeight) * 0.15;
    final axisMin = minWeight - padding;
    final axisMax = maxWeight + padding;
    final axisRange = axisMax - axisMin;
    final labelPainter = TextPainter(textDirection: TextDirection.ltr);
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final pointPaint = Paint()
      ..color = pointColor
      ..style = PaintingStyle.fill;

    for (var i = 0; i <= 4; i++) {
      final y = top + chartHeight * i / 4;
      canvas.drawLine(
        Offset(left, y),
        Offset(size.width - right, y),
        gridPaint,
      );
      final value = axisMax - axisRange * i / 4;
      labelPainter.text = TextSpan(
        text: value.toStringAsFixed(2),
        style: TextStyle(color: labelColor, fontSize: 11),
      );
      labelPainter.layout(maxWidth: left - 4);
      labelPainter.paint(
        canvas,
        Offset(left - labelPainter.width - 6, y - labelPainter.height / 2),
      );
    }

    Offset pointFor(int index) {
      final entry = entries[index];
      final x = left + chartWidth * index / (entries.length - 1);
      final y =
          top + chartHeight * (1 - ((entry.weightKg - axisMin) / axisRange));
      return Offset(x, y);
    }

    final path = Path()..moveTo(pointFor(0).dx, pointFor(0).dy);
    for (var i = 1; i < entries.length; i++) {
      final point = pointFor(i);
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, linePaint);

    for (var i = 0; i < entries.length; i++) {
      canvas.drawCircle(pointFor(i), 4, pointPaint);
    }

    final first = entries.first.enteredAt;
    final last = entries.last.enteredAt;
    _paintDateLabel(
      canvas,
      labelPainter,
      first,
      Offset(left, top + chartHeight + 14),
    );
    _paintDateLabel(
      canvas,
      labelPainter,
      last,
      Offset(size.width - right, top + chartHeight + 14),
      alignRight: true,
    );
  }

  void _paintDateLabel(
    Canvas canvas,
    TextPainter labelPainter,
    DateTime dateTime,
    Offset offset, {
    bool alignRight = false,
  }) {
    labelPainter.text = TextSpan(
      text: '${dateTime.month}/${dateTime.day}',
      style: TextStyle(color: labelColor, fontSize: 12),
    );
    labelPainter.layout();
    labelPainter.paint(
      canvas,
      alignRight ? Offset(offset.dx - labelPainter.width, offset.dy) : offset,
    );
  }

  @override
  bool shouldRepaint(_WeightHistoryChartPainter oldDelegate) {
    return entries != oldDelegate.entries ||
        gridColor != oldDelegate.gridColor ||
        lineColor != oldDelegate.lineColor ||
        pointColor != oldDelegate.pointColor ||
        labelColor != oldDelegate.labelColor;
  }
}

class MealDetailScreen extends StatefulWidget {
  const MealDetailScreen({
    super.key,
    required this.meal,
    required this.gemmaService,
    required this.onMealUpdated,
    required this.onMealDeleted,
  });

  final MealEntry meal;
  final GemmaService gemmaService;
  final Future<void> Function(MealEntry meal) onMealUpdated;
  final Future<void> Function(MealEntry meal) onMealDeleted;

  @override
  State<MealDetailScreen> createState() => _MealDetailScreenState();
}

class _MealDetailScreenState extends State<MealDetailScreen> {
  final _chatController = TextEditingController();
  final _chatImagePicker = ImagePicker();

  late MealEntry _meal;
  bool _isRefining = false;
  File? _referenceImage;

  @override
  void initState() {
    super.initState();
    _meal = widget.meal;
  }

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  Future<void> _pickReferenceImage(ImageSource source) async {
    try {
      final picked = await _chatImagePicker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      setState(() => _referenceImage = File(picked.path));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('画像を選択できませんでした。もう一度お試しください。')),
      );
    }
  }

  Future<void> _sendClarification() async {
    final answer = _chatController.text.trim();
    final referenceImage = _referenceImage;
    if (answer.isEmpty && referenceImage == null) return;
    _chatController.clear();
    if (mounted) setState(() => _referenceImage = null);

    final userText = [
      if (answer.isNotEmpty) answer,
      if (referenceImage != null) '（成分表画像を添付）',
    ].join('\n');

    final userMessage = MealMessage(
      role: 'user',
      text: userText,
      createdAt: DateTime.now(),
      imagePath: referenceImage?.path,
    );
    final pendingMeal = _meal.copyWith(
      messages: [..._meal.messages, userMessage],
    );
    await _replaceMeal(pendingMeal);

    if (!widget.gemmaService.isInitialized) {
      await _replaceMeal(
        pendingMeal.copyWith(
          messages: [
            ...pendingMeal.messages,
            MealMessage(
              role: 'assistant',
              text: 'モデルを読み込むと、この回答を使って栄養値を再計算できます。',
              createdAt: DateTime.now(),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _isRefining = true);
    try {
      String? ocrText;
      if (referenceImage != null) {
        final extracted = await widget.gemmaService.extractTextFromImage(
          referenceImage.path,
        );
        if (extracted.trim().isNotEmpty) {
          ocrText = extracted.trim();
          await _replaceMeal(
            pendingMeal.copyWith(
              messages: [
                ...pendingMeal.messages,
                MealMessage(
                  role: 'assistant',
                  text:
                      'OCR読み取り結果:\n${_previewOcrText(ocrText)}\n\nこのテキストを優先して再計算します。',
                  createdAt: DateTime.now(),
                ),
              ],
            ),
          );
        }
      }

      final latestMeal = _meal;
      final response = await widget.gemmaService.refineMeal(
        currentMealJson: jsonEncode(latestMeal.toJson()),
        userAnswer: answer,
        referenceImagePath: referenceImage?.path,
        ocrText: ocrText,
      );
      final refined = MealEntry.fromGemmaJson(
        imagePath: _meal.imagePath,
        eatenAt: _meal.eatenAt,
        response: response,
      );
      await _replaceMeal(
        pendingMeal.copyWith(
          foodName: refined.foodName,
          summary: refined.summary,
          nutrition: refined.nutrition,
          confidence: refined.confidence,
          questions: refined.questions,
          rawGemmaResponse: response,
          messages: [
            ...pendingMeal.messages,
            MealMessage(
              role: 'assistant',
              text: refined.questions.isEmpty
                  ? (refined.summary.isEmpty
                        ? '回答を反映して栄養値を更新しました。'
                        : '読み取り結果: ${refined.summary}\n\n回答を反映して栄養値を更新しました。')
                  : (refined.summary.isEmpty
                        ? refined.questions.join('\n')
                        : '読み取り結果: ${refined.summary}\n\n確認事項:\n${refined.questions.join('\n')}'),
              createdAt: DateTime.now(),
            ),
          ],
        ),
      );
    } catch (e) {
      await _replaceMeal(
        pendingMeal.copyWith(
          messages: [
            ...pendingMeal.messages,
            MealMessage(
              role: 'assistant',
              text: '再計算に失敗しました: $e',
              createdAt: DateTime.now(),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _isRefining = false);
    }
  }

  String _previewOcrText(String text) {
    const maxLength = 260;
    return text.length <= maxLength
        ? text
        : '${text.substring(0, maxLength)}...';
  }

  Future<void> _replaceMeal(MealEntry meal) async {
    if (mounted) setState(() => _meal = meal);
    await widget.onMealUpdated(meal);
  }

  Future<void> _confirmDeleteMeal() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final strings = AppStrings.of(context);
        return AlertDialog(
          title: Text(strings.t('この食事を削除しますか？')),
          content: Text(strings.t('削除すると、食事ログと栄養集計からこの記録が取り除かれます。')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(strings.t('キャンセル')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(strings.t('削除')),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    await widget.onMealDeleted(_meal);
    if (!mounted) return;
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text(AppStrings.of(context).t('食事を削除しました。'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.of(context).t('食事詳細')),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _buildMealDetail(_meal),
      ),
    );
  }

  Widget _buildMealDetail(MealEntry meal) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMealPhoto(meal),
            const SizedBox(height: 12),
            Text(meal.foodName, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(_formatDateTime(meal.eatenAt)),
            if (meal.summary.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(meal.summary),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _metricChip(
                  AppStrings.of(context).t('総カロリー'),
                  meal.nutrition.caloriesKcal,
                  'kcal',
                  Icons.bolt,
                ),
                _metricChip(
                  'P',
                  meal.nutrition.proteinG,
                  'g',
                  Icons.fitness_center,
                ),
                _metricChip('F', meal.nutrition.fatG, 'g', Icons.water_drop),
                _metricChip(
                  'C',
                  meal.nutrition.carbohydrateG,
                  'g',
                  Icons.rice_bowl,
                ),
                _metricChip(
                  AppStrings.of(context).t('塩分'),
                  meal.nutrition.saltG,
                  'g',
                  Icons.grain,
                ),
                _metricChip(
                  AppStrings.of(context).t('カフェイン'),
                  meal.nutrition.caffeineMg,
                  'mg',
                  Icons.coffee,
                ),
                _metricChip(
                  AppStrings.of(context).t('アルコール'),
                  meal.nutrition.alcoholG,
                  'g',
                  Icons.local_bar,
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: meal.confidence),
            const SizedBox(height: 6),
            Text(
              AppStrings.of(context).isJapanese
                  ? '推定の確信度 ${(meal.confidence * 100).round()}%'
                  : 'Confidence ${(meal.confidence * 100).round()}%',
            ),
            const Divider(height: 28),
            Text(
              AppStrings.of(context).t('Gemmaとの確認'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            ...meal.messages.map(_buildMessageBubble),
            if (_isRefining) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            if (_referenceImage != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.file(_referenceImage!, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.photo_library, size: 18),
                  label: Text(AppStrings.of(context).t('成分表画像を選択')),
                  onPressed: _isRefining
                      ? null
                      : () => _pickReferenceImage(ImageSource.gallery),
                ),
                ActionChip(
                  avatar: const Icon(Icons.photo_camera, size: 18),
                  label: Text(AppStrings.of(context).t('撮影して添付')),
                  onPressed: _isRefining
                      ? null
                      : () => _pickReferenceImage(ImageSource.camera),
                ),
                if (_referenceImage != null)
                  ActionChip(
                    avatar: const Icon(Icons.close, size: 18),
                    label: Text(AppStrings.of(context).t('添付を外す')),
                    onPressed: _isRefining
                        ? null
                        : () => setState(() => _referenceImage = null),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: AppStrings.of(
                        context,
                      ).t('例: ご飯は小盛り、味噌汁あり（画像添付のみでも可）'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _isRefining ? null : _sendClarification,
                  icon: const Icon(Icons.send),
                  tooltip: AppStrings.of(context).t('送信'),
                ),
              ],
            ),
            const Divider(height: 32),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: _isRefining ? null : _confirmDeleteMeal,
                icon: const Icon(Icons.delete_outline),
                label: Text(AppStrings.of(context).t('この食事を削除')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMealPhoto(MealEntry meal) {
    final file = File(meal.imagePath);
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: file.existsSync()
            ? Image.file(file, fit: BoxFit.cover)
            : Container(
                color: colorScheme.surfaceContainerHighest,
                child: Center(
                  child: Icon(
                    Icons.restaurant,
                    size: 48,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _metricChip(String label, double value, String unit, IconData icon) {
    final formatted = value >= 100
        ? value.round().toString()
        : value.toStringAsFixed(1);
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text('$label $formatted$unit'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    );
  }

  Widget _buildMessageBubble(MealMessage message) {
    final isUser = message.role == 'user';
    final colorScheme = Theme.of(context).colorScheme;
    final imagePath = message.imagePath;
    final imageFile = (imagePath == null || imagePath.isEmpty)
        ? null
        : File(imagePath);
    final hasImage = imageFile?.existsSync() ?? false;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: isUser
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasImage) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 200,
                  height: 120,
                  child: Image.file(imageFile!, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              message.text,
              style: TextStyle(
                color: isUser
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return '未取得';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${dateTime.year}/${two(dateTime.month)}/${two(dateTime.day)} ${two(dateTime.hour)}:${two(dateTime.minute)}';
  }
}
