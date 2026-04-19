# gemma_bite

A new Flutter project.

- 食事の写真を撮ることによってGemma4でカロリー、栄養素を推定。カロリーの取りすぎ、栄養の偏りなどに関するアドバイスをする
- アルコール摂取量も推定する
- Gemma4により、飛行機の機内などネットが通りにくいところでも使用できる

## 対象プラットフォーム

- iPhone
- Android

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.


### 実装内容

| レイヤー | ファイル | 内容 |
|---|---|---|
| **Flutter UI** | main.dart | アプリエントリポイント |
| | home_screen.dart | メイン画面（モデル管理・撮影・分析結果表示） |
| | gemma_service.dart | Platform Channel ラッパー |
| **Android** | android/app/.../MainActivity.kt | LiteRT-LM エンジン初期化・マルチモーダル推論 |
| | build.gradle.kts | LiteRT-LM 依存関係追加、minSdk=26 |
| | AndroidManifest.xml | カメラ権限、GPU ネイティブライブラリ |
| **iOS** | Info.plist | カメラ・フォトライブラリ使用説明 |

### アプリの使い方

1. **モデル配置**: Gemma-4-E2B の `.litertlm` ファイルを以下にadbで転送
   ```
   adb push gemma-4-E2B-it.litertlm /storage/emulated/0/Android/data/com.eyuras.gemma_bite/files/models/
   ```
2. **モデル読み込み**: アプリ内でモデルファイルを選択して初期化
3. **撮影/選択** → **分析** → Gemma 4 がオンデバイスで推論し、カロリー・栄養素・アルコール・アドバイスを表示

### 注意点
- **iOS**: LiteRT-LM の Swift SDK が開発中のため、現時点では Android のみ LLM 機能が動作します
- モデルファイル（約2.6GB）はアプリに同梱されず、手動配置が必要です
- `SamplerConfig` の `topP`/`temperature` の型が `Double` か `Float` かは、実際のビルド時に調整が必要な可能性があります

変更を行いました。
