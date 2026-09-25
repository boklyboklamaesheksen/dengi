import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

apply(from = rootProject.file("flutter-build-config.gradle"))

flutter {
    flutterVersionName = extra["rabochiyVersionName"] as String
    flutterVersionCode = extra["rabochiyVersionCode"].toString()
}

android {
    namespace = "app.rabochiy.vpn"
    compileSdk = 36
    // AGP 9.1 / Flutter 3.47 default; used only to strip and symbolize the prebuilt .so files.
    ndkVersion = "28.2.13676358"

    compileOptions {
        // Required by `coreLibraryDesugaring` for older Android API
        // levels using java.time / java.util.function APIs from the
        // vendored AmneziaWG sources.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        applicationId = "app.rabochiy.vpn"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Only ship ABIs supported by both VPN engines.
        ndk {
            abiFilters.clear()
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64")
            debugSymbolLevel = "FULL"
        }
    }
    
    // Правильная обработка native библиотек для AAB.
    // sshj (GW engine) pulls bouncycastle transitively; the bc*.jar files
    // ship duplicate OSGI manifests — without these excludes the release
    // merge fails with "4 files found with path META-INF/...".
    packaging {
        jniLibs {
            useLegacyPackaging = true  // Критично для VPN - извлекает .so файлы
        }
        resources {
            excludes += listOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt",
                "META-INF/versions/9/OSGI-INF/MANIFEST.MF",
                "META-INF/versions/9/OSGI-INF/*",
            )
        }
    }

    // Load signing config from android/key.properties if present.
    // See KEYSTORE_SETUP.md for how to generate a release keystore.
    val keystorePropertiesFile = rootProject.file("key.properties")
    val hasReleaseKeystore = keystorePropertiesFile.exists()
    val keystoreProperties = Properties().apply {
        if (hasReleaseKeystore) {
            load(FileInputStream(keystorePropertiesFile))
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                enableV1Signing = true
                enableV2Signing = true
            }
        }
    }

    buildTypes {
        debug {
            // Minification stays off (native engines + reflection-sensitive code)
            isMinifyEnabled = false
            isShrinkResources = false
        }
        release {
            // If no release keystore is configured, fall back to debug signing
            // so the build still completes (not distributable). This prevents
            // Gradle sync errors for fresh clones.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // JNI and reflective crypto keep rules are supplied by the modules.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )

            // Убираем отключение маппинга: теперь Crashlytics будет получать файл расшифровки
            // для Java/Kotlin кода (чтобы вместо a.b.c.d() видеть реальные имена функций).
            configure<com.google.firebase.crashlytics.buildtools.gradle.CrashlyticsExtension> {
                mappingFileUploadEnabled = true
                // Включаем поддержку загрузки символов для нативных библиотек C/C++
                nativeSymbolUploadEnabled = true
            }
        }
    }
    
    // Дополнительные настройки для корректной работы с AAB
    bundle {
        language {
            enableSplit = true
        }
        density {
            enableSplit = true
        }
        abi {
            enableSplit = true
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Firebase BoM — управляет совместимыми версиями Firebase SDK
    implementation(platform("com.google.firebase:firebase-bom:34.12.0"))
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-crashlytics")
    // Добавляем NDK для отслеживания крашей внутри нативных библиотек (.so)
    implementation("com.google.firebase:firebase-crashlytics-ndk")

    // Rabochiy VPN native engines ─────────────────────────────────────
    // AmneziaWG userspace tunnel: GoBackend + libwg-go.so.
    implementation(project(":amneziawg-tunnel"))
    implementation(project(":vlee_engine"))
    implementation(project(":hysteria2_engine"))
    // IKEv2 / StrongSwan was removed from the product; only AWG + GW
    // engines remain.

    // Coroutines used by the Kotlin VPN managers (AwgManager) glued
    // to Flutter via MethodChannel.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    // enableEdgeToEdge() in MainActivity (Play's Android 15 edge-to-edge check).
    implementation("androidx.activity:activity:1.12.4")
    // Java 8+ APIs used by the AmneziaWG sources on older devices
    // (we keep minSdk via Flutter, so desugaring is mandatory).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

flutter {
    source = "../.."
}

// Workaround for "Task 'wrapper' not found in project ':app'"
tasks.register("wrapper") {
    description = "Delegates wrapper task to root project"
    group = "Build Setup"
    dependsOn(rootProject.tasks.named("wrapper"))
}

// Workaround for "Task 'prepareKotlinBuildScriptModel' not found in project ':app'"
try {
    tasks.register("prepareKotlinBuildScriptModel") {
        // This is an empty task to satisfy the IDE sync if the plugin fails to register it
    }
} catch (e: Exception) {
    // Ignore if task already exists
}


