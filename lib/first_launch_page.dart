import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'miui_theme.dart';
import 'forum_model.dart';
import 'http_service.dart';
import 'login_page.dart';

class FirstLaunchPage extends StatefulWidget {
  final VoidCallback? onComplete;

  const FirstLaunchPage({super.key, this.onComplete});

  @override
  State<FirstLaunchPage> createState() => _FirstLaunchPageState();
}

class _FirstLaunchPageState extends State<FirstLaunchPage> {
  int _step = 0; // 0=线路选择, 1=登录/跳过
  String _selectedUrl = 'https://giantesswaltz.org/';
  bool _isApplying = false;

  final List<Map<String, dynamic>> _servers = [
    {
      'name': '主线路',
      'url': 'https://giantesswaltz.org/',
      'desc': '稳定性高，全球加速',
      'icon': Icons.public,
      'tag': '推荐',
    },
    {
      'name': '备用线路',
      'url': 'https://gtswaltz.org/',
      'desc': '国内直连访问优化',
      'icon': Icons.cloud_queue,
      'tag': '直连',
    },
  ];

  Future<void> _applyServer() async {
    setState(() => _isApplying = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_base_url', _selectedUrl);

      currentBaseUrl.value = _selectedUrl;
      HttpService().updateBaseUrl(_selectedUrl);

      // 清理旧缓存
      try {
        await DefaultCacheManager().emptyCache().timeout(
          const Duration(seconds: 2),
        );
        await globalImageCache.emptyCache().timeout(const Duration(seconds: 2));
      } catch (_) {}

      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();

      try {
        await WebViewCookieManager().clearCookies().timeout(
          const Duration(seconds: 2),
        );
      } catch (_) {}

      if (mounted) {
        setState(() {
          _isApplying = false;
          _step = 1;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isApplying = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("线路设置失败，请重试")));
      }
    }
  }

  Future<void> _completeSetup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('first_launch_completed', true);
    await prefs.setString('last_launch_version', kAppVersion);

    if (mounted) {
      if (widget.onComplete != null) {
        widget.onComplete!();
      } else {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: _step == 0 ? _buildServerSelect() : _buildLoginStep(),
        ),
      ),
    );
  }

  Widget _buildServerSelect() {
    return Column(
      key: const ValueKey('server'),
      children: [
        const Spacer(flex: 2),
        // Logo 区域
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: MiuiTheme.primaryColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: MiuiTheme.primaryColor.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.waving_hand, color: Colors.white, size: 36),
        ),
        const SizedBox(height: 24),
        Center(
          child: const Text(
            "欢迎使用",
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
          ),
        ),
        Center(
          child: const Text(
            "GiantessWaltz第三方客户端",
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "请先选择服务器线路",
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
        const Spacer(),
        // 服务器选择卡片
        ..._servers.map((server) {
          final bool isSelected = _selectedUrl == server['url'];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
            child: GestureDetector(
              onTap: () => setState(() => _selectedUrl = server['url']),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isSelected
                      ? MiuiTheme.primaryColor.withOpacity(0.08)
                      : Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected
                        ? MiuiTheme.primaryColor
                        : Colors.transparent,
                    width: 2,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: MiuiTheme.primaryColor.withOpacity(0.15),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? MiuiTheme.primaryColor.withOpacity(0.15)
                            : Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        server['icon'] as IconData,
                        color: isSelected
                            ? MiuiTheme.primaryColor
                            : Colors.grey,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                server['name'] as String,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? MiuiTheme.primaryColor
                                      : Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      (server['tag'] == '推荐'
                                              ? MiuiTheme.orange
                                              : MiuiTheme.green)
                                          .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  server['tag'] as String,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: server['tag'] == '推荐'
                                        ? MiuiTheme.orange
                                        : MiuiTheme.green,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            server['desc'] as String,
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? MiuiTheme.primaryColor
                            : Colors.transparent,
                        border: Border.all(
                          color: isSelected
                              ? MiuiTheme.primaryColor
                              : Colors.grey.withOpacity(0.4),
                          width: 2,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              size: 14,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        const Spacer(),
        // 确认按钮
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isApplying ? null : _applyServer,
              style: ElevatedButton.styleFrom(
                backgroundColor: MiuiTheme.primaryColor,
                disabledBackgroundColor: MiuiTheme.primaryColor.withOpacity(
                  0.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isApplying
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      "确认选择",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildLoginStep() {
    return Stack(
      key: const ValueKey('login'),
      children: [
        LoginPage(
          onLoginSuccess: _completeSetup,
          showSkip: true,
          onSkip: _completeSetup,
        ),
      ],
    );
  }
}
