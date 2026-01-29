import 'package:flutter/material.dart';
import 'package:giantesswaltz_app/offline_list_page.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart'; // Add Dio import
import 'login_page.dart';
import 'forum_model.dart';
import 'thread_list_page.dart';
import 'search_page.dart';
import 'favorite_page.dart';
import 'bookmark_page.dart';
import 'user_detail_page.dart'; // 用于跳转
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';

import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart'; // 引入缓存图片库
import 'cache_helper.dart'; // 引入缓存助手
import 'offline_manager.dart'; // 引入新文件

// 全局状态
final ValueNotifier<String> currentUser = ValueNotifier("未登录");
// 【新增】当前用户的 UID (用于跳转帖子列表)
final ValueNotifier<String> currentUserUid = ValueNotifier("");
// 【新增】当前用户的头像 URL
final ValueNotifier<String> currentUserAvatar = ValueNotifier("");
// 全局主题状态
final ValueNotifier<ThemeMode> currentTheme = ValueNotifier(ThemeMode.system);
// 【新增】自定义壁纸路径
final ValueNotifier<String?> customWallpaperPath = ValueNotifier(null);
final ValueNotifier<bool> transparentBarsEnabled = ValueNotifier(false);
// 【新增】加载模式开关：true = Dio代理加载 (强力模式), false = WebView原生加载 (默认)
final ValueNotifier<bool> useDioProxyLoader = ValueNotifier(false);

final GlobalKey<_ForumHomePageState> forumKey = GlobalKey();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _MyHttpOverrides();
  final prefs = await SharedPreferences.getInstance();

  currentUser.value = prefs.getString('username') ?? "未登录";
  // 【新增】加载本地存储的 UID 和 头像
  currentUserUid.value = prefs.getString('uid') ?? "";
  currentUserAvatar.value = prefs.getString('avatar') ?? "";
  // 【新增】加载壁纸路径
  customWallpaperPath.value = prefs.getString('custom_wallpaper');
  transparentBarsEnabled.value = prefs.getBool('transparent_bars') ?? false;
  // 【新增】读取设置
  useDioProxyLoader.value = prefs.getBool('use_dio_proxy') ?? false;

  String? themeStr = prefs.getString('theme_mode');
  if (themeStr == 'dark')
    currentTheme.value = ThemeMode.dark;
  else if (themeStr == 'light')
    currentTheme.value = ThemeMode.light;

  // 【新增】自动清理缓存逻辑
  bool clearImage = prefs.getBool('auto_clear_image_cache') ?? false;
  bool clearText = prefs.getBool('auto_clear_text_cache') ?? false;

  if (clearImage || clearText) {
    // 不阻塞主线程启动，但开始执行清理
    CacheHelper.clearAllCaches(
      clearFiles: clearImage,
      clearHtml: clearText,
    ).then((_) {
      print("🚀 [Main] 启动自动清理完成");
    });
  }

  runApp(const MyApp());
}

// 【新增】辅助函数：安全合并 Cookie 字符串
String _safeMergeCookies(String currentCookie, List<String> newCookieHeaders) {
  final Map<String, String> finalKv = {};

  // 1. 解析当前已有的 Cookie (旧的，如：auth=xxx; cdb_ref=yyy)
  void parseAndAdd(String raw) {
    for (final part in raw.split(';')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty || !trimmed.contains('=')) continue;
      final eq = trimmed.indexOf('=');
      final k = trimmed.substring(0, eq).trim();
      final v = trimmed.substring(eq + 1).trim();
      if (k.isNotEmpty &&
          !k.toLowerCase().contains('path') &&
          !k.toLowerCase().contains('domain')) {
        finalKv[k] = v;
      }
    }
  }

  // 2. 将旧 Cookie 存入 Map
  parseAndAdd(currentCookie);

  // 3. 将新的 Set-Cookie Header 存入 Map (新值覆盖旧值)
  for (final header in newCookieHeaders) {
    // Set-Cookie 头部包含 Path/Expires 等信息，我们只取 key=value 部分
    String cookiePart = header.split(';')[0];
    parseAndAdd(cookiePart);
  }

  // 4. 重新组合成一个新的、干净的 Cookie 字符串
  return finalKv.entries.map((e) => '${e.key}=${e.value}').join('; ');
}

// 【新增】定义一个 HttpOverrides 类
class _MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) =>
              true; // 允许自签名证书，减少 SSL 报错
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: currentTheme,
      builder: (context, mode, child) {
        return MaterialApp(
          title: 'GiantessWaltz',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF61CAB8),
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF61CAB8),
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          home: const MainScreen(),
        );
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final List<Widget> _pages = [
    ForumHomePage(key: forumKey),
    const SearchPage(),
    const ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: customWallpaperPath,
      builder: (context, wallpaperPath, child) {
        return Scaffold(
          // 如果有壁纸，Scaffold 背景透明
          backgroundColor: wallpaperPath != null ? Colors.transparent : null,
          extendBody: wallpaperPath != null && transparentBarsEnabled.value,
          body: Stack(
            children: [
              // 1. 背景层
              if (wallpaperPath != null)
                Positioned.fill(
                  child: Image.file(
                    File(wallpaperPath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(),
                  ),
                ),
              // 2. 遮罩层 (适配暗黑模式)
              if (wallpaperPath != null)
                Positioned.fill(
                  child: ValueListenableBuilder<ThemeMode>(
                    valueListenable: currentTheme,
                    builder: (context, mode, _) {
                      bool isDark = mode == ThemeMode.dark;
                      if (mode == ThemeMode.system) {
                        isDark =
                            MediaQuery.of(context).platformBrightness ==
                            Brightness.dark;
                      }
                      return Container(
                        color: isDark
                            ? Colors.black.withOpacity(0.6) // 暗黑模式加深遮罩
                            : Colors.white.withOpacity(0.3), // 亮色模式轻微遮罩
                      );
                    },
                  ),
                ),
              // 3. 内容层
              IndexedStack(index: _selectedIndex, children: _pages),
            ],
          ),
          bottomNavigationBar: ValueListenableBuilder<bool>(
            valueListenable: transparentBarsEnabled,
            builder: (context, enabled, _) {
              final bool useTransparent = wallpaperPath != null && enabled;
              return NavigationBar(
                backgroundColor: useTransparent
                    ? Colors.transparent
                    : (wallpaperPath != null
                          ? (Theme.of(context).brightness == Brightness.dark
                                ? Colors.black.withOpacity(0.4)
                                : Colors.white.withOpacity(0.6))
                          : null),
                elevation: wallpaperPath != null ? 0 : 3,
                indicatorColor: Theme.of(context).colorScheme.secondaryContainer
                    .withOpacity(useTransparent ? 0.6 : 0.8),
                selectedIndex: _selectedIndex,
                onDestinationSelected: (int index) =>
                    setState(() => _selectedIndex = index),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: '大厅',
                  ),
                  NavigationDestination(icon: Icon(Icons.search), label: '搜索'),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person),
                    label: '我的',
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

// ================== 首页 ==================

class ForumHomePage extends StatefulWidget {
  const ForumHomePage({super.key});
  @override
  State<ForumHomePage> createState() => _ForumHomePageState();
}

class _ForumHomePageState extends State<ForumHomePage> {
  List<Category> _categories = [];
  Map<String, Forum> _forumsMap = {};
  bool _isLoading = true;
  WebViewController? _hiddenController;
  Timer? _timeoutTimer;
  bool _apiHttpFallbackTried = false;

  @override
  void initState() {
    super.initState();
    _initHiddenWebView();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _forceRetry() {
    print("💪 用户手动触发强力加载");
    _fetchData();
  }

  // 【修复点】这就是之前报错缺失的方法，现在补上了
  void refreshData() {
    if (!mounted) return;
    print("🔄 收到外部刷新请求...");
    _fetchData();
  }

  // 在 _ForumHomePageState 类中

  Future<void> _initHiddenWebView() async {
    // 0. 【极速优化】先加载缓存数据，让用户这就看到界面
    _loadCacheData();

    // 1. 读取本地 Cookie
    final prefs = await SharedPreferences.getInstance();
    final String savedCookie = prefs.getString('saved_cookie_string') ?? "";

    // 2. 【核心修复】在创建 Controller 之前，先把 Cookie 塞进系统管理器
    //  这样 WebView 所有的请求（包括图片、AJAX、重定向）都会自动带上 Cookie
    if (savedCookie.isNotEmpty) {
      final cookieMgr = WebViewCookieManager();
      // 简单粗暴：把整个字符串作为 Cookie 注入
      // 注意：Discuz 需要域名匹配，我们设为主域名
      await cookieMgr.setCookie(
        WebViewCookie(
          name: 'cookie_import', // 名字不重要，重要的是 value
          value: 'imported', // 占位
          domain: kBaseDomain,
        ),
      );

      // 更高级的注入：解析原始字符串（这一步能极大提高稳定性）
      // 原始 Cookie 格式通常是 "name=value; name2=value2"
      List<String> rawCookies = savedCookie.split(';');
      for (var c in rawCookies) {
        if (c.contains('=')) {
          var parts = c.split('=');
          var key = parts[0].trim();
          var value = parts.sublist(1).join('=').trim();
          if (key.isNotEmpty) {
            try {
              await cookieMgr.setCookie(
                WebViewCookie(
                  name: key,
                  value: value,
                  domain: kBaseDomain, // 关键！必须是这个域名
                ),
              );
              await cookieMgr.setCookie(
                WebViewCookie(
                  name: key,
                  value: value,
                  domain: 'www.$kBaseDomain', //以此类推，www也加一份
                ),
              );
            } catch (e) {
              // 忽略个别格式错误的 cookie
            }
          }
        }
      }
      print("🍪 Cookie 已强力注入 WebView 系统！");
    }

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(kUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            if (url.contains('module=forumindex')) {
              _parsePageContent();
            }
            // 只要加载的是 forum.php (不管后面参数是啥)，都视为预热成功
            else if (url.contains('forum.php')) {
              print("🔥 Session 激活成功，开始请求 API...");
              final String timestamp = DateTime.now().millisecondsSinceEpoch
                  .toString();
              _hiddenController?.loadRequest(
                Uri.parse(
                  '${kBaseUrl}api/mobile/index.php?version=4&module=forumindex&t=$timestamp',
                ),
              );
            }
          },
        ),
      );

    if (mounted) {
      setState(() {
        _hiddenController = controller;
      });
    }

    // 3. 开始加载 (带上 Header 双重保险)
    _fetchData();
  }

  // 【新增】读取本地缓存数据
  Future<void> _loadCacheData() async {
    final prefs = await SharedPreferences.getInstance();
    final String? cacheJson = prefs.getString('home_page_cache');

    if (cacheJson != null && _categories.isEmpty) {
      print("🚀 命中本地缓存，立即渲染！");
      try {
        var data = jsonDecode(cacheJson);
        // 复用 _processData 来解析数据
        _processData(data);
        // 注意：_processData 内部会调用 setState，但我们可能还想保持 _isLoading = true
        // 实际上 _processData 会把 _isLoading 设为 false，这对于"秒开"体验是可以的
        // 后台的 _fetchData 仍然会继续跑，并在数据回来后再次调用 _processData 刷新界面
      } catch (e) {
        print("⚠️ 缓存解析失败: $e");
      }
    }
  }

  // ==========================================
  // 2. 初始预热方法
  // ==========================================
  void _fetchData() async {
    if (!mounted) return;

    // 重置定时器和SnackBar
    _timeoutTimer?.cancel();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    setState(() {
      _isLoading = true;
      _apiHttpFallbackTried = false;
    });

    // 启动超时检测
    _timeoutTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && _isLoading) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("加载超时，请尝试强力加载"),
            duration: const Duration(seconds: 30),
            action: SnackBarAction(label: "强力加载", onPressed: _forceRetry),
          ),
        );
      }
    });

    // 1. 【新增】Dio 抢跑 (尝试直接请求 API)
    // 不管有没有开启强力模式，只要有 Cookie，就尝试抢跑
    // 这样能最大程度利用 API 速度优势
    _fetchDataByDio();

    // 【新增】每次刷新前清理 WebView 缓存，确保 Cookie 状态重置
    // 这样能解决"第一次行第二次不行"的问题
    try {
      await _hiddenController?.clearCache();
    } catch (e) {
      // 忽略清理失败
    }

    print("🔄 WebView 开始预热...");

    // 预热使用 mobile=2，与登录态保持一致
    _hiddenController?.loadRequest(Uri.parse('${kBaseUrl}forum.php?mobile=2'));
  }

  // ==========================================
  // 2.5 Dio 强力加载主页 (API)
  // ==========================================
  // 【修复版】Dio 快速请求 + Cookie 自动更新
  Future<bool> _fetchDataByDio() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String oldCookie = prefs.getString('saved_cookie_string') ?? "";

      print(
        "🔍 [DioProxy Debug] 初始 Cookie: ${oldCookie.length > 50 ? oldCookie.substring(0, 50) + '...' : oldCookie}",
      );

      if (oldCookie.isEmpty) {
        print("🔍 [DioProxy Debug] 没有旧 Cookie，放弃抢跑");
        return false;
      }

      final dio = Dio();
      dio.options.headers['Cookie'] = oldCookie; // 确保带上旧的去请求
      dio.options.headers['User-Agent'] = kUserAgent;
      dio.options.connectTimeout = const Duration(seconds: 30);
      dio.options.receiveTimeout = const Duration(seconds: 30);

      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String httpsUrl =
          '${kBaseUrl}api/mobile/index.php?version=4&module=forumindex&t=$timestamp';
      final String httpUrl =
          'http://$kBaseDomain/api/mobile/index.php?version=4&module=forumindex&t=$timestamp';

      print("🔍 [DioProxy Debug] 请求 URL: $httpsUrl");
      Response<String> response;
      try {
        response = await dio.get<String>(httpsUrl);
      } on DioException catch (e) {
        final String msg = e.error?.toString() ?? e.toString();
        if (msg.contains('HandshakeException')) {
          print("⚠️ [DioProxy] HTTPS 握手失败，尝试 HTTP...");
          response = await dio.get<String>(httpUrl);
        } else {
          rethrow;
        }
      }

      print("🔍 [DioProxy Debug] 响应状态码: ${response.statusCode}");

      // 【核心修复】使用新的合并函数
      List<String>? newCookieHeaders = response.headers['set-cookie'];
      String? updatedCookie; // 用于重试的新 Cookie
      if (newCookieHeaders != null && newCookieHeaders.isNotEmpty) {
        print("🔍 [DioProxy Debug] 服务器返回 Set-Cookie: $newCookieHeaders");
        // 合并旧 Cookie 和新 Set-Cookie 头部
        String mergedCookie = _safeMergeCookies(oldCookie, newCookieHeaders);
        print(
          "🔍 [DioProxy Debug] 合并后 Cookie: ${mergedCookie.length > 50 ? mergedCookie.substring(0, 50) + '...' : mergedCookie}",
        );

        // 如果合并后的 Cookie 看起来有效，就存入硬盘
        if (mergedCookie.contains('auth') || mergedCookie.contains('saltkey')) {
          await prefs.setString('saved_cookie_string', mergedCookie);
          print("💾 [DioProxy] Cookie 合并成功，已保存！");
          updatedCookie = mergedCookie; // 记录下来准备重试
        }
      } else {
        print("🔍 [DioProxy Debug] 服务器没有返回 Set-Cookie");
      }

      if (response.statusCode == 200 && response.data != null) {
        String jsonStr = response.data!;

        print(
          "🔍 [DioProxy Debug] 响应数据片段: ${jsonStr.length > 100 ? jsonStr.substring(0, 100) : jsonStr}...",
        );

        // 数据清洗
        if (jsonStr.startsWith('"') && jsonStr.endsWith('"')) {
          jsonStr = jsonStr
              .substring(1, jsonStr.length - 1)
              .replaceAll('\\"', '"')
              .replaceAll('\\\\', '\\');
        }

        // 检查是否掉登录
        if (jsonStr.contains('"error":"to_login"') ||
            jsonStr.contains('messageval":"to_login')) {
          print("💨 [DioProxy] Cookie 已失效 (包含 to_login 错误)");

          // 【新增】原地复活重试机制 (API 续命)
          if (updatedCookie != null && updatedCookie != oldCookie) {
            print("🔄 [DioProxy] 发现 API 更新了 Cookie，尝试原地复活重试...");
            dio.options.headers['Cookie'] = updatedCookie;
            Response<String> retryResponse;
            try {
              retryResponse = await dio.get<String>(httpsUrl);
            } on DioException catch (e) {
              final String msg = e.error?.toString() ?? e.toString();
              if (msg.contains('HandshakeException')) {
                print("⚠️ [DioProxy] HTTPS 握手失败，尝试 HTTP...");
                retryResponse = await dio.get<String>(httpUrl);
              } else {
                rethrow;
              }
            }

            if (retryResponse.statusCode == 200 && retryResponse.data != null) {
              String retryJson = retryResponse.data!;
              // 再次清洗
              if (retryJson.startsWith('"') && retryJson.endsWith('"')) {
                retryJson = retryJson
                    .substring(1, retryJson.length - 1)
                    .replaceAll('\\"', '"')
                    .replaceAll('\\\\', '\\');
              }

              if (!retryJson.contains('"error":"to_login"') &&
                  !retryJson.contains('messageval":"to_login')) {
                print("✅ [DioProxy] 原地复活成功 (API 续命)！");
                await prefs.setString('home_page_cache', retryJson);
                _processData(jsonDecode(retryJson));
                return true;
              } else {
                print("❌ [DioProxy] 原地复活失败 (API 没给 Auth)");
              }
            }
          }

          // 【新增】Web 页面模拟续命 (终极杀招)
          // 既然 API 不给 Auth，那就模拟浏览器去访问 forum.php，强行让服务器刷新 Auth
          print("🔄 [DioProxy] 尝试模拟浏览器访问 forum.php 以刷新 Auth...");
          try {
            // 策略调整：优先使用旧的 Cookie 尝试（因为 API 给的新 Saltkey 可能有毒）
            // 如果旧的也失效，那反正都是失效，没区别
            String currentBestCookie = oldCookie;

            // 模拟更真实的浏览器 Header
            dio.options.headers['Cookie'] = currentBestCookie;
            dio.options.headers['Accept'] =
                'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8';
            dio.options.headers['Accept-Language'] = 'zh-CN,zh;q=0.9,en;q=0.8';
            dio.options.headers['Referer'] = '${kBaseUrl}forum.php?mobile=2';

            // 【关键】禁止自动重定向！
            // 这样我们能看到 forum.php 的 302 响应，以及它携带的 Set-Cookie
            // 否则 Dio 会自动跳转到登录页，我们看到的 Set-Cookie 就变成了登录页的（lastact=logging）
            dio.options.followRedirects = false;
            dio.options.validateStatus = (status) =>
                status != null && status < 500;

            // 请求 forum.php
            Response<String> forumResp = await dio.get<String>(
              '${kBaseUrl}forum.php?mobile=2',
            );

            print("🔍 [DioProxy Debug] forum.php 响应码: ${forumResp.statusCode}");

            final List<String>? forumCookies = forumResp.headers['set-cookie'];
            if (forumCookies != null && forumCookies.isNotEmpty) {
              currentBestCookie = _safeMergeCookies(
                currentBestCookie,
                forumCookies,
              );
            }

            final int? statusCode = forumResp.statusCode;
            final String? location = forumResp.headers.value('location');
            if ((statusCode == 301 || statusCode == 302) &&
                location != null &&
                location.isNotEmpty) {
              Uri redirectUri = Uri.parse(location);
              if (!location.startsWith('http')) {
                if (location.startsWith('/')) {
                  redirectUri = Uri.parse('https://$kBaseDomain$location');
                } else {
                  redirectUri = Uri.parse('$kBaseUrl$location');
                }
              }

              dio.options.headers['Cookie'] = currentBestCookie;
              dio.options.headers['Referer'] = '${kBaseUrl}forum.php?mobile=2';

              final Response<String> redirectResp = await dio.get<String>(
                redirectUri.toString(),
              );
              final List<String>? redirectCookies =
                  redirectResp.headers['set-cookie'];
              if (redirectCookies != null && redirectCookies.isNotEmpty) {
                currentBestCookie = _safeMergeCookies(
                  currentBestCookie,
                  redirectCookies,
                );
              }
            }

            final String forumMergedCookie = currentBestCookie;

            bool gotNewAuth = false;
            if (forumMergedCookie.contains('auth=') ||
                forumMergedCookie.contains('_auth=')) {
              final parts = forumMergedCookie.split(';');
              for (final p in parts) {
                final kv = p.trim().split('=');
                if (kv.length >= 2) {
                  final key = kv[0].toLowerCase();
                  final val = kv[1];
                  if ((key.endsWith('auth') || key.endsWith('_auth')) &&
                      val.length > 5 &&
                      val != 'deleted') {
                    gotNewAuth = true;
                    break;
                  }
                }
              }
            }

            if (gotNewAuth) {
              print("✅ [DioProxy] 检查到有效 Auth 存在");
            } else {
              print("⚠️ [DioProxy] 警告: 合并后的 Cookie 中未发现有效 Auth 字段");
            }

            await prefs.setString('saved_cookie_string', forumMergedCookie);

            dio.options.followRedirects = true;
            dio.options.headers['Cookie'] = forumMergedCookie;
            dio.options.headers.remove('Accept');
            dio.options.headers.remove('Accept-Language');
            dio.options.headers['Referer'] = '${kBaseUrl}forum.php?mobile=2';

            Response<String> finalRetry;
            try {
              finalRetry = await dio.get<String>(httpsUrl);
            } on DioException catch (e) {
              final String msg = e.error?.toString() ?? e.toString();
              if (msg.contains('HandshakeException')) {
                print("⚠️ [DioProxy] HTTPS 握手失败，尝试 HTTP...");
                finalRetry = await dio.get<String>(httpUrl);
              } else {
                rethrow;
              }
            }
            if (finalRetry.statusCode == 200 && finalRetry.data != null) {
              String finalJson = finalRetry.data!;
              if (finalJson.startsWith('"') && finalJson.endsWith('"')) {
                finalJson = finalJson
                    .substring(1, finalJson.length - 1)
                    .replaceAll('\\"', '"')
                    .replaceAll('\\\\', '\\');
              }

              if (!finalJson.contains('"error":"to_login"') &&
                  !finalJson.contains('messageval":"to_login')) {
                print("⚡️ [DioProxy] 最终抢跑成功！(Web模拟生效)");
                await prefs.setString('home_page_cache', finalJson);
                _processData(jsonDecode(finalJson));
                return true;
              } else {
                print(
                  "❌ [DioProxy] 最终重试依然失败。Server Response: ${finalJson.length > 50 ? finalJson.substring(0, 50) : finalJson}...",
                );
              }
            }
          } catch (e) {
            print("❌ [DioProxy] 模拟浏览器续命失败: $e");
          }

          print("💨 [DioProxy] 最终放弃，转交 WebView");
          return false;
        }

        print("✅ [DioProxy] 抢跑成功！");
        // 保存缓存
        await prefs.setString('home_page_cache', jsonStr);

        // 解析数据
        var data = jsonDecode(jsonStr);
        _processData(data);
        return true;
      }
    } catch (e) {
      print("❌ [DioProxy] 抢跑失败: $e");
    }
    return false;
  }

  // 抽取出的数据处理逻辑
  void _processData(dynamic data) async {
    // 处理 to_login 错误 (Cookie 失效)
    if (data['error'] == 'to_login' ||
        (data['Message'] != null &&
            data['Message']['messageval'] == 'to_login')) {
      print("⚠️ 检测到 Cookie 失效或需要登录");
      if (mounted) {
        _timeoutTimer?.cancel();
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    if (data['Variables'] == null) {
      print("⚠️ 数据解析异常: 缺少 Variables 字段");
      if (mounted) {
        _timeoutTimer?.cancel();
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    // === 开始解析 Variables ===
    var variables = data['Variables'];

    // 1. 更新用户信息
    String newName = variables['member_username'].toString();
    String newUid = variables['member_uid'].toString();
    final prefs = await SharedPreferences.getInstance();

    final String cookiePre = variables['cookiepre']?.toString() ?? '';
    final String apiAuth = variables['auth']?.toString() ?? '';
    final String apiSaltkey = variables['saltkey']?.toString() ?? '';
    if (cookiePre.isNotEmpty && (apiAuth.isNotEmpty || apiSaltkey.isNotEmpty)) {
      final List<String> kvCookies = [];
      if (apiAuth.isNotEmpty) kvCookies.add('${cookiePre}auth=$apiAuth');
      if (apiSaltkey.isNotEmpty)
        kvCookies.add('${cookiePre}saltkey=$apiSaltkey');

      final String current = prefs.getString('saved_cookie_string') ?? '';
      final String merged = _safeMergeCookies(current, kvCookies);
      await prefs.setString('saved_cookie_string', merged);
      debugPrint("💾 [AutoSync] 已从 API Variables 同步 auth/saltkey");
    }

    if (newName.isNotEmpty) {
      if (newName != currentUser.value) {
        currentUser.value = newName;
        await prefs.setString('username', newName);
      }

      if (newUid.isNotEmpty && newUid != "0") {
        if (newUid != currentUserUid.value) {
          currentUserUid.value = newUid;
          await prefs.setString('uid', newUid);
        }
        String avatarUrl =
            "${kBaseUrl}uc_server/avatar.php?uid=$newUid&size=middle";
        if (currentUserAvatar.value != avatarUrl) {
          currentUserAvatar.value = avatarUrl;
          await prefs.setString('avatar', avatarUrl);
        }
      }
    }

    // 2. 解析分区 (catlist)
    List<Category> tempCats = [];
    var rawCatList = variables['catlist'];
    if (rawCatList != null) {
      if (rawCatList is List) {
        tempCats = rawCatList.map((e) => Category.fromJson(e)).toList();
      } else if (rawCatList is Map) {
        rawCatList.forEach((k, v) {
          tempCats.add(Category.fromJson(v));
        });
      }
    }

    // 3. 解析板块 (forumlist)
    Map<String, Forum> tempForumMap = {};
    var rawForumList = variables['forumlist'];
    if (rawForumList != null) {
      if (rawForumList is List) {
        for (var f in rawForumList) {
          var forum = Forum.fromJson(f);
          tempForumMap[forum.fid] = forum;
        }
      } else if (rawForumList is Map) {
        rawForumList.forEach((k, v) {
          var forum = Forum.fromJson(v);
          tempForumMap[forum.fid] = forum;
        });
      }
    }

    print("✅ 解析成功: 获取到 ${tempCats.length} 个分区, ${tempForumMap.length} 个板块");
    _syncLatestCookie();

    if (mounted) {
      _timeoutTimer?.cancel();
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      setState(() {
        _categories = tempCats;
        _forumsMap = tempForumMap;
        _isLoading = false;
      });

      // 【新增】保存主页缓存
      // 我们只保存关键数据，把 _categories 和 _forumsMap 序列化后保存
      // 但 _processData 接收的是原始 data，所以我们应该在 _processData 外部保存原始 data
      // 或者在这里重新构造一下 data 结构
      // 最简单的办法：在 _fetchDataByDio 和 _parsePageContent 里，成功拿到 jsonStr 后直接保存
    }
  }

  // 【新增】自动同步 WebView 的 Cookie 到本地
  Future<void> _syncLatestCookie() async {
    if (_hiddenController == null) return;
    try {
      final String cookies =
          await _hiddenController!.runJavaScriptReturningResult(
                'document.cookie',
              )
              as String;
      String rawCookie = cookies;
      if (rawCookie.startsWith('"') && rawCookie.endsWith('"')) {
        rawCookie = rawCookie.substring(1, rawCookie.length - 1);
      }

      if (rawCookie.isNotEmpty &&
          (rawCookie.contains('auth') || rawCookie.contains('saltkey'))) {
        final prefs = await SharedPreferences.getInstance();
        final String current = prefs.getString('saved_cookie_string') ?? '';
        final List<String> kvCookies = rawCookie
            .split(';')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        final String merged = _safeMergeCookies(current, kvCookies);
        await prefs.setString('saved_cookie_string', merged);
        debugPrint("💾 [AutoSync] Cookie 已在后台更新，下次启动 Dio 更稳！");
      }
    } catch (_) {}
  }

  // ==========================================
  // 3. 核心解析逻辑 (修复了重复定义和解析兼容性)
  // ==========================================
  Future<void> _parsePageContent({String? inputJson}) async {
    try {
      String jsonString;

      // 1. 如果外部传了 JSON (来自 Dio)，直接用
      if (inputJson != null) {
        jsonString = inputJson;
      } else {
        // 2. 否则从 WebView 提取
        if (_hiddenController == null) return;
        final String content =
            await _hiddenController!.runJavaScriptReturningResult(
                  "document.body.innerText",
                )
                as String;
        jsonString = content;
        // 清洗数据
        if (jsonString.startsWith('"') && jsonString.endsWith('"')) {
          jsonString = jsonString.substring(1, jsonString.length - 1);
          jsonString = jsonString
              .replaceAll('\\"', '"')
              .replaceAll('\\\\', '\\');
        }
      }

      print(
        "📄 服务器返回原始内容: ${jsonString.length > 100 ? jsonString.substring(0, 100) + '...' : jsonString}",
      );

      if (!_apiHttpFallbackTried &&
          jsonString.contains('Webpage not available') &&
          _hiddenController != null) {
        _apiHttpFallbackTried = true;
        final String timestamp = DateTime.now().millisecondsSinceEpoch
            .toString();
        await _hiddenController!.loadRequest(
          Uri.parse(
            'http://$kBaseDomain/api/mobile/index.php?version=4&module=forumindex&t=$timestamp',
          ),
        );
        return;
      }

      var data;
      try {
        data = jsonDecode(jsonString);
      } catch (e) {
        print("❌ JSON 格式错误，服务器返回的可能不是数据");
        if (mounted) {
          _timeoutTimer?.cancel();
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      // 【新增】验证数据有效性后，保存缓存
      if (data['Variables'] != null) {
        final prefs = await SharedPreferences.getInstance();
        // 保存原始 JSON 字符串，方便下次直接加载
        // 注意：jsonString 已经是清洗过的
        await prefs.setString('home_page_cache', jsonString);
        print("💾 主页数据已缓存");
      }

      _processData(data); // Reuse the logic
    } catch (e) {
      print("❌ 解析过程报错: $e");
      if (mounted) {
        _timeoutTimer?.cancel();
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () async {
            _fetchData();
            await Future.delayed(const Duration(seconds: 1));
          },
          child: CustomScrollView(
            slivers: [
              ValueListenableBuilder<String?>(
                valueListenable: customWallpaperPath,
                builder: (context, wallpaperPath, _) {
                  bool useTransparent =
                      wallpaperPath != null && transparentBarsEnabled.value;
                  return SliverAppBar.large(
                    title: const Text("GiantessWaltz"),
                    backgroundColor: useTransparent ? Colors.transparent : null,
                  );
                },
              ),
              if (_isLoading)
                const SliverToBoxAdapter(child: LinearProgressIndicator()),
              if (_categories.isEmpty && !_isLoading)
                SliverFillRemaining(
                  child: Center(
                    child: ElevatedButton(
                      onPressed: _fetchData,
                      child: const Text("刷新数据"),
                    ),
                  ),
                ),
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final category = _categories[index];
                  return _buildCategoryCard(category);
                }, childCount: _categories.length),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),
        ),
        SizedBox(
          height: 0,
          width: 0,
          child: _hiddenController != null
              ? WebViewWidget(controller: _hiddenController!)
              : const SizedBox(),
        ),
      ],
    );
  }

  Widget _buildCategoryCard(Category category) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 16, 8),
          child: Text(
            category.name,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...category.forumIds.map((fid) {
          final forum = _forumsMap[fid];
          if (forum == null) return const SizedBox.shrink();
          return _buildForumTile(forum);
        }),
      ],
    );
  }

  Widget _buildForumTile(Forum forum) {
    return ValueListenableBuilder<String?>(
      valueListenable: customWallpaperPath,
      builder: (context, wallpaperPath, _) {
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          elevation: 0,
          color: wallpaperPath != null
              ? Theme.of(
                  context,
                ).colorScheme.surfaceContainerLow.withOpacity(0.7)
              : Theme.of(context).colorScheme.surfaceContainerLow,

          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    ThreadListPage(fid: forum.fid, forumName: forum.name),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          forum.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (int.tryParse(forum.todayposts) != null &&
                          int.parse(forum.todayposts) > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            "+${forum.todayposts}",
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (forum.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      forum.description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: wallpaperPath != null
                            ? Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.8)
                            : Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // 【新增】监听壁纸变化
  @override
  void initState() {
    super.initState();
    customWallpaperPath.addListener(_onWallpaperChanged);
  }

  @override
  void dispose() {
    customWallpaperPath.removeListener(_onWallpaperChanged);
    super.dispose();
  }

  void _onWallpaperChanged() {
    if (mounted) setState(() {});
  }

  void _toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (currentTheme.value == ThemeMode.light) {
      currentTheme.value = ThemeMode.dark;
      await prefs.setString('theme_mode', 'dark');
    } else {
      currentTheme.value = ThemeMode.light;
      await prefs.setString('theme_mode', 'light');
    }
  }

  // 【修正版】显示清理缓存选项弹窗
  void _showClearCacheDialog(BuildContext context) async {
    // 1. 先计算当前大小
    String cacheSizeStr = "计算中...";
    String cachePath = "";
    bool isClearing = false;

    // 自动清理设置状态
    bool? autoClearImage;
    bool? autoClearText;

    // 显示加载中的弹窗，等计算完了再更新内容
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            // 异步加载大小和设置 (仅在初始化时)
            if (cacheSizeStr == "计算中..." && !isClearing) {
              CacheHelper.getCachePath().then((p) {
                if (context.mounted) setState(() => cachePath = p);
              });
              CacheHelper.getTotalCacheSize().then((bytes) {
                if (context.mounted) {
                  setState(() {
                    cacheSizeStr = CacheHelper.formatSize(bytes);
                  });
                }
              });
              SharedPreferences.getInstance().then((prefs) {
                if (context.mounted) {
                  setState(() {
                    autoClearImage =
                        prefs.getBool('auto_clear_image_cache') ?? false;
                    autoClearText =
                        prefs.getBool('auto_clear_text_cache') ?? false;
                  });
                }
              });
            }

            return AlertDialog(
              title: const Text("缓存管理"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "如果是为了节省空间，建议定期清理图片缓存。\n文章缓存（WebView）清理后需要重新加载网页资源。",
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 15),

                    // 自动清理开关
                    if (autoClearImage != null)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text("退出后自动清理图片"),
                        subtitle: const Text("下次启动App时生效"),
                        value: autoClearImage!,
                        onChanged: (val) async {
                          setState(() => autoClearImage = val);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('auto_clear_image_cache', val);
                        },
                      ),
                    if (autoClearText != null)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text("退出后自动清理文本"),
                        subtitle: const Text("下次启动App时生效"),
                        value: autoClearText!,
                        onChanged: (val) async {
                          setState(() => autoClearText = val);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('auto_clear_text_cache', val);
                        },
                      ),
                    const Divider(),

                    if (cachePath.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SelectableText(
                          "缓存路径: $cachePath",
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                      ),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("当前缓存占用:"),
                              isClearing
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      cacheSizeStr,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.delete_forever,
                        color: Colors.red,
                      ),
                      title: const Text("清理图片缓存 (强力)"),
                      subtitle: const Text("删除所有已下载的帖子图片"),
                      onTap: isClearing
                          ? null
                          : () async {
                              setState(() {
                                isClearing = true;
                              });
                              // 不关闭弹窗，直接清理
                              await _clearImageCache(showLoading: false);

                              // 重新计算大小
                              int bytes = await CacheHelper.getTotalCacheSize();
                              if (context.mounted) {
                                setState(() {
                                  isClearing = false;
                                  cacheSizeStr = CacheHelper.formatSize(bytes);
                                });
                              }
                            },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.web, color: Colors.orange),
                      title: const Text("清理网页与文本缓存"),
                      subtitle: const Text("删除网页Cookie、帖子文本等"),
                      onTap: () async {
                        Navigator.pop(context);
                        _clearWebViewCache();
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("关闭"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _clearImageCache({bool showLoading = true}) async {
    if (showLoading) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      // 1. 先尝试清理 WebView 缓存 (释放文件锁)
      try {
        await WebViewController().clearCache();
      } catch (e) {
        print("WebView clearCache 失败 (非致命): $e");
      }

      // 2. 清理内存缓存 (Flutter ImageCache)
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      // 3. 使用 Helper 进行强力清理 (仅清理文件，保留文本)
      await CacheHelper.clearAllCaches(clearFiles: true, clearHtml: false);

      if (mounted) {
        if (showLoading) Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("✅ 图片缓存已彻底清理 (含内存/磁盘)")));
      }
    } catch (e) {
      if (mounted) {
        if (showLoading) Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("❌ 清理失败: $e")));
      }
    }
  }

  Future<void> _clearWebViewCache() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // 创建临时控制器清理缓存
      await WebViewController().clearCache();

      // 【新增】同时清理 SharedPreferences 中的帖子文本缓存
      await CacheHelper.clearHtmlCache();

      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("✅ 网页与文本缓存已清理")));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("❌ 清理失败: $e")));
      }
    }
  }

  // 【新增】跳转到我的帖子
  void _jumpToMyPosts(BuildContext context) {
    if (currentUserUid.value.isNotEmpty && currentUserUid.value != "0") {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserDetailPage(
            uid: currentUserUid.value,
            username: currentUser.value,
            avatarUrl: currentUserAvatar.value,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("请先登录")));
    }
  }

  // 【新增】显示关于弹窗
  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("关于"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Giantesswaltz 第三方客户端"),
            const SizedBox(height: 8),
            const Text("这是一个非官方的第三方客户端，旨在提供更好的移动端阅读体验。"),
            const SizedBox(height: 16),
            InkWell(
              onTap: () async {
                final Uri url = Uri.parse(
                  "https://github.com/fangzny1/GiantessNight_App",
                );
                if (!await launchUrl(
                  url,
                  mode: LaunchMode.externalApplication,
                )) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text("无法打开链接")));
                }
              },
              child: const Text(
                "基于https://github.com/fangzny1/GiantessNight_App项目改进",
                style: TextStyle(
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("确定"),
          ),
        ],
      ),
    );
  }

  // 【修复版】选择背景图片并永久保存
  Future<void> _pickWallpaper(BuildContext context) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      try {
        final prefs = await SharedPreferences.getInstance();

        // 1. 获取永久存储目录 (Documents)
        final appDir = await getApplicationDocumentsDirectory();
        final String fileName = 'permanent_wallpaper.jpg';
        final File permanentFile = File('${appDir.path}/$fileName');

        // 2. 将选择的图片复制到永久目录
        // 这一步是关键！防止被 CacheHelper 清理掉
        await File(image.path).copy(permanentFile.path);

        // 3. 记录这个永久路径
        await prefs.setString('custom_wallpaper', permanentFile.path);
        customWallpaperPath.value = permanentFile.path;

        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("背景设置成功！(已永久保存)")));
        }
      } catch (e) {
        print("背景保存失败: $e");
      }
    }
  }

  // 【修复版】清除背景图片
  Future<void> _clearWallpaper(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();

    // 同时也删除那个永久文件，节省空间
    if (customWallpaperPath.value != null) {
      try {
        final file = File(customWallpaperPath.value!);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }

    await prefs.remove('custom_wallpaper');
    customWallpaperPath.value = null;

    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("已恢复默认背景")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 如果有壁纸，Scaffold 背景透明
      backgroundColor: Colors.transparent, // 关键：让 ProfilePage 本身透明
      appBar: AppBar(
        title: const Text("个人中心"),
        backgroundColor: Colors.transparent, // AppBar 也透明
        elevation: 0,
        actions: [
          ValueListenableBuilder<ThemeMode>(
            valueListenable: currentTheme,
            builder: (context, mode, _) {
              bool isDark = mode == ThemeMode.dark;
              if (mode == ThemeMode.system)
                isDark =
                    MediaQuery.of(context).platformBrightness ==
                    Brightness.dark;
              return IconButton(
                icon: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
                onPressed: _toggleTheme,
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      // 监听用户名变化，触发重绘
      body: ValueListenableBuilder<String>(
        valueListenable: currentUser,
        builder: (context, username, child) {
          bool isLogin = username != "未登录";

          return ListView(
            children: [
              const SizedBox(height: 40),

              // === 头像区域 ===
              Center(
                child: GestureDetector(
                  // 点击头像跳转
                  onTap: isLogin ? () => _jumpToMyPosts(context) : null,
                  child: Stack(
                    children: [
                      // 使用 ValueListenableBuilder 监听头像变化
                      ValueListenableBuilder<String>(
                        valueListenable: currentUserAvatar,
                        builder: (context, avatarUrl, _) {
                          return CircleAvatar(
                            radius: 45,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            backgroundImage: (isLogin && avatarUrl.isNotEmpty)
                                ? CachedNetworkImageProvider(avatarUrl)
                                : null,
                            child: (!isLogin || avatarUrl.isEmpty)
                                ? const Icon(Icons.person, size: 50)
                                : null,
                          );
                        },
                      ),
                      // 如果已登录，显示一个小角标提示可以点击
                      if (isLogin)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.edit_note,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // === 用户名区域 ===
              Center(
                child: InkWell(
                  onTap: isLogin ? () => _jumpToMyPosts(context) : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: Column(
                      children: [
                        Text(
                          username,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (isLogin)
                          const Text(
                            "点击查看我的发布",
                            style: TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),
              if (isLogin)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green),
                    ),
                    child: const Text(
                      "已登录",
                      style: TextStyle(color: Colors.green, fontSize: 12),
                    ),
                  ),
                ),

              const SizedBox(height: 30),

              // ... 下面的菜单项 (书签、收藏等) 保持不变 ...
              ListTile(
                leading: const Icon(
                  Icons.bookmark_border,
                  color: Colors.purple,
                ),
                title: const Text("阅读书签"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const BookmarkPage()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.star_outline, color: Colors.orange),
                title: const Text("我的收藏"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const FavoritePage()),
                ),
              ),
              // 上次加的清除缓存
              ListTile(
                leading: const Icon(
                  Icons.cleaning_services_outlined,
                  color: Colors.blueGrey,
                ),
                title: const Text("清除缓存"),
                subtitle: const Text("管理存储空间"), // 加个副标题更好看
                trailing: const Icon(Icons.chevron_right),
                // 【修改】点击不再直接清理，而是弹窗询问
                onTap: () => _showClearCacheDialog(context),
              ),
              ListTile(
                leading: const Icon(
                  Icons.download_for_offline_outlined,
                  color: Colors.teal,
                ),
                title: const Text("离线缓存"),
                subtitle: const Text("管理已保存的帖子"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const OfflineListPage(),
                    ),
                  );
                },
              ),
              // 【新增】加载模式入口
              ListTile(
                leading: const Icon(
                  Icons.settings_ethernet,
                  color: Colors.deepPurple,
                ),
                title: const Text("加载模式设置"),
                subtitle: ValueListenableBuilder<bool>(
                  valueListenable: useDioProxyLoader,
                  builder: (context, value, _) {
                    return Text(
                      value ? "当前: 强力代理模式 (Dio)" : "当前: 原生模式 (WebView+Json解析)",
                    );
                  },
                ),
                trailing: const Icon(Icons.chevron_right),
                // onTap: () => _showLoadModeDialog(context),
              ),

              const Divider(),

              // 【新增】外观设置
              ListTile(
                leading: const Icon(Icons.image_outlined, color: Colors.teal),
                title: const Text("自定义背景"),
                subtitle: const Text("设置全局背景图片"),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (customWallpaperPath.value != null)
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () => _clearWallpaper(context),
                      ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => _pickWallpaper(context),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: transparentBarsEnabled,
                builder: (context, enabled, _) {
                  bool hasWallpaper = customWallpaperPath.value != null;
                  return SwitchListTile(
                    title: const Text("透明导航栏与顶栏"),
                    subtitle: const Text("需使用自定义背景"),
                    value: hasWallpaper ? enabled : false,
                    onChanged: hasWallpaper
                        ? (v) async {
                            transparentBarsEnabled.value = v;
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setBool('transparent_bars', v);
                          }
                        : null,
                  );
                },
              ),

              // 【新增】关于
              ListTile(
                leading: const Icon(Icons.info_outline, color: Colors.indigo),
                title: const Text("关于项目"),
                subtitle: const Text("GitHub 开源地址"),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showAboutDialog(context),
              ),
              const Divider(),

              if (!isLogin)
                ListTile(
                  leading: const Icon(Icons.login),
                  title: const Text("登录账号"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LoginPage(),
                      ),
                    );
                    if (result == true) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text("登录成功！")));
                      forumKey.currentState?.refreshData();
                    }
                  },
                ),

              if (isLogin)
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text(
                    "退出登录",
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () async {
                    await WebViewCookieManager().clearCookies();
                    final prefs = await SharedPreferences.getInstance();
                    // 【新增】清理所有用户信息
                    prefs.remove('username');
                    prefs.remove('uid');
                    prefs.remove('avatar');

                    currentUser.value = "未登录";
                    currentUserUid.value = "";
                    currentUserAvatar.value = "";
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class PlaceholderPage extends StatelessWidget {
  final String title;
  const PlaceholderPage({super.key, required this.title});
  @override
  Widget build(BuildContext context) => Center(child: Text(title));
}
