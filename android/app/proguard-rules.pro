# R8 runs in FULL mode. Full mode does not implicitly keep default constructors,
# generic signatures or members of classes that are only reached by name, so every
# entry point Flutter, Pigeon, JNI or reflection reaches by name is pinned here.
# Plugin AARs (CameraX, Media3, Firebase, MLKit, WebRTC, FFmpegKit, Sentry, jni)
# ship their own consumer rules; these cover what they leave out.

# Flutter's generated registrar is reached by the embedding at runtime.
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Plugin classes are instantiated by GeneratedPluginRegistrant and register
# Pigeon/MethodChannel handlers by channel name. Full-mode class merging and
# member removal can silently drop those handlers ("Unable to establish
# connection on channel"), so plugin implementations are kept whole.
-keep class * implements io.flutter.embedding.engine.plugins.FlutterPlugin { *; }
-keep class * implements io.flutter.embedding.engine.plugins.activity.ActivityAware { *; }
-keep class * implements io.flutter.plugin.common.MethodChannel$MethodCallHandler { *; }
-keep class * implements io.flutter.plugin.common.EventChannel$StreamHandler { *; }
-keep class io.flutter.plugins.** { *; }
-keep class dev.flutter.pigeon.** { *; }
-keep class dev.fluttercommunity.plus.** { *; }
-keep class com.baseflow.** { *; }
-keep class io.livekit.plugin.** { *; }

# flutter_local_notifications persists scheduled notifications with Gson,
# which needs the model classes and their generic signatures intact.
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# JNI entry points and runtime annotations must retain their descriptors.
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}
-keepattributes *Annotation*,InnerClasses,EnclosingMethod

# Flutter references Play Core deferred components even when they are not used.
-dontwarn com.google.android.play.core.**
