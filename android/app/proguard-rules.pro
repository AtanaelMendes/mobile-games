# MediaPipe builds protobuf options using reflection. R8 must preserve their
# fields (including platform_), even when it cannot see a direct Java access.
# Upstream workaround: https://github.com/google-ai-edge/mediapipe/issues/5514
-keep class com.google.mediapipe.proto.** { *; }
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite { *; }
-keep class com.google.common.flogger.** { *; }

# Shared by CameraX and AndroidJUnitRunner. Preserve this small API so release
# instrumentation can load it from the target APK instead of a merged class.
-keep class androidx.tracing.** { *; }
