import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../domain/meal_models.dart';
import '../services/gemma_service.dart';
import '../services/meal_repository.dart';
import '../services/photo_taken_at_reader.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _gemmaService = GemmaService();
  final _imagePicker = ImagePicker();
  final _repository = MealRepository();
  final _photoTakenAtReader = PhotoTakenAtReader();
  final _chatController = TextEditingController();

  bool _isPreparingModel = true;
  bool _isModelLoading = false;
  bool _isLogLoading = true;
  bool _isAnalyzing = false;
  bool _isRefining = false;
  bool _hasTriedAutoModelLoad = false;
  bool _hasPromptedForProfile = false;
  String? _modelDirectory;
  List<String> _availableModels = [];
  File? _selectedImage;
  DateTime? _selectedImageTime;
  MealLog _log = const MealLog();
  String? _selectedMealId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadModelInfo();
    _loadLog();
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

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(source: source);
      if (picked == null || !mounted) return;

      final imageFile = File(picked.path);
      final timestamp = source == ImageSource.camera
          ? DateTime.now()
          : await _photoTakenAtReader.readTakenAt(imageFile.path) ??
                await imageFile.lastModified();
      setState(() {
        _selectedImage = imageFile;
        _selectedImageTime = timestamp;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _analyzeFood() async {
    if (_selectedImage == null || !_gemmaService.isInitialized) return;

    setState(() {
      _isAnalyzing = true;
      _error = null;
    });
    try {
      final response = await _gemmaService.analyzeFood(_selectedImage!.path);
      final meal = MealEntry.fromGemmaJson(
        imagePath: _selectedImage!.path,
        eatenAt: _selectedImageTime ?? DateTime.now(),
        response: response,
      );
      await _saveLog(
        _log.copyWith(meals: [meal, ..._log.meals]..sort(_sortMeals)),
      );
      if (mounted) {
        setState(() {
          _selectedMealId = meal.id;
          _selectedImage = null;
          _selectedImageTime = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '分析結果を記録できませんでした: $e');
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  Future<void> _sendClarification(MealEntry meal) async {
    final answer = _chatController.text.trim();
    if (answer.isEmpty) return;
    _chatController.clear();

    final userMessage = MealMessage(
      role: 'user',
      text: answer,
      createdAt: DateTime.now(),
    );
    final pendingMeal = meal.copyWith(
      messages: [...meal.messages, userMessage],
    );
    await _replaceMeal(pendingMeal);

    if (!_gemmaService.isInitialized) {
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
      final response = await _gemmaService.refineMeal(
        currentMealJson: jsonEncode(pendingMeal.toJson()),
        userAnswer: answer,
      );
      final refined = MealEntry.fromGemmaJson(
        imagePath: meal.imagePath,
        eatenAt: meal.eatenAt,
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
                  ? '回答を反映して栄養値を更新しました。'
                  : refined.questions.join('\n'),
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

  Future<void> _replaceMeal(MealEntry updatedMeal) async {
    final meals =
        _log.meals
            .map((meal) => meal.id == updatedMeal.id ? updatedMeal : meal)
            .toList()
          ..sort(_sortMeals);
    await _saveLog(_log.copyWith(meals: meals));
  }

  int _sortMeals(MealEntry a, MealEntry b) => b.eatenAt.compareTo(a.eatenAt);

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

  MealEntry? get _selectedMeal {
    for (final meal in _log.meals) {
      if (meal.id == _selectedMealId) return meal;
    }
    return _log.meals.isEmpty ? null : _log.meals.first;
  }

  @override
  void dispose() {
    _chatController.dispose();
    _gemmaService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedMeal = _selectedMeal;

    if (!_gemmaService.isInitialized) {
      return _buildModelPreparationScreen();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gemma Bite'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            tooltip: '身体情報',
            onPressed: _showProfileDialog,
          ),
          if (_gemmaService.isInitialized)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'モデルをリセット',
              onPressed: () async {
                await _gemmaService.dispose();
                setState(() {
                  _selectedImage = null;
                  _selectedImageTime = null;
                  _hasTriedAutoModelLoad = false;
                });
                _loadModelInfo();
              },
            ),
        ],
      ),
      body: _isLogLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildImageSection(),
                  const SizedBox(height: 12),
                  _buildActionButtons(),
                  if (_isAnalyzing) ...[
                    const SizedBox(height: 12),
                    _buildLoadingIndicator(),
                  ],
                  const SizedBox(height: 16),
                  _buildDailySummary(_log.mealsForDay(DateTime.now())),
                  const SizedBox(height: 12),
                  _buildMealTimeline(_log.meals, title: '食事の記録'),
                  if (selectedMeal != null) ...[
                    const SizedBox(height: 12),
                    _buildMealDetail(selectedMeal),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _buildError(),
                  ],
                ],
              ),
            ),
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
                      isSearching ? 'モデルを確認しています' : 'モデルを読み込んでいます',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '初回読み込みには時間がかかります。',
                      textAlign: TextAlign.center,
                    ),
                  ] else if (_availableModels.isEmpty) ...[
                    Text(
                      'モデルファイルが見つかりません',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'モデルファイル (.litertlm) を配置してください:',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      _modelDirectory ?? '読み込み中...',
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
                      label: const Text('モデルを再検索'),
                    ),
                  ] else ...[
                    Text(
                      '読み込むモデルを選択してください',
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
                          label: Text(model.split('/').last),
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

  Widget _buildDailySummary(List<MealEntry> meals) {
    final totals = _log.totalsForDay(DateTime.now());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('1日の摂取量', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _metricChip('総カロリー', totals.caloriesKcal, 'kcal', Icons.bolt),
                _metricChip(
                  'タンパク質',
                  totals.proteinG,
                  'g',
                  Icons.fitness_center,
                ),
                _metricChip('脂質', totals.fatG, 'g', Icons.water_drop),
                _metricChip('炭水化物', totals.carbohydrateG, 'g', Icons.rice_bowl),
                _metricChip('塩分', totals.saltG, 'g', Icons.grain),
                _metricChip('カフェイン', totals.caffeineMg, 'mg', Icons.coffee),
                _metricChip('アルコール', totals.alcoholG, 'g', Icons.local_bar),
              ],
            ),
            const SizedBox(height: 12),
            Text('${meals.length}件の食事を記録済み'),
          ],
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

  Widget _buildImageSection() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: _selectedImage != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.file(
                  _selectedImage!,
                  height: 230,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('食事時刻: ${_formatDateTime(_selectedImageTime)}'),
                ),
              ],
            )
          : Container(
              height: 180,
              color: Colors.grey[100],
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.restaurant, size: 44, color: Colors.grey),
                    SizedBox(height: 8),
                    Text('食事の写真を撮影・選択してください'),
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
            label: const Text('撮影'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isAnalyzing
                ? null
                : () => _pickImage(ImageSource.gallery),
            icon: const Icon(Icons.photo_library, size: 18),
            label: const Text('選択'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed:
                (_selectedImage != null &&
                    !_isAnalyzing &&
                    _gemmaService.isInitialized)
                ? _analyzeFood
                : null,
            icon: const Icon(Icons.analytics, size: 18),
            label: const Text('分析'),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingIndicator() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Gemma が食事を分析中...'),
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
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('まだ食事記録がありません')),
              )
            else
              ...meals.map((meal) {
                final selected = meal.id == _selectedMeal?.id;
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
                  onTap: () => setState(() => _selectedMealId = meal.id),
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

  Widget _buildMealDetail(MealEntry meal) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                  '総カロリー',
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
                _metricChip('塩分', meal.nutrition.saltG, 'g', Icons.grain),
                _metricChip(
                  'カフェイン',
                  meal.nutrition.caffeineMg,
                  'mg',
                  Icons.coffee,
                ),
                _metricChip(
                  'アルコール',
                  meal.nutrition.alcoholG,
                  'g',
                  Icons.local_bar,
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: meal.confidence),
            const SizedBox(height: 6),
            Text('推定の確信度 ${(meal.confidence * 100).round()}%'),
            const Divider(height: 28),
            Text('Gemmaとの確認', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ...meal.messages.map(_buildMessageBubble),
            if (_isRefining) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: '例: ご飯は小盛り、味噌汁あり',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _isRefining
                      ? null
                      : () => _sendClarification(meal),
                  icon: const Icon(Icons.send),
                  tooltip: '送信',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(MealMessage message) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(message.text),
      ),
    );
  }

  Future<void> _showProfileDialog() async {
    if (!mounted) return;
    final heightController = TextEditingController(
      text: _log.profile.heightCm > 0
          ? _log.profile.heightCm.toStringAsFixed(1)
          : '',
    );
    final weightController = TextEditingController(
      text: _log.profile.weightKg > 0
          ? _log.profile.weightKg.toStringAsFixed(1)
          : '',
    );

    UserProfile? profile;
    try {
      profile = await showDialog<UserProfile>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('身体情報を入力'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: heightController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: '身長 cm'),
                ),
                TextField(
                  controller: weightController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: '体重 kg'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('あとで'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop(
                    UserProfile(
                      heightCm: _parseProfileNumber(heightController.text),
                      weightKg: _parseProfileNumber(weightController.text),
                    ),
                  );
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      );
    } finally {
      heightController.dispose();
      weightController.dispose();
    }
    if (!mounted || profile == null) return;

    try {
      await _saveLog(_log.copyWith(profile: profile));
    } catch (e) {
      if (mounted) setState(() => _error = '身体情報を保存できませんでした: $e');
    }
  }

  double _parseProfileNumber(String text) {
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
    if (dateTime == null) return '未取得';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${dateTime.year}/${two(dateTime.month)}/${two(dateTime.day)} ${two(dateTime.hour)}:${two(dateTime.minute)}';
  }
}
