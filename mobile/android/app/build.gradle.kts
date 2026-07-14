import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) {
        load(FileInputStream(f))
    }
}

// libbox.aar (sing-box JNI) declares minSdk 23; VpnService.Builder.establish
// also requires it. Flutter tooling rewrites the literal in defaultConfig back
// to flutter.minSdkVersion (21), so the real enforcement is finalizeDsl below.
val requiredMinSdk = 23

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
        // Placeholder only — finalizeDsl ниже поднимает до requiredMinSdk (23).
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

    // ABI splits — отдельные APK на архитектуру (Шаг 19).
    // Уменьшает размер APK на 60-70% (вместо 175 MB sing-box binaries — только нужный ABI).
    splits {
        abi {
            isEnable = true
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
// afterEvaluate override is too late for the manifest merger (CI failed with
// "minSdkVersion 21 cannot be smaller than 23 declared in libbox.aar").
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
    implementation(files("libs/libbox.aar"))
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
}
