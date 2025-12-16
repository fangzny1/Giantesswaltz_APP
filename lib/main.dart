import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
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
          title: 'GiantessNight',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF6750A4),
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF6750A4),
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

  @override
  void initState() {
    super.initState();
    _initHiddenWebView();
  }

  // 【修复点】这就是之前报错缺失的方法，现在补上了
  void refreshData() {
    if (!mounted) return;
    print("🔄 收到外部刷新请求...");
    _fetchData();
  }

  // 在 _ForumHomePageState 类中

  Future<void> _initHiddenWebView() async {
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
          domain: 'giantessnight.com',
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
                  domain: 'giantessnight.com', // 关键！必须是这个域名
                ),
              );
              await cookieMgr.setCookie(
                WebViewCookie(
                  name: key,
                  value: value,
                  domain: 'www.giantessnight.com', //以此类推，www也加一份
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
                  'https://www.giantessnight.com/gnforum2012/api/mobile/index.php?version=4&module=forumindex&t=$timestamp',
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

  // ==========================================
  // 2. 初始预热方法
  // ==========================================
  void _fetchData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    // 【新增】每次刷新前清理 WebView 缓存，确保 Cookie 状态重置
    // 这样能解决"第一次行第二次不行"的问题
    try {
      await _hiddenController?.clearCache();
    } catch (e) {
      // 忽略清理失败
    }

    print("🔄 开始预热 Session (身份统一: 手机版)...");

    // 预热使用 mobile=2，与登录态保持一致
    _hiddenController?.loadRequest(
      Uri.parse('https://www.giantessnight.com/gnforum2012/forum.php?mobile=2'),
    );
  }

  // ==========================================
  // 3. 核心解析逻辑 (修复了重复定义和解析兼容性)
  // ==========================================
  Future<void> _parsePageContent() async {
    if (_hiddenController == null) return;
    try {
      final String content =
          await _hiddenController!.runJavaScriptReturningResult(
                "document.body.innerText",
              )
              as String;

      // 清洗数据
      String jsonString = content;
      if (jsonString.startsWith('"') && jsonString.endsWith('"')) {
        jsonString = jsonString.substring(1, jsonString.length - 1);
        jsonString = jsonString.replaceAll('\\"', '"').replaceAll('\\\\', '\\');
      }

      print(
        "📄 服务器返回原始内容: ${jsonString.length > 100 ? jsonString.substring(0, 100) + '...' : jsonString}",
      );

      var data;
      try {
        data = jsonDecode(jsonString);
      } catch (e) {
        print("❌ JSON 格式错误，服务器返回的可能不是数据");
        if (mounted)
          setState(() {
            _isLoading = false;
          });
        return;
      }

      // 处理 to_login 错误 (Cookie 失效)
      if (data['error'] == 'to_login' ||
          (data['Message'] != null &&
              data['Message']['messageval'] == 'to_login')) {
        print("⚠️ 检测到 Cookie 失效或需要登录");
        // 这里可以选择清理本地缓存，或者只是停止加载
        if (mounted)
          setState(() {
            _isLoading = false;
          });
        return;
      }

      if (data['Variables'] == null) {
        print("⚠️ 数据解析异常: 缺少 Variables 字段");
        if (mounted)
          setState(() {
            _isLoading = false;
          });
        return;
      }

      // === 开始解析 Variables ===
      var variables = data['Variables'];

      // 1. 更新用户信息
      String newName = variables['member_username'].toString();
      String newUid = variables['member_uid'].toString();
      final prefs = await SharedPreferences.getInstance();

      // 只要服务器返回了有效的用户名，就更新状态
      if (newName.isNotEmpty) {
        if (newName != currentUser.value) {
          currentUser.value = newName;
          await prefs.setString('username', newName);
        }

        // 独立更新 UID 和头像 (不依赖用户名是否变化)
        if (newUid.isNotEmpty && newUid != "0") {
          if (newUid != currentUserUid.value) {
            currentUserUid.value = newUid;
            await prefs.setString('uid', newUid);
          }

          String avatarUrl =
              "https://www.giantessnight.com/gnforum2012/uc_server/avatar.php?uid=$newUid&size=middle";

          // 确保头像 URL 被设置 (即使用户名没变)
          if (currentUserAvatar.value != avatarUrl) {
            currentUserAvatar.value = avatarUrl;
            await prefs.setString('avatar', avatarUrl);
          }
        }
      }

      // 2. 解析分区 (catlist) - 兼容 List 和 Map
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

      // 3. 解析板块 (forumlist) - 兼容 List 和 Map
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

      if (mounted) {
        setState(() {
          _categories = tempCats;
          _forumsMap = tempForumMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      print("❌ 解析过程报错: $e");
      if (mounted)
        setState(() {
          _isLoading = false;
        });
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
                    title: const Text("GiantessNight"),
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

  // 【新增】显示清理缓存选项弹窗
  // 【修正版】显示清理缓存选项弹窗
  void _showClearCacheDialog(BuildContext context) async {
    // 1. 先计算当前大小
    String cacheSizeStr = "计算中...";
    String debugInfo = "";
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
            const Text("GiantessNight 第三方客户端"),
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
                "https://github.com/fangzny1/GiantessNight_App",
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

  // 【新增】选择背景图片
  Future<void> _pickWallpaper(BuildContext context) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('custom_wallpaper', image.path);
      customWallpaperPath.value = image.path;
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("背景设置成功！")));
      }
    }
  }

  // 【新增】清除背景图片
  Future<void> _clearWallpaper(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
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
