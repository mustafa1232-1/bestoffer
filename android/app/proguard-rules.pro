# Flutter engine and embedding classes are invoked from Dart via message
# channels rather than direct Java references, so R8 sees them as unused and
# strips/renames them unless explicitly kept. That breaks platform channels
# (e.g. path_provider) only in release builds, since debug skips minification.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.embedding.**

# Pigeon-generated plugin APIs (path_provider, etc.) and their message codecs.
-keep class * extends io.flutter.plugin.common.StandardMessageCodec { *; }
-keepclassmembers class * {
    @io.flutter.plugin.common.* *;
}

# ============================================================================
# Plugin keep rules. NOTE: release currently builds with minify DISABLED (see
# android/app/build.gradle.kts), so these are not strictly required today, but
# are kept complete so code-shrinking can be safely re-enabled later without
# reintroducing the release-only camera/reels/location/gallery breakage.
# ============================================================================

# --- camera ---
-keep class io.flutter.plugins.camera.** { *; }
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**

# --- image_picker / file_picker (AndroidX ActivityResult + delegates) ---
-keep class io.flutter.plugins.imagepicker.** { *; }
-keep class com.mr0xf00.** { *; }
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-keep class androidx.activity.result.** { *; }
-keep class androidx.core.content.FileProvider { *; }

# --- geolocator / location ---
-keep class com.baseflow.geolocator.** { *; }
-keep class com.baseflow.permissionhandler.** { *; }
-keep class com.lyokone.location.** { *; }

# --- video_player (ExoPlayer / media3) for reels ---
-keep class io.flutter.plugins.videoplayer.** { *; }
-keep class androidx.media3.** { *; }
-keep interface androidx.media3.** { *; }
-dontwarn androidx.media3.**
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

# --- google_mlkit_face_detection (reflection + native model loading) ---
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }
-dontwarn com.google.mlkit.**
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_face_detection.** { *; }

# --- Firebase / FCM ---
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# --- ffmpeg_kit (story/reel export) ---
-keep class com.arthenica.** { *; }
-dontwarn com.arthenica.**

# --- Play Core (Flutter deferred components references these even if unused) ---
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Keep annotations + enums used reflectively by the plugins above.
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
