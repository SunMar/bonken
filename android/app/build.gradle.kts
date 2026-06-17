import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin") // must be applied after the Android plugin
}

// Read upload-keystore credentials from android/key.properties when present.
// CI writes that file from secrets before running ./gradlew; locally the file
// is gitignored.  When absent we fall back to the debug keys so
// `flutter run --release` still works.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}
val hasReleaseSigning = keystorePropertiesFile.exists()

android {
    namespace = "org.suninet.bonken"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Application ID for the new Play Store listing (org.suninet.bonken).
        // The `legacy` flavor overrides this to com.suninet.bonken so both
        // listings can be built and published from the same repo.
        applicationId = "org.suninet.bonken"
        // Optional suffix + label override for parallel-installable side
        // builds (e.g. the `develop` branch APK).  Pass on the command
        // line:  ./gradlew … -PappIdSuffix=.develop -PappLabel="Bonken (test versie)"
        // When unset, the regular Play Store identity is used.
        val appIdSuffix = (project.findProperty("appIdSuffix") as String?).orEmpty()
        if (appIdSuffix.isNotEmpty()) {
            applicationIdSuffix = appIdSuffix
        }
        manifestPlaceholders["appLabel"] =
            (project.findProperty("appLabel") as String?) ?: "Bonken"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "edition"
    productFlavors {
        create("legacy") {
            dimension = "edition"
            applicationId = "com.suninet.bonken"
        }
        create("current") {
            dimension = "edition"
            // inherits org.suninet.bonken from defaultConfig
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                storeType = (keystoreProperties["storeType"] as String?) ?: "PKCS12"
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}
