# GiantessWaltz Flutter Client

[简体中文](./README.md) | [English](./README_EN.md)

> **Disclaimer**: This project is completely free and open source. If you purchased this application on platforms like Xianyu, Taobao, or any other marketplace, please request an immediate refund and report the seller.

A tailored third-party mobile client for **GiantessWaltz (GW Forum)**. Built with Flutter, it aims to provide a much smoother reading experience and powerful offline capabilities compared to the mobile web version.

[![Version](https://img.shields.io/badge/version-v1.4.0-orange.svg)](https://github.com/fangzny1/Giantesswaltz_APP/releases) 
[![Platform](https://img.shields.io/badge/platform-Android-green.svg)](https://flutter.dev) 
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE) 
[![Python Update Server](https://img.shields.io/badge/Update%20Server-FastAPI-blue?logo=python)](https://fangzny-myupdate-gw-app.hf.space/)

## 🌟 Highlights

This project was initially assisted by AI and deeply customized for the Discuz! X3.4 architecture. It is not just a web-view wrapper, but a **native API-driven** high-performance application.

- **🚀 API-First (Extreme Speed)**: Completely abandons web scraping in favor of the Discuz! mobile JSON API. Reduces data usage by over 60%.
- **📦 Full Offline Support**: Supports one-click "Full Thread Download" for a seamless reading experience even without an internet connection.
- **📖 Immersive "Novel Mode"**: Features smart OP-only locking, clean typography, and multiple background color schemes.
- **💬 Advanced Reply System**: Includes intelligent image compression for uploads, a BBCode toolbar, and pre-posting validation.
- **🎨 Personalization**: Supports global custom wallpapers and adaptive transparent themes.

## 📸 Screenshots

| Home Hall | Novel Mode | Image Preview | Profile |
|:---:|:---:|:---:|:---:|
| <img src="picture/home.jpg " width="200"/> | <img src="picture/novel.jpg" width="200"/> | <img src="picture/image.png" width="200"/> | <img src="picture/profile.png" width="200"/> |

## 📥 Installation

1.  Go to the [Releases](../../releases) page.
2.  Download the latest `Giantesswaltz_APP+arm64-v8a.apk
`.
3.  Install it on your Android device to start using it.

## 🛠️ Tech Stack

- **Framework**: Flutter (Dart)
- **Networking**: [Dio](https://pub.dev/packages/dio) (With Cookie persistence)
- **HTML Rendering**: [flutter_widget_from_html](https://pub.dev/packages/flutter_widget_from_html)
- **Backend (Update Service)**: Python + FastAPI (Hosted on Hugging Face Spaces)

## 🔒 Privacy & Security

- **Account Safety**: All login operations are performed directly through the official original web interface. The App only retrieves the Session Cookie upon successful login.
- **Privacy Protection**: The App does not collect or upload any of your personal private information.
- **Ad-Free**: This project is built out of passion and will remain permanently ad-free.

## 🤝 Feedback & Contribution

- If you encounter any bugs, feel free to submit an [Issue](../../issues).
- Pull Requests are welcome from developers interested in optimizing the app together.
## DEEPWIKI

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/fangzny1/Giantesswaltz_APP)
---
*Created with ❤️ by [fangzny](https://github.com/fangzny1)*