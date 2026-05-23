# GatiVani — Android ProGuard / R8 rules
#
# Used for --obfuscate release builds. Keep this conservative: aggressive
# stripping breaks Firebase reflection and Flutter platform channels.

# ----- Flutter --------------------------------------------------------------
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-keep class io.flutter.embedding.** { *; }

# ----- Kotlin coroutines ----------------------------------------------------
-keepclassmembers class kotlinx.coroutines.** { volatile <fields>; }
-dontwarn kotlinx.coroutines.**

# ----- Firebase -------------------------------------------------------------
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# Crashlytics: keep line numbers for readable stack traces
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# ----- just_audio / ExoPlayer ----------------------------------------------
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

# ----- google_ml_kit / tflite ----------------------------------------------
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.vision.** { *; }
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**

# ----- Drift / sqflite ------------------------------------------------------
-keep class androidx.sqlite.** { *; }
-keep class io.requery.android.database.** { *; }

# ----- workmanager ----------------------------------------------------------
-keep class androidx.work.** { *; }

# ----- Models with @JsonSerializable / Freezed -----------------------------
# Generated *.g.dart / *.freezed.dart code doesn't ship to JVM, but plugin
# bridges may reflect on these names.
-keep @kotlinx.serialization.Serializable class * { *; }

# ----- Misc -----------------------------------------------------------------
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
