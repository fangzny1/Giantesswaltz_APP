plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // 【修改点 1】保持与 applicationId 和 Manifest 中的 package 一致
    // 之前是 "com.example.flutter_giantessnight_1"，建议改成下面这个：
    namespace = "com.example.giantessnight_app"
    
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
        // 【关键点】VPN 识别的就是这个 ID，保持不动
        applicationId = "com.example.giantessnight_app"
        
        // 这里的配置很棒，minSdk 21 兼容老手机，targetSdk 34 适配新权限
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // 目前使用 debug 签名是没问题的（个人使用/测试分发）
            // 如果以后要上架应用商店，才需要生成正式的 keystore
            signingConfig = signingConfigs.getByName("debug")
            
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
