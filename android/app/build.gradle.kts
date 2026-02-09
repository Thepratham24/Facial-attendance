plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.face_attendance"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.untitled" // Or whatever your ID is
        // You can update the 'hello world' text below to update the 'applicationId' for specific build variants.
        // applicationIdSuffix = ".dev"

        minSdk = 26 // <--- NOTICE THE BRACKETS HERE
        targetSdkVersion(flutter.targetSdkVersion)
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    buildTypes {
        release {
            // Updated syntax for Kotlin (.kts)
            isMinifyEnabled = true
            isShrinkResources = true

            // This line fixes the 'signingConfigs' error
            signingConfig = signingConfigs.getByName("debug")

            // This line fixes the 'proguardFiles' error
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    aaptOptions {
        noCompress.addAll(listOf("tflite", "lite"))
    }
}

flutter {
    source = "../.."
}
