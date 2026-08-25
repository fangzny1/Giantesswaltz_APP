plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// =====================================================
// 【签名】读取 android/key.properties 里的 release keystore 配置
// 这样无论在哪台机器/CI 上构建，release APK 都用同一把签名。
// 如果 key.properties 或 keystore 文件缺失（比如别人 clone 后没拿到），
// 自动回退到 debug 签名，保证仓库能直接编译。
// =====================================================
import java.io.FileInputStream
import java.util.Properties

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
var hasReleaseKeystore = false
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    val storeFile = keystoreProperties.getProperty("storeFile")
    hasReleaseKeystore = storeFile != null && file(storeFile).exists()
}

android {
    // 【修改点 1】保持与 applicationId 和 Manifest 中的 package 一致
    // 之前是 "com.example.flutter_giantessnight_1"，建议改成下面这个：
    namespace = "com.example.gw_app"
    
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    // 针对 Kotlin DSL 的新写法，解决警告并修复单引号错误
    kotlinOptions {
        jvmTarget = "21" // 必须用双引号
    }
   // 如果你之前听我的加了这一段，请把它也改成 21，或者直接删掉它
   
    defaultConfig {
        // 【关键点】VPN 识别的就是这个 ID，保持不动
        applicationId = "com.example.gw_app"
        
        // 这里的配置很棒，minSdk 21 兼容老手机，targetSdk 34 适配新权限
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 【签名】专用 release 签名配置（gw_release.jks）
    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // 有正式 keystore 就用它，保证各机器签名一致、可覆盖安装；
            // 没有则回退 debug 签名（个人测试/派生版）
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // 【建议添加】开启代码混淆和压缩，可以让 APK 更小，也更安全一点
            // isMinifyEnabled = true
            // isShrinkResources = true
            // proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}
flutter {
    source = "../.."
}
