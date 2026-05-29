# Keep Flutter and Media3 classes needed at runtime
-keep class io.flutter.** { *; }
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**

# Flutter optional Play Store deferred-components classes.
# This app does not use Play deferred components, so R8 may ignore these optional references.
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
