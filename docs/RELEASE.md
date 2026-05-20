# Release Build Notes

This document is for maintainers preparing a GitHub Release. For user-facing
demo APK installation steps, see the main README.

## Build the Android APK

Build the release APK and rename the generated file before uploading it:

```bash
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk gemma-bite-v1.0.0.apk
shasum -a 256 gemma-bite-v1.0.0.apk > SHA256SUMS
```

This project currently signs the Android `release` build with the debug signing
config, so the APK is suitable for demos and manual testing, not Play Store
distribution.

## Recommended GitHub Release Assets

- `gemma-bite-v1.0.0.apk`
- `SHA256SUMS` (checksum file for APK)
- `README.md` and `README_JA.md`, or a short `INSTALL.md` / `INSTALL_JA.md`
  copied from the user-facing install instructions

Do not attach the Gemma `.litertlm` model file unless the model provider's
license and redistribution terms explicitly allow it.
