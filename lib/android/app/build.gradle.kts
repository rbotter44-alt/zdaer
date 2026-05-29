import java.io.File
import java.io.FileInputStream
import java.security.KeyStore
import java.security.MessageDigest
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}


fun certificateSha256FromKeystore(storeFile: File?, storePassword: String?, keyAlias: String?): String {
    if (storeFile == null || !storeFile.exists() || storePassword.isNullOrBlank()) return ""

    val tried = linkedSetOf("JKS", "PKCS12", KeyStore.getDefaultType())
    for (type in tried) {
        try {
            val keyStore = KeyStore.getInstance(type)
            storeFile.inputStream().use { keyStore.load(it, storePassword.toCharArray()) }

            val alias = when {
                !keyAlias.isNullOrBlank() && keyStore.containsAlias(keyAlias) -> keyAlias
                else -> keyStore.aliases().toList().firstOrNull { keyStore.getCertificate(it) != null }
            } ?: continue

            val cert = keyStore.getCertificate(alias) ?: continue
            val digest = MessageDigest.getInstance("SHA-256").digest(cert.encoded)
            return digest.joinToString("") { "%02X".format(it.toInt() and 0xff) }
        } catch (_: Throwable) {
        }
    }

    return ""
}

fun escapedBuildConfigString(value: String): String {
    return value.replace("\\", "\\\\").replace("\"", "\\\"")
}

android {
    namespace = "com.lighton.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    buildFeatures {
        buildConfig = true
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    defaultConfig {
        val releaseSigning = signingConfigs.getByName("release")
        val autoCertSha256 = certificateSha256FromKeystore(
            releaseSigning.storeFile,
            releaseSigning.storePassword,
            releaseSigning.keyAlias
        )
        val trustedCertSha256 = (
            (findProperty("APP_TRUSTED_CERT_SHA256") as String?)
                ?: System.getenv("APP_TRUSTED_CERT_SHA256")
                ?: autoCertSha256
        ).trim().replace(":", "").uppercase()

        buildConfigField("String", "TRUSTED_CERT_SHA256", "\"${escapedBuildConfigString(trustedCertSha256)}\"")

        applicationId = "com.lighton.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.media3:media3-exoplayer:1.10.0")
    implementation("androidx.media3:media3-exoplayer-hls:1.10.0")
    implementation("androidx.media3:media3-exoplayer-dash:1.10.0")
    implementation("androidx.media3:media3-ui:1.10.0")

    implementation("androidx.media3:media3-datasource-okhttp:1.10.0")
    implementation("androidx.media3:media3-datasource-cronet:1.10.0")

    implementation("org.chromium.net:cronet-embedded:119.6045.31")
}
    
   
    

