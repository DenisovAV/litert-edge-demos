import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (git-ignored) points at a keystore kept outside the repo.
// storeFile may be absolute, or relative to android/app/ (it goes through this module's file()).
//
// Without key.properties a release build FAILS: a debug-signed APK handed to testers could never
// be updated by a properly signed one. To sign a local release build with the debug key anyway
// (never for testers), pass the Gradle property allowDebugSigning=true:
//   fvm flutter run --release -P allowDebugSigning=true
//   fvm flutter build apk --release -P allowDebugSigning=true
// (or ORG_GRADLE_PROJECT_allowDebugSigning=true in the environment). Debug builds are unaffected.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null
val allowDebugSigning = (findProperty("allowDebugSigning") as String?)?.toBoolean() == true

android {
    namespace = "dev.fluttergemma.litert_hackathon"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications (via flutter_edge_ai_agent) needs java.time desugaring.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.fluttergemma.litert_hackathon"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // .litertlm (LLM, embeddings, speech) fails to load at runtime below API 30.
        minSdk = 30
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        // LiteRT-LM ships arm64-v8a only. Replace, don't append: the Flutter Gradle plugin
        // has already filled abiFilters with every Flutter ABI (FlutterPlugin.configureAbiWithoutSplits).
        ndk {
            abiFilters.clear()
            abiFilters += "arm64-v8a"
        }
    }

    // The built-in models stay uncompressed in the APK: the detector is read
    // as one buffer, the embedder streamed out once (docs/design/
    // distribution.md, "Bundled models"). Deflating them saves little and
    // costs a full inflate on every read.
    androidResources {
        noCompress += listOf("tflite", "model")
    }

    // Firebase Test Lab runs the integration tests on a PROFILE build
    // (tool/run_android_check_ftl.sh): Flutter leaves dev-dependency plugins, integration_test
    // included, out of release builds. The test APK must target the app's build type:
    //   ./gradlew app:assembleAndroidTest -PtestBuildType=profile
    testBuildType = (findProperty("testBuildType") as String?) ?: "debug"

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = when {
                hasReleaseKey -> signingConfigs.getByName("release")
                allowDebugSigning -> signingConfigs.getByName("debug")
                // Unsigned until the check below stops the build.
                else -> null
            }
        }
    }
}

// Fails a release build without the key (at execution, so configuring or building debug is
// unaffected). preReleaseBuild runs first in every release variant's task graph.
tasks.configureEach {
    if (name == "preReleaseBuild") {
        doFirst {
            if (!hasReleaseKey && !allowDebugSigning) {
                throw GradleException(
                    "Release signing: android/key.properties is missing (see the comment at the top " +
                        "of android/app/build.gradle.kts). Restore it, or pass " +
                        "-P allowDebugSigning=true for a local debug-signed build (never for testers).",
                )
            }
            if (!hasReleaseKey) {
                logger.warn("allowDebugSigning=true: signing the release build with the DEBUG key")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
