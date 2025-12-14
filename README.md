# 📱 GiantessNight 第三方客户端 (GN Forum App)

[![Flutter](https://img.shields.org/badge/Flutter-3.0%2B-blue.svg)](https://flutter.dev)
[![Platform](https://img.shields.org/badge/Platform-Android-green.svg)](https://www.android.com)
[![License](https://img.shields.org/badge/License-MIT-purple.svg)](LICENSE)

> **专为“被窝党”打造：流畅、纯净、强大的 GN 论坛原生阅读器。**

这是一个基于 **Flutter** 开发的 [GiantessNight](https://www.giantessnight.com) 论坛第三方客户端。它解决了原生网页版在手机上翻页困难、图片加载失败、排版混乱等痛点，为你带来如丝般顺滑的阅读体验。

## ✨ 核心亮点

### 📖 独家“小说模式”
- **沉浸阅读**：一键开启，自动过滤水贴，**只看楼主**。
- **智能排版**：隐藏多余 UI，采用羊皮纸/护眼绿背景，字体优化，堪比专业小说软件。
- **精准书签**：**手动选择楼层保存进度**，再也不怕进度丢失或页码错乱，随时接着看。

### 🖼️ 图片浏览“黑科技”
- **超强兼容**：完美解决 Discuz 动态链接导致的图片裂开、无限 Loading 问题。
- **原图预览**：点击图片进入大图预览模式，支持**双指缩放**查看细节。
- **一键保存**：支持长按或点击按钮将高清原图**保存到手机相册**（适配 Android 13+ 权限）。
- **智能重载**：弱网环境下图片加载失败？点击图片即可强制重载，不再需要刷新整个页面。

### 🎨 现代化体验
- **无限瀑布流**：告别“下一页”，手指一滑到底，自动加载后续楼层。
- **深色模式**：完美适配夜间模式，被窝里看帖不刺眼，修复了网页版字体颜色冲突看不清的问题。
- **个人中心**：自动同步论坛头像和用户名，一键查看自己的发帖历史。

### 🛠️ 实用工具
- **全站搜索**：支持关键词搜索帖子。
- **外部跳转**：帖子内的网盘链接可直接唤起浏览器或夸克下载。
- **缓存管理**：提供一键清除缓存功能，给手机瘦身。

## 📸 应用截图

| 首页浏览 | 小说模式 | 图片预览 | 个人中心 |
|:---:|:---:|:---:|:---:|
| ![Home](screenshot_path/home.jpg) | ![Novel](screenshot_path/novel.jpg) | ![Image](screenshot_path/image.jpg) | ![Profile](screenshot_path/profile.jpg) |

*(注：请替换为实际截图链接)*

## 📥 下载安装

前往 [Releases](../../releases) 页面下载最新版本的 APK 安装包。

或者访问蓝奏云下载：
- **链接**: [点击跳转](https://wwbnh.lanzout.com/iQ4k83cj1hha) (示例链接，请替换你的新链接)
- **密码**: `xxxx`

## 🛠️ 技术栈

本项目使用 **Flutter** 构建，主要技术点：
- **网络层**: `dio` + `cookie_jar` (处理 Discuz 复杂的鉴权和防盗链)
- **内容渲染**: `flutter_widget_from_html` (深度定制的 CSS 样式清洗和图片解析)
- **图片管理**: `cached_network_image` + `gal` (相册保存) + `photo_view` (手势缩放)
- **架构**: 针对 Android 13/14 进行了权限适配，支持 ARM32/64 架构。

## 🔒 隐私声明

本应用为**开源、非官方**客户端。
- **账号安全**：所有登录操作直接在 GN 论坛原版网页 (WebView) 中进行，App 仅获取登录成功后的 Cookie 用于数据请求。
- **隐私保护**：App 不会收集或上传您的任何个人信息。
- **纯净无广**：本项目纯粹为爱发电，无任何广告植入。

## 🤝 反馈与交流

如果你在使用中遇到 Bug（比如闪退、解析错误），欢迎在 GitHub 提 [Issues](../../issues) 或在论坛发布页留言。

## 📄 开源协议

本项目遵循 [MIT License](LICENSE) 开源协议。

---
*Created with ❤️ by fangzny*