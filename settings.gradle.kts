pluginManagement {
    repositories {
        // 国内镜像放最前：本机直连 dl.google.com 会 TLS 中断，能命中镜像就不走直连；
        // 原仓库保留在后作为后备（镜像未同步的构件仍可回落直连）。
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
        google()
        mavenCentral()
    }
}
rootProject.name = "SunsetRipple"
include(":app")
