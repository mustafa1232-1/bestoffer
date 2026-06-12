import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val appKeyPropertiesFile = rootProject.file("key.properties")
val rootFallbackKeyPropertiesFile = rootProject.file("../../../android/key.properties")
val activeKeyPropertiesFile = when {
    appKeyPropertiesFile.exists() -> appKeyPropertiesFile
    rootFallbackKeyPropertiesFile.exists() -> rootFallbackKeyPropertiesFile
    else -> null
}
if (activeKeyPropertiesFile != null) {
    activeKeyPropertiesFile.inputStream().use(keystoreProperties::load)
}

fun propOrEnv(propKey: String, envKey: String): String? {
    val envValue = System.getenv(envKey)?.trim()
    if (!envValue.isNullOrEmpty()) return envValue
    val propValue = keystoreProperties.getProperty(propKey)?.trim()
    if (!propValue.isNullOrEmpty()) return propValue
    return null
}

val releaseStoreFilePath = propOrEnv("storeFile", "ANDROID_KEYSTORE_PATH")
val releaseStorePassword = propOrEnv("storePassword", "ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = propOrEnv("keyAlias", "ANDROID_KEY_ALIAS")
val releaseKeyPassword = propOrEnv("keyPassword", "ANDROID_KEY_PASSWORD")
val releaseStoreFileResolved = releaseStoreFilePath?.let { configuredPath ->
    val raw = configuredPath.trim()
    if (raw.isEmpty()) {
        null
    } else {
        val candidate = File(raw)
        if (candidate.isAbsolute) {
            candidate
        } else {
            val baseDir = activeKeyPropertiesFile?.parentFile ?: rootProject.projectDir
            File(baseDir, raw).normalize()
        }
    }
}
val hasReleaseSigning =
    releaseStoreFileResolved != null &&
        releaseStoreFileResolved.exists() &&
        !releaseStorePassword.isNullOrBlank() &&
        !releaseKeyAlias.isNullOrBlank() &&
        !releaseKeyPassword.isNullOrBlank()
val releaseTaskRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true) || it.contains("bundle", ignoreCase = true)
}

android {
    namespace = "com.maslaki.user"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.maslaki.user"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                storeFile = releaseStoreFileResolved
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                signingConfig = signingConfigs.getByName("debug")
                if (releaseTaskRequested) {
                    throw GradleException(
                        "Release signing is not configured for app_user. " +
                            "Provide apps/app_user/android/key.properties or root android/key.properties, " +
                            "or set ANDROID_KEYSTORE_PATH/ANDROID_KEYSTORE_PASSWORD/ANDROID_KEY_ALIAS/ANDROID_KEY_PASSWORD.",
                    )
                }
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
