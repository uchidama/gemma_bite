# Release 作成メモ

このドキュメントは GitHub Release を作成するメンテナー向けです。
デモAPKのインストール手順はREADMEを参照してください。

## Android APKをビルド

Release 用 APK をビルドし、アップロード前にファイル名を変更します。

```bash
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk gemma-bite-v1.0.0.apk
shasum -a 256 gemma-bite-v1.0.0.apk > SHA256SUMS
```

現在の Android `release` ビルドは debug signing config で署名しています。
そのため、この APK はデモや手動テスト向けであり、Play Store 配布向けではありません。

## GitHub Release に同梱推奨のファイル

- `gemma-bite-v1.0.0.apk`
- `SHA256SUMS`（APKのチェックサム）
- `README.md` と `README_JA.md`、またはREADMEのインストール手順を抜き出した
  短い `INSTALL.md` / `INSTALL_JA.md`

Gemma の `.litertlm` モデルファイルは、モデル提供元のライセンスや再配布条件で
明示的に許可されている場合を除き、GitHub Release には添付しないでください。
