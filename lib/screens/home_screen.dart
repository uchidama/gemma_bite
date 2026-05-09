import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../domain/meal_models.dart';
import '../services/gemma_service.dart';
import '../services/meal_repository.dart';
import '../services/photo_taken_at_reader.dart';

enum _MainTab { home, eatLog, settings }

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final ThemeMode themeMode;
  final Future<void> Function(ThemeMode themeMode) onThemeModeChanged;

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

class _HomeScreenState extends State<HomeScreen> {
  final _gemmaService = GemmaService();
  final _imagePicker = ImagePicker();
  final _repository = MealRepository();
  final _photoTakenAtReader = PhotoTakenAtReader();

  bool _isPreparingModel = true;
  bool _isModelLoading = false;
  bool _isLogLoading = true;
  bool _isAnalyzing = false;
  bool _hasTriedAutoModelLoad = false;
  bool _hasPromptedForProfile = false;
  String? _modelDirectory;
  List<String> _availableModels = [];
  File? _selectedImage;
  DateTime? _selectedImageTime;
  MealLog _log = const MealLog();
  String? _selectedMealId;
  String? _error;
  _MainTab _tab = _MainTab.home;

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
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85,
      );
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

  @override
  void dispose() {
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
          _MainTab.eatLog => 'イートログ',
          _MainTab.settings => '設定',
        }),
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab.index,
        onDestinationSelected: (index) {
          setState(() => _tab = _MainTab.values[index]);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'ホーム'),
          NavigationDestination(icon: Icon(Icons.insights), label: 'イートログ'),
          NavigationDestination(icon: Icon(Icons.settings), label: '設定'),
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
              ),
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

  Widget _buildSettingsTab() {
    final isDark = widget.themeMode == ThemeMode.dark;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SwitchListTile(
              secondary: const Icon(Icons.dark_mode),
              title: const Text('ダークモード'),
              subtitle: const Text('黒ベースのUIテーマに切り替えます'),
              value: isDark,
              onChanged: (enabled) {
                widget.onThemeModeChanged(
                  enabled ? ThemeMode.dark : ThemeMode.light,
                );
              },
            ),
          ),
        ),
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
      mealTitle: usesYesterday ? '昨日の食事の記録' : '今日の食事の記録',
      intakeTitle: usesYesterday ? '昨日の摂取量' : '今日の摂取量',
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
              label: '写真登録数',
              valueText: '${overview.meals.length}枚',
              icon: Icons.photo_camera,
              color: Colors.blue[600]!,
            ),
            _summaryRow(
              label: '総カロリー',
              value: overview.totals.caloriesKcal,
              unit: 'kcal',
              icon: Icons.bolt,
              color: Colors.amber[700]!,
            ),
            _summaryRow(
              label: 'タンパク質',
              value: overview.totals.proteinG,
              unit: 'g',
              icon: Icons.fitness_center,
              color: Colors.green[700]!,
            ),
            _summaryRow(
              label: '脂質',
              value: overview.totals.fatG,
              unit: 'g',
              icon: Icons.water_drop,
              color: Colors.teal[700]!,
            ),
            _summaryRow(
              label: '炭水化物',
              value: overview.totals.carbohydrateG,
              unit: 'g',
              icon: Icons.rice_bowl,
              color: Colors.lightGreen[700]!,
            ),
            _summaryRow(
              label: '塩分',
              value: overview.totals.saltG,
              unit: 'g',
              icon: Icons.grain,
              color: Colors.blueGrey[600]!,
            ),
            _summaryRow(
              label: 'カフェイン',
              value: overview.totals.caffeineMg,
              unit: 'mg',
              icon: Icons.coffee,
              color: Colors.brown[600]!,
            ),
            _summaryRow(
              label: 'アルコール',
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
                        '過去7日間',
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
                label: '摂取カロリーの1日平均',
                valueText: '${overview.averageCaloriesKcal.round()}kcal',
                icon: Icons.timeline,
                color: Colors.orange[700]!,
              ),
              _summaryValueRow(
                label: '写真投稿数',
                valueText: '${overview.photoCount}枚',
                icon: Icons.photo_library,
                color: Colors.blue[600]!,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  '各日の摂取カロリー',
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
                      '食事の写真を撮影・選択してください',
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
        ),
      ),
    );
  }

  void _openEatLog(_WeeklyOverview overview) {
    setState(() => _tab = _MainTab.eatLog);
  }

  Future<void> _showProfileDialog() async {
    if (!mounted) return;
    final profile = await showDialog<UserProfile>(
      context: context,
      builder: (context) => _ProfileDialog(initialProfile: _log.profile),
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
    if (dateTime == null) return '未取得';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${dateTime.year}/${two(dateTime.month)}/${two(dateTime.day)} ${two(dateTime.hour)}:${two(dateTime.minute)}';
  }

  String _formatDayLabel(DateTime dateTime) {
    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
    final weekday = weekdays[dateTime.weekday - 1];
    return '${dateTime.month}/${dateTime.day} ($weekday)';
  }
}

enum _EatLogMetric {
  calories('カロリー', 'kcal', Colors.amber, Icons.bolt),
  protein('タンパク質', 'g', Colors.green, Icons.fitness_center),
  fat('脂質', 'g', Colors.teal, Icons.water_drop),
  carbohydrate('炭水化物', 'g', Colors.lightGreen, Icons.rice_bowl);

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
    };
  }
}

class _EatLogContent extends StatefulWidget {
  const _EatLogContent({
    required this.overview,
    this.gemmaService,
    this.onMealUpdated,
  });

  final _WeeklyOverview overview;
  final GemmaService? gemmaService;
  final Future<void> Function(MealEntry meal)? onMealUpdated;

  @override
  State<_EatLogContent> createState() => _EatLogContentState();
}

class _EatLogContentState extends State<_EatLogContent> {
  _EatLogMetric _metric = _EatLogMetric.calories;

  @override
  Widget build(BuildContext context) {
    final chronologicalDays = widget.overview.days.reversed.toList();
    final meals = widget.overview.days.expand((day) => day.meals).toList()
      ..sort((a, b) => b.eatenAt.compareTo(a.eatenAt));
    final total = widget.overview.days.fold<double>(
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
            '過去7日間',
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
                    '${_metric.label}の推移',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 220,
                    child: CustomPaint(
                      painter: _WeeklyNutritionChartPainter(
                        days: chronologicalDays,
                        metric: _metric,
                        gridColor: Theme.of(context).colorScheme.outlineVariant,
                        barColor: _metric.color[700]!,
                        labelColor: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _metricTotal(
                          label: '合計',
                          value: _formatMetricValue(total),
                          icon: Icons.functions,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _metricTotal(
                          label: '一日の平均',
                          value: _formatMetricValue(average),
                          icon: Icons.timeline,
                        ),
                      ),
                    ],
                  ),
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
                      '写真投稿数',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _eatLogValueRow(
                    label: '過去7日間',
                    valueText: '${widget.overview.photoCount}枚',
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
              label: Text(metric.label),
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
            Text('イートログ', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (meals.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('この期間の食事記録はありません')),
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
    if (gemmaService == null || onMealUpdated == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MealDetailScreen(
          meal: meal,
          gemmaService: gemmaService,
          onMealUpdated: onMealUpdated,
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

  static String _formatRange(List<_WeeklyDaySummary> days) {
    if (days.isEmpty) return '';
    final start = days.first.day;
    final end = days.last.day;
    return '${start.month}月${start.day}日〜${end.day}日';
  }

  static String _formatDateTime(DateTime dateTime) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${dateTime.year}/${two(dateTime.month)}/${two(dateTime.day)} ${two(dateTime.hour)}:${two(dateTime.minute)}';
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
  const _ProfileDialog({required this.initialProfile});

  final UserProfile initialProfile;

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
      text: profile.weightKg > 0 ? profile.weightKg.toStringAsFixed(1) : '',
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
    Navigator.of(context).pop(
      UserProfile(
        heightCm: _parseProfileNumber(_heightController.text),
        weightKg: _parseProfileNumber(_weightController.text),
        birthDate: _birthDate,
        gender: _gender,
        notes: _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('身体情報を入力'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _heightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: '身長 cm'),
            ),
            TextField(
              controller: _weightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: '体重 kg'),
            ),
            TextField(
              controller: _birthDateController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: '生年月日',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.calendar_today),
                  tooltip: '生年月日を選択',
                  onPressed: _pickBirthDate,
                ),
              ),
              onTap: _pickBirthDate,
            ),
            DropdownButtonFormField<String>(
              initialValue: _gender,
              decoration: const InputDecoration(labelText: '性別'),
              items: const [
                DropdownMenuItem(
                  value: UserProfile.genderMale,
                  child: Text('男'),
                ),
                DropdownMenuItem(
                  value: UserProfile.genderFemale,
                  child: Text('女'),
                ),
                DropdownMenuItem(
                  value: UserProfile.genderNoAnswer,
                  child: Text('無回答'),
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
              decoration: const InputDecoration(labelText: '特記事項'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('あとで'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
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

class MealDetailScreen extends StatefulWidget {
  const MealDetailScreen({
    super.key,
    required this.meal,
    required this.gemmaService,
    required this.onMealUpdated,
  });

  final MealEntry meal;
  final GemmaService gemmaService;
  final Future<void> Function(MealEntry meal) onMealUpdated;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('食事詳細'),
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
                  label: const Text('成分表画像を選択'),
                  onPressed: _isRefining
                      ? null
                      : () => _pickReferenceImage(ImageSource.gallery),
                ),
                ActionChip(
                  avatar: const Icon(Icons.photo_camera, size: 18),
                  label: const Text('撮影して添付'),
                  onPressed: _isRefining
                      ? null
                      : () => _pickReferenceImage(ImageSource.camera),
                ),
                if (_referenceImage != null)
                  ActionChip(
                    avatar: const Icon(Icons.close, size: 18),
                    label: const Text('添付を外す'),
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
                    decoration: const InputDecoration(
                      hintText: '例: ご飯は小盛り、味噌汁あり（画像添付のみでも可）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _isRefining ? null : _sendClarification,
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
