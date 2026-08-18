import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("androidx.baselineprofile")
}

val releaseSigningPropertiesPath =
    providers.gradleProperty("sunsetRipple.signingProperties").orNull ?: "keystore.properties"
val releaseSigningFile = rootProject.file(releaseSigningPropertiesPath)
val releaseSigningProperties = Properties().apply {
    if (releaseSigningFile.isFile) {
        releaseSigningFile.inputStream().use { load(it) }
    }
}
val releaseSigningKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val missingReleaseSigningKeys = releaseSigningKeys.filter {
    releaseSigningProperties.getProperty(it).isNullOrBlank()
}
val releaseSigningReady = releaseSigningFile.isFile && missingReleaseSigningKeys.isEmpty()
val updateManifestUrl = providers.gradleProperty("sunsetRipple.updateManifestUrl")
    .orElse("https://github.com/Starlordzz/sunsetripple/releases/latest/download/update.json")
    .get()
val updatePublicKey = providers.gradleProperty("sunsetRipple.updatePublicKey").orElse("").get()

fun buildConfigString(value: String): String = "\"${value.replace("\\", "\\\\").replace("\"", "\\\"")}\""

fun releaseSigningValue(key: String): String = releaseSigningProperties.getProperty(key).trim()

android {
    namespace = "host.msknet.sunsetripple"
    compileSdk = 35

    defaultConfig {
        applicationId = "host.msknet.sunsetripple"
        minSdk = 26
        targetSdk = 35
        versionName = "0.1.0-alpha.5"
        versionCode = 6
        buildConfigField("String", "UPDATE_MANIFEST_URL", buildConfigString(updateManifestUrl))
        buildConfigField("String", "UPDATE_PUBLIC_KEY", buildConfigString(updatePublicKey))
    }
    signingConfigs {
        if (releaseSigningReady) {
            create("release") {
                storeFile = rootProject.file(releaseSigningValue("storeFile"))
                storePassword = releaseSigningValue("storePassword")
                keyAlias = releaseSigningValue("keyAlias")
                keyPassword = releaseSigningValue("keyPassword")
            }
        }
    }
    buildTypes {
        getByName("release") {
            isDebuggable = false
            isMinifyEnabled = false
            signingConfig = signingConfigs.findByName("release")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

val verifyReleaseSigning by tasks.registering {
    group = "verification"
    description = "Fails release packaging when signing credentials are incomplete."
    doLast {
        check(releaseSigningFile.isFile) {
            "缺少本地发布签名配置：${releaseSigningFile.absolutePath}。"
        }
        check(missingReleaseSigningKeys.isEmpty()) {
            "发布签名配置缺少字段：${missingReleaseSigningKeys.joinToString()}"
        }
        val storePath = rootProject.file(releaseSigningValue("storeFile"))
        check(storePath.isFile) {
            "发布密钥文件不存在：${storePath.absolutePath}"
        }
    }
}

tasks.matching { it.name == "packageRelease" || it.name == "bundleRelease" }.configureEach {
    dependsOn(verifyReleaseSigning)
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.09.00"))
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("io.github.jaredmdobson:concentus:1.0.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.5")
    implementation("com.google.android.gms:play-services-nearby:19.3.0")
    baselineProfile(project(":benchmark"))
    testImplementation("junit:junit:4.13.2")
}
