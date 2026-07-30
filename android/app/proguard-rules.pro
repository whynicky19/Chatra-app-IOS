# ProGuard/R8 для релизной сборки.
#
# Flutter-движок и плагины активно используют рефлексию и JNI, поэтому их
# классы нельзя переименовывать — иначе приложение падает при старте уже
# после успешной сборки.

# --- Flutter ---
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# --- Firebase (Messaging + Crashlytics) ---
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Crashlytics: без исходных имён файлов и номеров строк стектрейсы
# нечитаемы даже после загрузки маппинга.
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# --- Desugaring (flutter_local_notifications) ---
-dontwarn java.time.**
-dontwarn javax.annotation.**

# --- flutter_local_notifications ---
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**
