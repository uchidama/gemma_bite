# Gemma Bite

Gemma Bite は、食事写真から Gemma 4 がオンデバイスでカロリーや栄養素を推定する Android 向けの食事記録アプリです。食事写真を撮影または選択すると、Gemma が栄養情報を推定し、プロフィールを考慮した食事相談まで行えます。

Kaggle コンペティション応募用のプロジェクトとして、プライバシーを守りやすく、通信しづらい環境でも使いやすい食事ログ体験を目指しています。

[English README](README.md)

<p align="center">
  <img src="docs/images/ja/boot.png" width="220" alt="Gemma Bite 日本語ホーム画面">
  <img src="docs/images/ja/meal_detail.png" width="220" alt="食事詳細画面">
  <img src="docs/images/ja/ai_chat_result.png" width="220" alt="AI相談の提案画面">
</p>

## 主な機能

- **Gemma 4 によるオンデバイス食事分析**: 食事写真からカロリー、タンパク質、脂質、炭水化物、塩分、カフェイン、アルコールを推定します。
- **複数写真の一括分析**: 登録していない写真を複数選択し、1枚ずつ食事記録として分析できます。
- **重複登録の防止**: 同じ食事写真を複数回登録しないようにチェックします。
- **プロフィールを考慮したAI相談**: 身長、体重、性別、生年月日、体重履歴、Notes のアレルギーや制限事項を踏まえて次の食事を提案します。
- **食事ログと摂取量の集計**: 写真の撮影時刻を使って食事時刻を記録し、1日の摂取量を確認できます。
- **栄養成分表による補正**: 栄養成分表や参考画像を添付して、推定結果をより正確にできます。
- **読み上げ機能**: Android の Text-to-Speech を使って、AI相談の回答を端末内の音声で読み上げます。
- **日本語・英語UI**: 端末の言語設定に追従しつつ、アプリ内設定で言語を切り替えられます。

## スクリーンショット

### 日本語UI

| ホーム | 食事詳細 | AI相談 |
|---|---|---|
| <img src="docs/images/ja/boot.png" width="240" alt="ホーム画面"> | <img src="docs/images/ja/meal_detail.png" width="240" alt="食事詳細"> | <img src="docs/images/ja/ai_chat_result.png" width="240" alt="AI相談結果"> |

| AI相談入力 | プロフィール | 設定 |
|---|---|---|
| <img src="docs/images/ja/ai_chat.png" width="240" alt="AI相談画面"> | <img src="docs/images/ja/profile.png" width="240" alt="プロフィール画面"> | <img src="docs/images/ja/setting.png" width="240" alt="設定画面"> |

英語UIのスクリーンショットは [README.md](README.md) に掲載しています。

## 仕組み

Gemma Bite は Flutter UI と Android ネイティブの Gemma 推論処理を組み合わせています。

1. ユーザーが食事写真を撮影、または1枚以上選択します。
2. Flutter から Android へ platform channel 経由で画像パスを渡します。
3. Android 側で Gemma 4 LiteRT-LM モデルを読み込み、オンデバイスでマルチモーダル推論します。
4. モデルは食事名、概要、栄養値、推定信頼度、追加確認事項を JSON で返します。
5. アプリは食事記録をローカルに保存し、プロフィールと合わせて AI相談に利用します。

```text
Flutter UI
  -> MethodChannel
  -> Android Kotlin
  -> LiteRT-LM Engine
  -> Gemma 4 E2B model
```

## 技術構成

- Flutter / Dart
- Android Kotlin platform channel
- Google AI Edge LiteRT-LM
- Gemma 4 E2B LiteRT-LM model
- Android Text-to-Speech
- ML Kit Japanese Text Recognition による栄養成分表OCR

## セットアップ

### 前提

- Flutter SDK
- Android Studio または Android SDK command-line tools
- Android 端末またはエミュレータ
- `adb`
- Gemma 4 LiteRT-LM の `.litertlm` モデルファイル

モデルファイルはこのリポジトリには含めません。別途ダウンロードし、モデル提供元のライセンスや利用条件に従ってください。

### モデルのダウンロード

Gemma Bite は LiteRT-LM 用の Gemma 4 E2B モデルで開発しています。

<https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm>

```bash
pip install huggingface_hub
huggingface-cli login
huggingface-cli download litert-community/gemma-4-E2B-it-litert-lm --local-dir ./models/gemma-4-E2B-it-litert-lm
```

### Android 端末へのモデル配置

```bash
adb shell mkdir -p /storage/emulated/0/Android/data/com.eyuras.gemma_bite/files/models
adb push ./models/gemma-4-E2B-it-litert-lm/gemma-4-E2B-it.litertlm /storage/emulated/0/Android/data/com.eyuras.gemma_bite/files/models/
```

モデル変更後に再最適化したい場合:

```bash
adb shell rm -f /storage/emulated/0/Android/data/com.eyuras.gemma_bite/files/models/*.xnnpack_cache_*
```

### 実行

```bash
flutter pub get
flutter run
```

特定の Android 端末で実行する場合:

```bash
flutter devices
flutter run -d <device-id>
```

APK をビルドする場合:

```bash
flutter build apk
```

## 現在の範囲

- オンデバイス Gemma 推論は Android を主対象にしています。
- iOS のプロジェクトファイルはありますが、iOS のネイティブ Gemma 推論処理は未実装です。
- 栄養値は推定であり、医療的な判断には使用しないでください。
- 読み上げ音声は Android 端末にインストールされているローカル音声に依存します。
- 通信が必要な TTS 音声は、オフライン寄りの体験を保つため表示しない方針です。

## リポジトリメモ

- 英語UIのスクリーンショットは `docs/images/en/` に置いています。
- 日本語UIのスクリーンショットは `docs/images/ja/` に置いています。
- モデルファイルはリポジトリに含めません。`models/` は Git 管理対象外です。
- ローカルで取得した `screenshot*.png` は Git 管理対象外です。
