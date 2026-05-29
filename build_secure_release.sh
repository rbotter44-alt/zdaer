#!/usr/bin/env bash
set -e
flutter clean
flutter pub get
flutter build apk --release --obfuscate --split-debug-info=build/symbols --tree-shake-icons --dart-define=APP_STRICT_SECURITY=true
