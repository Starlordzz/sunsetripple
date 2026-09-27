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

/// CI 上宁可让构建直接失败，也不能产出 debug 签名的「正式包」：
/// 每个 runner 的 debug keystore 都不同，用户会 INSTALL_FAILED_UPDATE_INCOMPATIBLE，
/// 只能卸载重装——那是比构建失败严重得多的发布事故。
/// 本地自测想要 debug 签名时显式传 -PallowDebugSigning=true。
val allowDebugSigning = providers.gradleProperty("allowDebugSigning")
    .map { it.equals("true", ignoreCase = true) }
    .getOrElse(false)

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
            } else if (allowDebugSigning) {
                logger.warn(
                    "[sunsetripple] -PallowDebugSigning=true：本次 release 包使用 debug 签名，仅限本地自测。"
                )
                signingConfigs.getByName("debug")
            } else {
                null
            }
        }
    }
}

// 没有签名材料时不产出 release 产物，而是直接失败并给出修复指令。
afterEvaluate {
    val releaseTasks = tasks.matching { it.name.startsWith("assembleRelease") }
    releaseTasks.configureEach {
        doFirst {
            if (!hasReleaseSigning && !allowDebugSigning) {
                throw GradleException(
                    """
                    缺少发布签名材料：找不到 ${keystorePropertiesFile.path}

                    修复方式（三选一）：
                      1) 本地运行 bash scripts/setup-release-signing.sh 生成并写入 android/key.properties
                      2) CI 上配置 ANDROID_KEYSTORE_BASE64 / ANDROID_KEYSTORE_PASSWORD /
                         ANDROID_KEY_ALIAS / ANDROID_KEY_PASSWORD 四个 repository secret
                         （release.yml 会自动还原）
                      3) 仅本地自测、明确接受不可发布的包：加 -PallowDebugSigning=true
                    """.trimIndent()
                )
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
