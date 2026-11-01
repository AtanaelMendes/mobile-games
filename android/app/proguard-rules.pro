# MediaPipe builds protobuf options using reflection. R8 must preserve their
# fields (including platform_), even when it cannot see a direct Java access.
# Upstream workaround: https://github.com/google-ai-edge/mediapipe/issues/5514
-keep class com.google.mediapipe.proto.** { *; }
# Preserve the public task/image APIs shared with the release smoke test.
# Avoid keeping all framework Graph overloads: some reference optional protos
# that are intentionally absent from the prebuilt tasks-vision distribution.
-keep class com.google.mediapipe.tasks.** { *; }
-keep class com.google.mediapipe.framework.image.** { *; }
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite { *; }
-keep class com.google.common.flogger.** { *; }

# Shared by CameraX and AndroidJUnitRunner. Preserve this small API so release
# instrumentation can load it from the target APK instead of a merged class.
-keep class androidx.tracing.** { *; }

# The minified app and instrumentation share the Kotlin runtime. Prevent R8
# merging/removing entry points required by AndroidJUnitRunner in the test APK.
-keep class kotlin.** { *; }
