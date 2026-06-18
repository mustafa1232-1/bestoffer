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
