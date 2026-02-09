# Keep TensorFlow Lite classes
-keep class org.tensorflow.lite.** { *; }
-keep class org.tensorflow.lite.gpu.** { *; }

# Keep Google ML Kit classes
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_common.** { *; }

# Ignore warnings from missing classes (fixes your specific error)
-dontwarn org.tensorflow.lite.gpu.**