import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services") apply false
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use(keystoreProperties::load)
}

fun propOrEnv(propKey: String, envKey: String): String? {
    val propValue = keystoreProperties.getProperty(propKey)?.trim()
    if (!propValue.isNullOrEmpty()) return propValue
    val envValue = System.getenv(envKey)?.trim()
    if (!envValue.isNullOrEmpty()) return envValue
    return null
}

val releaseStoreFilePath = propOrEnv("storeFile", "ANDROID_KEYSTORE_PATH")
val releaseStorePassword = propOrEnv("storePassword", "ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = propOrEnv("keyAlias", "ANDROID_KEY_ALIAS")
val releaseKeyPassword = propOrEnv("keyPassword", "ANDROID_KEY_PASSWORD")

val hasReleaseSigning =
    !releaseStoreFilePath.isNullOrBlank() &&
        !releaseStorePassword.isNullOrBlank() &&
        !releaseKeyAlias.isNullOrBlank() &&
        !releaseKeyPassword.isNullOrBlank()

val releaseTaskRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true) || it.contains("bundle", ignoreCase = true)
}

val googleServicesJsonFile = project.file("google-services.json")
val googleServicesJsonText = if (googleServicesJsonFile.exists()) {
    googleServicesJsonFile.readText()
} else {
    ""
}
val configuredApplicationId =
    (project.findProperty("APP_ID") as String?)
        ?.trim()
        ?.takeIf { it.isNotEmpty() }
        ?: "com.maslaki.user"

val configuredAppLabel =
    (project.findProperty("APP_LABEL") as String?)
        ?.trim()
        ?.takeIf { it.isNotEmpty() }
val effectiveAppLabel = configuredAppLabel ?: "Maslaki"

val hasConfiguredFirebaseClient =
    googleServicesJsonText.contains("\"package_name\": \"$configuredApplicationId\"")

if (hasConfiguredFirebaseClient) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.lifecycle(
        "Skipping Google Services plugin for applicationId=$configuredApplicationId; no matching client in google-services.json.",
    )
}

android {
    // Root mobile surface is the user app only.
    namespace = "com.maslaki.user"
    compileSdk = maxOf(flutter.compileSdkVersion, 35)
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
        applicationId = configuredApplicationId
        minSdk = flutter.minSdkVersion
        targetSdk = maxOf(flutter.targetSdkVersion, 35)
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = effectiveAppLabel
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                storeFile = file(releaseStoreFilePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        debug {
            manifestPlaceholders["usesCleartextTraffic"] = "true"
        }
        release {
            manifestPlaceholders["usesCleartextTraffic"] = "false"
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                // Keep local non-release workflows running, but block real release packaging.
                signingConfig = signingConfigs.getByName("debug")
                if (releaseTaskRequested) {
                    throw GradleException(
                        "Release signing is not configured. Create android/key.properties " +
                            "or set env vars: ANDROID_KEYSTORE_PATH, ANDROID_KEYSTORE_PASSWORD, " +
                            "ANDROID_KEY_ALIAS, ANDROID_KEY_PASSWORD.",
                    )
                }
                logger.warn(
                    "Release signing not configured yet. Debug key is used only for non-release tasks.",
                )
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
