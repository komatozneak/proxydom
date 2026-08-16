import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Invalid stub flutter_build.d (no ": ") crashes FlutterTaskHelper.readDependencies.
run {
    val dep = file("${rootProject.projectDir}/../build/app/intermediates/flutter/debug/flutter_build.d")
    if (dep.exists()) {
        val text = runCatching { dep.readText() }.getOrElse { "" }
        if (!text.contains(": ")) {
            dep.delete()
        }
    }
}

val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) {
        load(FileInputStream(f))
    }
}

// TrustTunnel adapter + libXray require minSdk 26 (ADR 006). Flutter tooling
// may rewrite the literal in defaultConfig back to flutter.minSdkVersion, so
// the real enforcement is finalizeDsl below.
val requiredMinSdk = 26

android {
    namespace = "com.teremok.connect.teremok_connect"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.teremok.connect.teremok_connect"
        // Placeholder only — finalizeDsl ниже поднимает до requiredMinSdk (26).
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (!keystoreProperties.isEmpty) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        getByName("release") {
            // Если key.properties настроен — подписываем release keystore.
            // Иначе fallback на debug (dev/CI only, НЕ для Play Store).
            signingConfig = if (!keystoreProperties.isEmpty) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
        getByName("debug") {
            // debug уже настроен
        }
    }

    // ABI splits — только для `flutter build apk`, не для app bundle (Play).
    // AGP/R8: bundle + splits → "Multiple shrunk-resources files found" (issuetracker 402800800).
    splits {
        abi {
            isEnable = gradle.startParameter.taskNames.none {
                it.contains("bundle", ignoreCase = true)
            }
            reset()
            include("arm64-v8a", "armeabi-v7a", "x86_64")
            isUniversalApk = true
        }
    }
}

flutter {
    source = "../.."
}

// AGP 8 locks the android DSL right after project evaluation, so a plain
// afterEvaluate override is too late for the manifest merger.
// finalizeDsl is the AGP-sanctioned last-write hook and survives Flutter's
// build.gradle.kts rewrites because it never touches the literal above.
androidComponents {
    finalizeDsl { extension ->
        val current = extension.defaultConfig.minSdk ?: 0
        if (current < requiredMinSdk) {
            extension.defaultConfig.minSdk = requiredMinSdk
        }
    }
}

dependencies {
    // Xray-core via libXray (gomobile). Replaces libbox/sing-box — ADR 005.
    implementation(files("libs/libXray.aar"))
    // TrustTunnel client adapter (ADR 006 dual-core). Vendored AAR — fetch via
    // mobile/scripts/fetch-trusttunnel-aar.ps1 (GitHub Packages, needs GPR_KEY).
    // Transitive deps below mirror the adapter's lib/build.gradle.kts because
    // a raw AAR carries no POM.
    implementation(files("libs/trusttunnel-client-android.aar"))
    // Official Hy2 AAR (optional until `hysteria-bind/build-aar.sh` runs).
    val hy2Aar = file("libs/hysteria-client.aar")
    if (hy2Aar.exists()) {
        implementation(files(hy2Aar))
    }
    implementation("com.akuleshov7:ktoml-core:0.7.0")
    implementation("org.slf4j:slf4j-api:1.7.25")
    implementation("com.github.tony19:logback-android:2.0.0")
    implementation("io.reactivex.rxjava3:rxandroid:3.0.0")
    implementation("io.reactivex.rxjava3:rxjava:3.1.8")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("androidx.core:core-ktx:1.15.0")
    // EdgeToEdge.enable for MainActivity (Android 15 system-bar insets).
    implementation("androidx.activity:activity-ktx:1.10.1")
    testImplementation("junit:junit:4.13.2")
}
