# R8 release rules for Proxy Dom.
#
# Keep only what the OS, Flutter or the gomobile JNI bridge reaches by name.
# Everything else — session state machines, ping monitors, traffic policies —
# is renamed and shrunk. Do not add a package-wide `com.proxydom.app.**` keep:
# that is exactly what makes a release APK readable.

# Flutter embedding and plugin registration are reached by class name from the
# engine and from GeneratedPluginRegistrant.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Android entry points named in AndroidManifest.xml. Their companions are
# reached from the same manifest-declared classes.
-keep class com.proxydom.app.MainActivity { *; }
-keep class com.proxydom.app.ProxyDomVpnService { *; }
-keep class com.proxydom.app.ProxyDomTileService { *; }
-keep class com.proxydom.app.VpnActionReceiver { *; }

# Kotlin object that owns the gomobile calls. It is small and sits on the JNI
# boundary; keep its method names so a bridge failure stays diagnosable.
-keep class com.proxydom.app.HysteriaBridge { *; }

# gomobile AAR: Java/ObjC bindings and go.Seq are called from native code by
# symbol, so R8 must not rename or remove them.
-keep class hy2bind.** { *; }
-keep class hy.** { *; }
-keep class go.** { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}

# Optional crypto providers referenced by tls packages; absent at runtime.
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**

# Flutter deferred components reference Play Core, which this app does not use.
-dontwarn com.google.android.play.core.**
