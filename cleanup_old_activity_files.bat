@echo off
set BASE=android\app\src\main\kotlin\com\example\flutter_application_1

if exist "%BASE%\LightOnActivity.kt" del /f "%BASE%\LightOnActivity.kt"
if exist "%BASE%\AnimeActivity.kt" del /f "%BASE%\AnimeActivity.kt"
if exist "%BASE%\EgyActivity.kt" del /f "%BASE%\EgyActivity.kt"
if exist "%BASE%\ArabActivity.kt" del /f "%BASE%\ArabActivity.kt"

echo Deleted old Activity files if they existed.
echo.
echo Now run:
echo flutter clean
echo flutter pub get
echo flutter run
pause
