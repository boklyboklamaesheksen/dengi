plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

// Slimmed-down port of the vyom-tun-sdk module: VLEE only needs the
// hev-socks5-tunnel JNI bridge (TProxyService + libhev-socks5-tunnel.so).
// The heavy hysteria2/xray cmake build is intentionally not carried over.
android {
    namespace = "io.github.vyomtunnel.sdk"
    compileSdk = 36

    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }
}

dependencies {
    implementation("org.jetbrains.kotlin:kotlin-stdlib")
    implementation("androidx.core:core-ktx:1.13.1")
}
