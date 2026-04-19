import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/gemma_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _gemmaService = GemmaService();
  final _imagePicker = ImagePicker();

  bool _isModelLoading = false;
  String? _modelDirectory;
  List<String> _availableModels = [];
  File? _selectedImage;
  bool _isAnalyzing = false;
  String? _analysisResult;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadModelInfo();
  }

  Future<void> _loadModelInfo() async {
    try {
      final dir = await _gemmaService.getModelDirectory();
      final models = await _gemmaService.listModels();
      if (mounted) {
        setState(() {
          _modelDirectory = dir;
          _availableModels = models;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    }
  }

  Future<void> _initializeModel(String modelPath) async {
    setState(() {
      _isModelLoading = true;
      _error = null;
    });
    try {
      await _gemmaService.initialize(modelPath);
      if (mounted) {
        setState(() => _isModelLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
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
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked != null && mounted) {
        setState(() {
          _selectedImage = File(picked.path);
          _analysisResult = null;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    }
  }

  Future<void> _analyzeFood() async {
    if (_selectedImage == null || !_gemmaService.isInitialized) return;

    setState(() {
      _isAnalyzing = true;
      _analysisResult = null;
      _error = null;
    });
    try {
      final result = await _gemmaService.analyzeFood(_selectedImage!.path);
      if (mounted) {
        setState(() {
          _analysisResult = result;
          _isAnalyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isAnalyzing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _gemmaService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gemma Bite'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_gemmaService.isInitialized)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'モデルをリセット',
              onPressed: () async {
                await _gemmaService.dispose();
                setState(() {
                  _analysisResult = null;
                  _selectedImage = null;
                });
                _loadModelInfo();
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildModelStatus(),
            const SizedBox(height: 16),
            if (_gemmaService.isInitialized) ...[
              _buildImageSection(),
              const SizedBox(height: 12),
              _buildActionButtons(),
              const SizedBox(height: 16),
              if (_isAnalyzing) _buildLoadingIndicator(),
              if (_analysisResult != null) _buildResults(),
            ],
            if (_error != null) _buildError(),
          ],
        ),
      ),
    );
  }

  Widget _buildModelStatus() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _gemmaService.isInitialized
                      ? Icons.check_circle
                      : _isModelLoading
                          ? Icons.hourglass_top
                          : Icons.circle_outlined,
                  color: _gemmaService.isInitialized
                      ? Colors.green
                      : _isModelLoading
                          ? Colors.orange
                          : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  _gemmaService.isInitialized
                      ? 'モデル準備完了'
                      : _isModelLoading
                          ? 'モデル読み込み中...'
                          : 'モデル未読み込み',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            if (_isModelLoading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text(
                '初回読み込みには時間がかかります（最大数十秒）...',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            if (!_gemmaService.isInitialized && !_isModelLoading) ...[
              const SizedBox(height: 12),
              if (_availableModels.isEmpty) ...[
                Text(
                  'モデルファイル (.litertlm) を以下のディレクトリに配置してください:',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectableText(
                    _modelDirectory ?? '読み込み中...',
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const SelectableText(
                    'adb push gemma-4-E2B-it.litertlm \n  <上記パス>/',
                    style: TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _loadModelInfo,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('モデルを再検索'),
                ),
              ] else ...[
                const Text('利用可能なモデル:'),
                const SizedBox(height: 8),
                ..._availableModels.map((model) {
                  final name = model.split('/').last;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _initializeModel(model),
                        icon: const Icon(Icons.play_arrow),
                        label: Text(name),
                      ),
                    ),
                  );
                }),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImageSection() {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: _selectedImage != null
          ? Image.file(
              _selectedImage!,
              height: 250,
              width: double.infinity,
              fit: BoxFit.cover,
            )
          : Container(
              height: 200,
              color: Colors.grey[100],
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.restaurant, size: 48, color: Colors.grey),
                    SizedBox(height: 8),
                    Text(
                      '食事の写真を撮影・選択してください',
                      style: TextStyle(color: Colors.grey),
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
            onPressed: _isAnalyzing ? null : () => _pickImage(ImageSource.camera),
            icon: const Icon(Icons.camera_alt, size: 18),
            label: const Text('撮影'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed:
                _isAnalyzing ? null : () => _pickImage(ImageSource.gallery),
            icon: const Icon(Icons.photo_library, size: 18),
            label: const Text('選択'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed:
                (_selectedImage != null && !_isAnalyzing) ? _analyzeFood : null,
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
        padding: EdgeInsets.all(32),
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Gemma 4 が食事を分析中...'),
            SizedBox(height: 4),
            Text(
              'オンデバイスで推論しています',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.restaurant_menu,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  '分析結果',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const Divider(),
            SelectableText(
              _analysisResult ?? '',
              style: const TextStyle(height: 1.5),
            ),
          ],
        ),
      ),
    );
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
}
