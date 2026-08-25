# agent.md — GiantessWaltz Flutter 客户端

> 本项目档案由 Claude 编写，供下次会话快速恢复上下文。**项目约 90% 由 AI vibe-coding 生成**，代码冗余、重复定义、注释多于实现是常态，动手前务必先读相关文件确认现状。

## 一句话

一个面向 **GiantessWaltz 论坛（Discuz! X3.4 架构）** 的第三方 Flutter 安卓客户端：原生 API 驱动（不爬网页），Cookie 鉴权，主打离线整本阅读 / 小说模式 / 自定义壁纸 / 双线路切换。

- 版本：v2.1.0（`kAppVersion`，forum_model.dart）
- 仓库：https://github.com/fangzny1/Giantesswaltz_APP
- 更新服务器：kUpdateUrl = `https://fangzny-myupdate-gw-app.hf.space/update`（Python FastAPI）
- 网络是核心：**主要围绕 Discuz 移动端 JSON API + Cookie 续命 + Cloudflare 对抗** 展开，所有疑难 bug 基本都在这条链路上。

## 技术栈

- Flutter (Dart)，主目标 Android；ios/web/linux/macos/windows 目录都在但未深度维护
- 网络：[dio](http://pub.dev/packages/dio) + [native_dio_adapter](http://pub.dev/packages/native_dio_adapter)（图片下载加速）
- HTML 渲染：flutter_widget_from_html；WebView：[webview_flutter](http://pub.dev/packages/webview_flutter)（隐藏 WebView 预热带 Cookie）
- 特效：[liquid_glass_renderer](http://pub.dev/packages/liquid_glass_renderer) v0.2.0-dev.4（LiquidGlass，**非默认**，设置在「外观」里开，作用于手机底栏）
- 缓存：flutter_cache_manager + flutter_cache_manager_dio + SharedPreferences
- 持久化：SharedPreferences（大量 JSON 字符串直接存里面）
- 其它：app_links（深链）、receive_sharing_intent（分享唤起）、image_picker、file_picker、cached_network_image、url_launcher

## 目录与关键文件

```
lib/
  main.dart               ★ 3632 行，程序入口 + MainScreen + ForumHomePage(首页大厅) + ProfilePage(个人中心)
  http_service.dart       HttpService 单例：getHtml / reviveSession / hosts直连模式(useHostsMode)
  forum_model.dart        全局状态 + 数据模型。currentBaseUrl、globalImageCache、cookieVersion 都在这
  thread_list_page.dart   板块帖子列表
  thread_detail_page.dart 帖子详情（从 WebView 抽取 HTML 渲染 / 小说模式入口）
  ultra_reader_page.dart  小说模式
  gallery_reader_page.dart 图片阅读
  login_page.dart         登录（跳官方 Web 网页登录，捕获 Cookie）
  cloudflare_solver.dart  Cloudflare 对抗（自动点击验证等）
  settings_page.dart      高级设置
  其余:
  offline_manager / offline_list_page / history_manager / history_page
  bookmark_page / favorite_page / search_page / user_detail_page / notification_page
  new_thread_page / reply_native_page / image_preview_page / image_download_service
  first_launch_page / miui_theme(主题) / cache_helper / general_webview_page
```

## 核心全局状态（多处 import 直接引用）

- `currentBaseUrl`（ValueNotifier\<String>，forum_model.dart）：当前线路域名，默认 `https://giantesswaltz.org/`，备用 `https://gtswaltz.org/`
- `currentUser` / `currentUserUid` / `currentUserAvatar`（ValueNotifier）
- `currentTheme`、`customWallpaperPath`、`transparentBarsEnabled`、`forumCardOpacity`、`transitionAnimationType`、`colorSchemeMode`、`seedColor`
- `useDioProxyLoader`（Dio 强力加载 vs WebView 原生加载）
- `cookieVersion`（ValueNotifier\<int>，forum_model.dart）：任何写入 `saved_cookie_string` 的地方都应 bump 它，否则 ThreadDetailPage 等持有 `_userCookies` 缓存的页面不刷新，会出现"图片必须重进模式才好"的玄学问题
- `globalImageCache`（late CacheManager）：自定义图片缓存，key 为 `gn_forum_imageCache_v5`
- `forumKey`：GlobalKey\<_ForumHomePageState>，供其它页面调 `refreshData()`

持久化 key（SharedPreferences）：
`saved_cookie_string` / `username` / `uid` / `avatar` / `selected_base_url` / `use_hosts_mode` / `use_dio_proxy` / `home_page_cache` / `hot_threads_cache_v2` / `custom_wallpaper` / `theme_mode` / `transition_animation_type` / `seed_color` / `cache_max_objects` / `cache_stale_days` 等。

## 网络链路（ Debug 时先理清这条）

1. 启动：读 `selected_base_url` → 设 currentBaseUrl；`HttpOverrides` 全局放宽证书校验
2. 首页 `_fetchData()`（main.dart）：先 **Dio 强力模式** `_fetchDataByDio()` 带 Cookie 直取 `api/mobile/index.php?version=4&module=forumindex`；失败/掉登录 → 隐藏 WebView 访问 `forum.php?mobile=2` 预热带刷新 Session → 再试一次
3. 掉登录判断：JSON 含 `"error":"to_login"`；续命 = 模拟浏览器请求 forum.php 302 链路抓 set-cookie
4. 抓数据统一走 `HttpService.getHtml()`，带 Hosts 直连（`useHostsMode && kDirectIp=104.128.90.178`）与 3 次重试 + 自愈
5. `_processData()` 解析 Variables → 同步 acth/saltkey/新 cookie 并写回 prefs，同时渲染分区/板块

**Cloudflare**：遇到会被 `HttpService` 抛 `CLOUDFLARE`；由 cloudflare_solver.dart 处理。

## 平板双栏导航系统（重要）

判定：`_isTabletMode(context)` = `宽度>600 && 横屏`（main.dart 顶部）。

- `openOnTablet(context, page)`：平板 → 右侧根页面（`tabletRightRootPage` + `tabletNavigatorKey` 的 `pushAndRemoveUntil`）；手机 → `Navigator.push`
- `adaptivePush(context, page)`：平板 → 压入右侧 Navigator（用于帖子详情等二级页面）；手机 → `Navigator.push`
- 右侧容器：`Navigator(key: tabletNavigatorKey)`，由 `tabletRightRootPage` 驱动
- 返回键：外层 PopScope 拦截，平板先返回右侧 Navigator，再双击退出

**约定：所有"打开页面"在平板下都必须走 `adaptivePush`/`openOnTablet`，否则会整屏盖住双栏。**

## ✅ Bug 1（已修复）：切换线路后一直转圈、退不出来

**位置**：ProfilePage._showDomainSwitchDialog + _changeDomain（main.dart ~3051–3180）

**根因（已定位，竞态）**：`_showDomainSwitchDialog` 里回调传的是 **Radio 弹窗自己的 `ctx`**（`_changeDomain(ctx, ...)`）。`_changeDomain` 全程用这个 `ctx`：先 `Navigator.pop` 关掉 Radio 弹窗，再 `showDialog` 弹转圈，收尾/异常分支再 `Navigator.pop` 关转圈。中间缓存清理/Cookie 迁移要 2s+，等跑完 `ctx` 指向的 element 已 deactivated，`Navigator.of(context)` 抛 `FlutterError`；catch 里再 pop 又抛一次，转圈弹窗 `canPop:false`+`barrierDismissible:false`，**物理键也退不出**。缓存清理快时可能在弹窗退出动画窗口内碰巧关掉，所以表现为偶发。

**已修复方案**：外层 `_showDomainSwitchDialog` 捕获 ProfilePage 自身 context（`final pageContext = context;`）传给 `_changeDomain`；且 `_changeDomain` 新增 `closeLoadingDialog()` 用 `Navigator.of(context, rootNavigator: true).canPop()` 兜底关闭，成功/失败（try+finally 语义）都能关掉。**

## ✅ Bug 2（已修复）：平板模式下头像入口未适配双栏

**位置**：main.dart 两处 `_jumpToMyPosts`（ForumHomePage / ProfilePage）+ 通知铃铛 + 登录入口

**修复方案**：`openOnTablet`/`adaptivePush` 返回类型从 void 改为 `Future<dynamic>?`（返回 push 的 Future，供 await）；两处 `_jumpToMyPosts`、首页通知铃铛、两处登录入口（“立即重新登录”/“登录账号”）全部改用 `adaptivePush`，平板下压入右侧面板而不再整屏盖住双栏。UserDetailPage 内点帖子本就 `adaptivePush`，链路已通。

## ✅ Bug 3（已修复）：切换线路后"暂无内容 / 登录态失效"，重启才好

**位置**：http_service.dart `getHtml` + main.dart `_changeDomain`

**根因**：切线路时旧域名的 `saved_cookie_string` 被原样塞给新域名 → 新域名 API 判 `to_login`。`getHtml` 原来只对"网络异常"续命重试，对 **200 但内容是 to_login** 的响应直接放行 → 所有页面显示"暂无内容/登录失效"；恢复靠 WebView 预热碰运气 + 冷启动重跑全流程。

**修复（3 个小改动，未重写现有流程）**：
1. `HttpService.getHtml`：API 返回含 `to_login` 时，本次调用内 `reviveSession()` 续命 + `continue` 重试一次（`toLoginHealed` 标志防循环；续命后仍失效则照常返回原响应，页面照旧弹"重新登录"）
2. `_changeDomain`：切线路成功后额外清 WebView 缓存（`WebViewController().clearCache()`，防止隐藏 WebView 沿用旧域名缓存导致"怎么都上不去、重启才好"）
3. `_changeDomain`：清掉 `home_page_cache` / `hot_threads_cache_v2` / `hot_thread_cache` 三个旧文本缓存，避免残留旧域名数据

注意：若服务器本身对新域名鉴权有差异（两域名非同一实例），可能仍有短暂等待或需要手动重登——此修复目标是让 App 自动完成"续命→重试"，不再依赖重启。

## ✅ 签名问题（已解决：统一 Release 签名入库）

**改动**（commit `f013d78`）：
- 生成专用 release keystore：`android/app/gw_release.jks`（alias `gw_release`，密码见 `android/key.properties`，**已提交仓库**）
- `android/app/build.gradle.kts`：新增 `signingConfigs.release` 从 key.properties 读取；release 构建**优先用 gw_release 签名**，文件缺失时自动回退 debug 签名，保证仓库 clone 也能编译
- `.gitignore`（根 + android）已去掉对 key.properties / .jks 的忽略，注明签名密钥有意入库

**影响**：
- 之前 Windows 上用该机器 debug.keystore 打的旧 Release APK，与现在 gw_release.jks 打的**签名不同** → 老用户覆盖安装会失败，必须先卸载（需在 GitHub Release 里说明）
- 之后所有机器（这台 Linux + 旧 Windows）只要 `git pull` 拿到最新代码，打的 release APK 签名一致，可互相覆盖安装
- keytool 在 `/home/mnski/.jdks/temurin-25.0.4/bin/keytool`（PATH 里没有 java，构建需自己设 JAVA_HOME 或用 Android Studio JBR `/home/mnski/android-studio/jbr`）

## ✨ LiquidGlass 液态玻璃效果（非默认）

- 依赖 `liquid_glass_renderer: ^0.2.0-dev.4`（已 pub get）
- 全局开关：`useLiquidGlass`（ValueNotifier\<bool>，main.dart 顶部），prefs key `use_liquid_glass`，**默认 false**
- 入口：settings_page.dart「外观与动画 → 液态玻璃底栏 (实验性)」SwitchListTile
- 作用点：**手机模式底部导航栏**。开启后 `ClipRRect+BackdropFilter` 换成 `LiquidGlass.withOwnLayer`（`LiquidRoundedRectangle` 药丸形 + `LiquidGlassSettings(blur:9, thickness:10, lightIntensity:0.35)`），折射背景；GPU 不支持 shader 时库自动回退 FakeGlass。参数在 main.dart nav bar 分支里可随手调。
- 注意：需要 Impeller（Flutter 3.47 安卓默认开启，Manifest 里无禁用项）；低端机/老设备慎开，有性能开销；当前是"尝试"级特性。

## 构建 / 运行命令

```bash
# 国内网络优先走镜像，否则 pub get 会超时
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
export JAVA_HOME=/home/mnski/.jdks/temurin-25.0.4   # PATH 里没有 java，需要手动指

flutter pub get
flutter run            # 联机调试
flutter build apk --release        # 产物在 build/app/outputs/，签名用 gw_release.jks
# 仓库里有 move_apks.ps1（Windows 脚本，移动产物），对应 Linux 可自行写一个
```

## 工程约定 / 常见坑

- **vibe 代码特征**：存在大量重复实现（如两个 `_jumpToMyPosts`、多个 cookie merge）、复制粘贴的 setState、print 中文日志。**搜索替代实现时多看几个文件。**
- `_safeMergeCookies`（main.dart 321 行）与 `mergeCookies`（forum_model.dart 68 行）是两个版本，别混用。
- 全局图片并发用 `PoliteFileService`（本站图故意 50ms 限流，外链全速）。
- SharedPreferences 里 `home_page_cache` / `hot_threads_cache_v2` 是首页秒开缓存；改 UI 或切换线路后记得清。
- 改 HTML 渲染相关主要在 thread_detail_page.dart / ultra_reader_page.dart，里面维护着自己的 cookie 快照 `_userCookies`，要用 `cookieVersion` 推失效。
- Android `local.properties` 里 SDK 路径、`.flutter-plugins-dependencies` 别提交到 git。

## 会话速查

看代码优先读：main.dart（路由/首页/个人中心）、http_service.dart（网络骨架）、forum_model.dart（全局状态/模型）。
改导航 → 先想平板双栏，用 `adaptivePush`/`openOnTablet`。
改网络 → 想 Cookie 链路，bump `cookieVersion`。