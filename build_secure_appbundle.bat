@echo off
REM Google Play / AAB secure build.
flutter clean
flutter pub get
flutter build appbundle --release --obfuscate --split-debug-info=build\symbols --tree-shake-icons --dart-define=APP_STRICT_SECURITY=true
pause
