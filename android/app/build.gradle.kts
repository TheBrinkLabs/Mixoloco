import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Release signing — reuses the same shared BrinkLabs upload keystore as
// Capitle (see android/key.properties, gitignored — never committed).
// Falls back to nothing / build fails loudly if that file is missing
// rather than silently signing a release build with debug keys, which
// Play Store would reject anyway.
val keyProperties = Properties()
val keyPropertiesFile = rootProject.file("key.properties")
if (keyPropertiesFile.exists()) {
    keyPropertiesFile.inputStream().use { keyProperties.load(it) }
}

android {
    namespace = "com.brinklabs.mixoloco"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        create("release") {
            keyAlias = keyProperties["keyAlias"].toString()
            keyPassword = keyProperties["keyPassword"].toString()
            storeFile = file(keyProperties["storeFile"].toString())
            storePassword = keyProperties["storePassword"].toString()
        }
    }

    defaultConfig {
        applicationId = "com.brinklabs.mixoloco"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Unity Ads — the one network behind Unity LevelPlay mediation that
    // needs no separate account (LevelPlay itself is a Unity product).
    // Exact SDK/adapter version pairing per Unity's own published
    // versions.json for this adapter release — same pairing already
    // proven working in Capitle. Add Vungle/Meta/Mintegral adapters here
    // later the same way if those accounts get set up for Mixoloco too
    // (see Capitle's own build.gradle.kts for that exact pattern).
    implementation("com.unity3d.ads:unity-ads:4.20.0")
    implementation("com.unity3d.ads-mediation:unityads-adapter:5.12.0")
}

flutter {
    source = "../.."
}
