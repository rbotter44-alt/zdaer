@echo off
REM Secure Flutter release build: Dart obfuscation + Android R8/ProGuard.
flutter clean
flutter pub get
flutter build apk --release --obfuscate --split-debug-info=build\symbols --tree-shake-icons --dart-define=APP_STRICT_SECURITY=true
pause
