@echo off
cd /d %~dp0
set PATH=%PATH%;C:\NuGet
set CL=/D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS
flutter clean
if exist build rmdir /s /q build
flutter pub get
flutter build windows --release
pause
