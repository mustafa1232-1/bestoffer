# Flutter's generated registrar is reached by the embedding at runtime.
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Keep plugin constructors used by generated registration while allowing R8 to
# optimize and rename the rest of each plugin. CameraX, Media3, Firebase and
# MLKit supply consumer rules in their own Android artifacts.
-keep,allowoptimization,allowobfuscation class * implements io.flutter.embedding.engine.plugins.FlutterPlugin {
    public <init>();
}

# JNI entry points and runtime annotations must retain their descriptors.
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# Flutter references Play Core deferred components even when they are not used.
-dontwarn com.google.android.play.core.**
