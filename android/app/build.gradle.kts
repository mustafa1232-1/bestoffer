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

data class FlavorConfig(
    val applicationId: String,
    val appLabel: String,
    val deepLinkScheme: String,
)

val flavorConfigs =
    mapOf(
        "user" to FlavorConfig("com.maslaki.user", "مسلكي", "maslaki-user"),
        "delivery" to FlavorConfig("com.maslaki.delivery", "مسلكي دلفري", "maslaki-delivery"),
        "captain" to FlavorConfig("com.maslaki.captain", "مسلكي كابتن", "maslaki-captain"),
        "store" to FlavorConfig("com.maslaki.store", "متجر مسلكي", "maslaki-store"),
        "company" to FlavorConfig("com.maslaki.company", "شركات مسلكي", "maslaki-company"),
        "pharmacy" to FlavorConfig("com.maslaki.pharmacy", "صيدلية مسلكي", "maslaki-pharmacy"),
    )

fun requestedFlavorName(): String {
    val explicit =
        (project.findProperty("APP_FLAVOR") as String?)
            ?.trim()
            ?.lowercase()
            ?.takeIf { it in flavorConfigs.keys }
    if (explicit != null) return explicit

    val taskNames = gradle.startParameter.taskNames.map { it.lowercase() }
    for (flavor in flavorConfigs.keys) {
        if (taskNames.any { task -> task.contains(flavor) }) {
            return flavor
        }
    }
    return "user"
}

val requestedFlavorConfig = flavorConfigs.getValue(requestedFlavorName())
val hasConfiguredFirebaseClient =
    googleServicesJsonText.contains("\"package_name\": \"${requestedFlavorConfig.applicationId}\"")

if (hasConfiguredFirebaseClient) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.lifecycle(
        "Skipping Google Services plugin for applicationId=${requestedFlavorConfig.applicationId}; no matching client in google-services.json.",
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
        minSdk = flutter.minSdkVersion
        targetSdk = maxOf(flutter.targetSdkVersion, 35)
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = flavorConfigs.getValue("user").appLabel
        manifestPlaceholders["deepLinkScheme"] = flavorConfigs.getValue("user").deepLinkScheme
    }

    flavorDimensions += "app"

    productFlavors {
        flavorConfigs.forEach { (name, config) ->
            create(name) {
                dimension = "app"
                applicationId = config.applicationId
                manifestPlaceholders["appLabel"] = config.appLabel
                manifestPlaceholders["deepLinkScheme"] = config.deepLinkScheme
            }
        }
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
            // R8/code-shrinking is intentionally DISABLED for now.
            //
            // The previous internal-testing build had minify+shrink ON with
            // incomplete keep rules, so R8 stripped native plugin code that is
            // only referenced from Dart over method channels (mlkit face
            // detection, video_player/ExoPlayer, geolocator, permission_handler,
            // image_picker). That broke camera, reels, location and gallery in
            // release while debug (no minify) worked — the exact reported bug.
            //
            // Dart code is AOT-compiled and does not need R8, so disabling it
            // yields a 100%-reliable build for internal testing at the cost of a
            // slightly larger APK. proguard-rules.pro now ALSO carries the full
            // keep rules, so minify can be re-enabled later by flipping these
            // two flags back to true once a shrunk build is verified on-device.
            isMinifyEnabled = false
            isShrinkResources = false
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
