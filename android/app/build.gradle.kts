import java.util.Properties

// Релизный keystore не лежит в репозитории. Создай android/key.properties
// (он в .gitignore) по образцу key.properties.example. Если файла нет —
// release собирается debug-ключом, и это видно в логе сборки.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase (push-уведомления).
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

android {
    namespace = "kz.chatra.app"
    // 36, а не 35: androidx.core 1.18 (тянется транзитивно через
    // firebase_messaging / flutter_local_notifications) требует компиляции
    // против API 36 — со значением 35 задача bundleRelease падала целиком.
    // compileSdk влияет только на доступный набор API при компиляции, к
    // runtime-поведению отношения не имеет (за это отвечает targetSdk ниже).
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Требуется flutter_local_notifications (desugaring java.time и пр.).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "kz.chatra.app"
        // Версии зафиксированы явно, а не взяты из flutter.*: иначе итоговый
        // targetSdk зависит от версии Flutter SDK на машине сборки, и после
        // отката SDK получается AAB с устаревшим target, который Play не
        // принимает (требование targetSdk >= 35 действует с 31.08.2025,
        // >= 36 — с 31.08.2026).
        minSdk = 24          // требование firebase_messaging 16.x
        // ВНИМАНИЕ: на Android 16 (API 36) вступает в силу принудительный
        // edge-to-edge — отказаться от него через windowOptOutEdgeToEdgeEnforcement
        // на этом target уже нельзя. Отступы шелла и плавающего таб-бара под
        // системными панелями на реальном Android 16 ещё НЕ проверялись.
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
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
            // Уменьшение размера и обфускация Java/Kotlin-части.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )

            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // Раньше здесь было только предупреждение в логе — его легко
                // не заметить, и в Play уезжал AAB, подписанный debug-ключом
                // (консоль отклоняет такую загрузку). Для CI и для любой
                // осознанной релизной сборки падаем сразу.
                if (project.hasProperty("ciRelease")) {
                    throw GradleException(
                        "android/key.properties не найден — релизная сборка запрещена. " +
                        "См. key.properties.example."
                    )
                }
                logger.warn("⚠️  android/key.properties не найден — release подписан DEBUG-ключом. Такой билд Google Play не примет.")
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
