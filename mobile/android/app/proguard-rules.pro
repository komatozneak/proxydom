# Flutter wrapper (Шаг 19)
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# VpnService (Шаг 11)
-keep class android.net.VpnService { *; }
-keep class com.proxydom.app.** { *; }

# Hy2 gomobile AAR
-keep class hy2bind.** { *; }
-keep class hy.** { *; }

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
