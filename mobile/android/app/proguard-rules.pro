# Flutter wrapper (Шаг 19)
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# VpnService (Шаг 11)
-keep class android.net.VpnService { *; }
-keep class com.teremok.connect.teremok_connect.** { *; }

# Sing-box native binary (Шаг 14) — НЕ трогаем через ProGuard,
# т.к. binary вызывается через ProcessBuilder, а не через JNI classes.
# Но keep-правило ниже не помешает на случай если кто-то добавит JNI wrapper.
-keep class sing.box.** { *; }

# JSON serialization annotations (для будущих моделей)
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Suppress warnings от optional dependencies
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.

# Flutter deferred components / split install (Шаг 19)
# Flutter ссылается на Play Core classes, но мы не используем
# deferred components — просто игнорируем через -dontwarn.
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }