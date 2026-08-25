import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 发布签名从 android/key.properties 读取（该文件不入库）。格式：
//   storeFile=../keystore/sunsetripple.jks   # 相对 android/app/ 或绝对路径
//   storePassword=...
//   keyAlias=...
//   keyPassword=...
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}
val hasReleaseSigning = keystorePropertiesFile.exists()

android {
    // 必须与线上已发布版本一致，否则装不上去覆盖升级。
    namespace = "host.msknet.sunsetripple"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "host.msknet.sunsetripple"
        // 项目基线是 26；不要用 flutter.minSdkVersion，它会随 Flutter 版本漂移。
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++17"
            }
        }
        ndk {
            // 只出真机会用到的 ABI，x86 模拟器保留 x86_64。
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    // native/ 下的 C++（无锁环形缓冲、PCM 混音、帧编解码）此前从未接入构建，
    // 所以 libsunset_ripple_native.so 根本不存在，FFI 每次都静默回退到纯 Dart。
    externalNativeBuild {
        cmake {
            path = file("../../native/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
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
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "[sunsetripple] 未找到 android/key.properties，release 包将使用 debug 签名，" +
                        "只能自测，不能发布。"
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Opus 编解码。纯 JVM 实现，不需要额外的 .so。
    // 版本与已发布的 Kotlin 版 alpha.7 一致，保证两版音频互通。
    implementation("io.github.jaredmdobson:concentus:1.0.2")
}
