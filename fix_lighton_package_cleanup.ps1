$ErrorActionPreference = "Stop"
Write-Host "Cleaning old Kotlin package path..."
$oldPath = "android\app\src\main\kotlin\com\example\flutter_application_1"
if (Test-Path $oldPath) {
    Remove-Item -Recurse -Force $oldPath
    Write-Host "Deleted: $oldPath"
} else {
    Write-Host "Old path not found, OK."
}

$newPath = "android\app\src\main\kotlin\com\lighton\app"
if (!(Test-Path $newPath)) {
    throw "Missing new package path: $newPath. Copy the android folder from this zip into the project root first."
}

$gradleFile = "android\app\build.gradle.kts"
if (!(Test-Path $gradleFile)) {
    throw "Missing $gradleFile"
}

$text = Get-Content $gradleFile -Raw
if ($text -notmatch 'namespace\s*=\s*"com\.lighton\.app"') {
    throw "namespace is not com.lighton.app in $gradleFile"
}
if ($text -notmatch 'applicationId\s*=\s*"com\.lighton\.app"') {
    throw "applicationId is not com.lighton.app in $gradleFile"
}
if ($text -notmatch 'buildConfig\s*=\s*true') {
    throw "buildFeatures { buildConfig = true } is missing in $gradleFile"
}

Write-Host "Lighton package cleanup OK."
Write-Host "Now run: flutter clean; flutter pub get; flutter build apk --release --obfuscate --split-debug-info=build/symbols --tree-shake-icons --dart-define=APP_STRICT_SECURITY=true"
