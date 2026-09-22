plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.brinklabs.mixoloco"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.brinklabs.mixoloco"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
