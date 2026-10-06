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
    // proven working in Capitle.
    implementation("com.unity3d.ads:unity-ads:4.20.0")
    implementation("com.unity3d.ads-mediation:unityads-adapter:5.12.0")

    // Vungle (Liftoff Monetize) — mediated through LevelPlay (see the
    // unity_levelplay_mediation Flutter plugin) rather than called
    // directly. Same exact SDK/adapter version pairing as Capitle
    // (7.7.8/5.14.0 — the vungle-adapter's own versions.json requirement;
    // an older pairing caused a real runtime class-resolution failure
    // there, silently preventing Vungle from ever initializing through
    // LevelPlay even though "no fill" was the visible symptom).
    implementation("com.vungle:vungle-ads:7.7.8")
    implementation("com.unity3d.ads-mediation:vungle-adapter:5.14.0")

    // Meta Audience Network — mediated through LevelPlay, same as Vungle
    // above. Linked as a network instance under all 4 ad units in the
    // LevelPlay dashboard — same SDK version already proven working in
    // Capitle.
    implementation("com.facebook.android:audience-network-sdk:6.22.0")
    implementation("com.unity3d.ads-mediation:facebook-adapter:5.4.0")

    // Mintegral — not set up for Mixoloco (no account), unlike Capitle.
    // Add back the same way as Vungle/Meta above if that ever changes —
    // see this file's own git history for the exact dependency lines and
    // the Maven repo entry it needs in the root build.gradle.kts.
}

flutter {
    source = "../.."
}
