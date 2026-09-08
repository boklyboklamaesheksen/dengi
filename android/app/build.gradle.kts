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

android {
    namespace = "app.rabochiy.vpn"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        // Required by `coreLibraryDesugaring` for older Android API
        // levels using java.time / java.util.function APIs from the
        // vendored StrongSwan + AmneziaWG sources.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        // StrongSwan sources read app metadata via BuildConfig.
        buildConfig = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "app.rabochiy.vpn"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion // Lowered for better compatibility
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"

        // Явно указываем архитектуры для native библиотек V2Ray
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
            // Disable minification like GW VPN - strongSwan plugins break with ProGuard
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
            // Minification with ProGuard rules required for V2Ray native classes
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

dependencies {
    // Заменяем устаревший Play Core на новые разделенные библиотеки
    implementation("com.google.android.play:feature-delivery:2.1.0")
    implementation("com.google.android.play:asset-delivery:2.2.2")
    implementation("com.google.android.play:app-update:2.1.0")
    implementation("com.google.android.play:review:2.0.1")

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
    // StrongSwan IKEv2 sources live directly under
    // `app/src/main/java/org/strongswan/android/**`; the matching
    // .so files (libcharon.so, libstrongswan.so …) sit in
    // `app/src/main/jniLibs/**` so no extra `implementation` is
    // needed for IKEv2.

    // Coroutines used by the Kotlin VPN managers (IkeV2Manager /
    // AwgManager) glued to Flutter via MethodChannel.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    // Java 8+ APIs used by StrongSwan / AmneziaWG sources on
    // older devices (we keep minSdk via Flutter, so desugaring is
    // mandatory).
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


