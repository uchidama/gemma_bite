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

### モデルのダウンロード

LiteRT-LM 用のモデル
https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm

```
# ツールが入っていない場合はインストール
pip install huggingface_hub

# ログイン（トークンが必要な場合があります）
huggingface-cli login

# モデルを丸ごとダウンロード
huggingface-cli download litert-community/gemma-4-E2B-it-litert-lm --local-dir ./models/gemma-4-E2B-it-litert-lm

```



### Gemma 4 MTP（ドラフターモデル）について

- 2026-05時点の LiteRT-LM Android ドキュメントでは、MTP は `ExperimentalFlags.enableSpeculativeDecoding = true` で有効化します。
- Gemma 4 の LiteRT モデル（例: `gemma-4-E2B-it.litertlm`）をそのまま利用し、推論側の投機的デコードをONにする運用です。
- 本アプリの Android 実装では、モデル初期化時に投機的デコードを有効化しています。
- MTPの有無や配布状況は公式ドキュメントを参照してください: https://ai.google.dev/gemma/docs/mtp/overview



### アプリの使い方

1. **モデル配置**: Gemma-4-E2B の `.litertlm` ファイルを以下にadbで転送

```
# ディレクトリ作成
adb shell mkdir -p /storage/emulated/0/Android/data/com.eyuras.gemma_bite/files/models

# モデルファイルを転送（ダウンロードしたファイルのパスに合わせて調整）
adb push ~/FlutterProjects/gemma_bite/models/gemma-4-E2B-it-litert-lm/gemma-4-E2B-it.litertlm /storage/emulated/0/Android/data/com.eyuras.gemma_bite/files/models/

adb push ./models/gemma-4-E2B-it-litert-lm/gemma-4-E2B-it.litertlm /storage/emulated/0/Android/data/com.eyuras.gemma_bite/files/models/

# 旧キャッシュを削除（再最適化させる）
adb shell rm -f /storage/emulated/0/Android/data/com.eyuras.gemma_bite/files/models/*.xnnpack_cache_*
```

2. **モデル読み込み**: アプリ内でモデルファイルを選択して初期化
3. **撮影/選択** → **分析** → Gemma 4 がオンデバイスで推論し、カロリー・栄養素・アルコール・アドバイスを表示

### 注意点
- **iOS**: LiteRT-LM の Swift SDK が開発中のため、現時点では Android のみ LLM 機能が動作します
- モデルファイル（約2.6GB）はアプリに同梱されず、手動配置が必要です
- `SamplerConfig` の `topP`/`temperature` の型が `Double` か `Float` かは、実際のビルド時に調整が必要な可能性があります

変更を行いました。

### 実行

```
flutter run
```

```
flutter devices
flutter run -d 57060DLCQ000P3
```

#### インストールだけして apk を作りたい

```
flutter build apk
flutter install -d 57060DLCQ000P3
```

# スクリーンショットを取得

## 接続されているAndroid端末のスクリーンショットをローカルにとる

```
adb exec-out screencap -p > screenshot.png
```

```
adb devices
adb shell ls /sdcard/Pictures/Screenshots | tail
```

## スクリーンショットから最新の１枚を取得

```
latest=$(adb shell ls /sdcard/Pictures/Screenshots | tail -n 1 | tr -d '\r')
adb pull "/sdcard/Pictures/Screenshots/$latest" .
```

# 仕様案

## 主要な栄養素の集計

### 黄金の「PFCバランス」（最優先）

- タンパク質 (Protein)
- 脂質 (Fat)
- 炭水化物 (Carbohydrate)
- 総カロリー
- 塩分

### 嗜好品系

- カフェイン
- アルコール

## 食事の時系列の記録

　写真の撮影時間から、どの時間の食事か取れるだろう。これを記録。一覧でみれる

## 食事内容について、正確な情報がわからないときはGemmaから質問してくる。ユーザーが文言で答えてチャットでやりとりすることで情報は正確になる

## １日の摂取カロリー、栄養が集計される

## 現在の身長、体重を入力

　アプリ起動時か？


・Googleカレンダーとの連携。
　持久力が求められる運動をする場合: 「明日は長距離を走る予定なら、もう少し炭水化物を多めに摂っておきましょう」といった助言。