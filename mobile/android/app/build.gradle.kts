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

fun looksLikeKeystorePlaceholder(value: String?): Boolean {
    val v = value.orEmpty().trim()
    return v.isEmpty() || v.contains("YOUR_") || v.contains("PASSWORD_HERE")
}

// Production sideload / Play: real key.properties + JKS. CI and accidental
// `flutter build apk --release` without a keystore must NOT reuse the store
// package id — that caused INSTALL_FAILED_UPDATE_INCOMPATIBLE («Приложение
// не установлено») when a debug build occupied com.proxy.dom.
val releaseStoreFileRel = keystoreProperties.getProperty("storeFile").orEmpty()
val hasUsableReleaseKeystore =
    !looksLikeKeystorePlaceholder(keystoreProperties.getProperty("keyAlias")) &&
        !looksLikeKeystorePlaceholder(keystoreProperties.getProperty("keyPassword")) &&
        !looksLikeKeystorePlaceholder(keystoreProperties.getProperty("storePassword")) &&
        releaseStoreFileRel.isNotBlank() &&
        file(releaseStoreFileRel).isFile

// minSdk 26 — keep in sync with hysteria-bind / VpnService (do not roll back).
// may rewrite the literal in defaultConfig back to flutter.minSdkVersion, so
// the real enforcement is finalizeDsl below.
val requiredMinSdk = 26
val productionApplicationId = "com.proxy.dom"

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
        applicationId = productionApplicationId
        // Placeholder only — finalizeDsl ниже поднимает до requiredMinSdk (26).
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasUsableReleaseKeystore) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        getByName("release") {
            if (hasUsableReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                // CI / local without upload keystore: debug-signed. Package id
                // is set on the application variant below (not applicationIdSuffix:
                // Flutter 3.32–3.35 copies buildTypes onto library plugins).
                // Sideload to the site uses mobile/android/build-sideload.ps1.
                versionNameSuffix = "-ci"
                signingConfig = signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
        getByName("debug") {
            versionNameSuffix = "-debug"
        }
        getByName("profile") {
            versionNameSuffix = "-profile"
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

    // applicationId belongs on ApplicationVariant only. applicationIdSuffix on
    // buildTypes is copied by Flutter onto com.android.library plugins and
    // fails AGP ("Library projects cannot set applicationIdSuffix").
    onVariants(selector().withBuildType("debug")) { variant ->
        variant.applicationId.set("$productionApplicationId.debug")
    }
    onVariants(selector().withBuildType("profile")) { variant ->
        variant.applicationId.set("$productionApplicationId.profile")
    }
    onVariants(selector().withBuildType("release")) { variant ->
        if (!hasUsableReleaseKeystore) {
            variant.applicationId.set("$productionApplicationId.ci")
        }
    }
}

dependencies {
    // Official Hy2 AAR (`hysteria-bind/build-aar.sh`). VLESS Reality runs
    // inside this binary via xtls/xray-core. Do not also link libs/libXray.aar.
    val hy2Aar = file("libs/hysteria-client.aar")
    if (hy2Aar.exists()) {
        implementation(files(hy2Aar))
    }
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("androidx.core:core-ktx:1.15.0")
    // Edge-to-edge (enableEdgeToEdge) for Android 15 system-bar insets.
    implementation("androidx.activity:activity:1.10.1")
    implementation("androidx.activity:activity-ktx:1.10.1")
    testImplementation("junit:junit:4.13.2")
}
