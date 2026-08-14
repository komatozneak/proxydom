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

# libXray JNI (Xray-core via gomobile) — ADR 005
-keep class libXray.** { *; }
-keep class go.** { *; }

# Hy2 gomobile AAR (namespaced off libXray's go.Seq / libgojni.so)
-keep class hy2bind.** { *; }
-keep class hy.** { *; }

# TrustTunnel native client — ADR 006
-keep class com.adguard.trusttunnel.** { *; }
-keep class ch.qos.** { *; }
-keep class org.slf4j.** { *; }
-keepattributes *Annotation*
-dontwarn ch.qos.logback.core.net.*

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
