import 'package:flutter/material.dart';
import 'package:giantesswaltz_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'miui_theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  double _imageTimeout = 15.0;
  double _cacheMaxObjects = 1000.0;
  double _cacheStaleDays = 7.0;
  double _cardOpacity = 0.7;
  String _transitionType = "default";
  String _colorSchemeMode = "default";
  Color _seedColorValue = MiuiTheme.primaryColor;
  bool _isLoading = true;

  static const Map<String, String> _transitionLabels = {
    "default": "默认",
    "fade": "淡入淡出",
    "slide_left": "左侧滑入",
    "slide_up": "底部上滑",
    "scale": "缩放动画",
    "slide_right": "右侧滑入",
    "rotation": "旋转动画",
  };

  static const List<Color> _presetColors = [
    Color(0xFF1677FF), // 小米蓝
    Color(0xFFFF6B00), // 橙色
    Color(0xFF00B365), // 绿色
    Color(0xFFE53935), // 红色
    Color(0xFF9C27B0), // 紫色
    Color(0xFF00BCD4), // 青色
    Color(0xFFFF9800), // 琥珀
    Color(0xFF795548), // 棕色
    Color(0xFF607D8B), // 蓝灰
    Color(0xFFE91E63), // 粉色
    Color(0xFF3F51B5), // 靛蓝
    Color(0xFFFF5722), // 深橙
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _imageTimeout = (prefs.getInt('image_timeout_seconds') ?? 15).toDouble();
      _cacheMaxObjects = (prefs.getInt('cache_max_objects') ?? 1000).toDouble();
      _cacheStaleDays = (prefs.getInt('cache_stale_days') ?? 7).toDouble();
      _cardOpacity = prefs.getDouble('forum_card_opacity') ?? 0.7;
      _transitionType = prefs.getString('transition_animation_type') ?? "default";
      _colorSchemeMode = prefs.getString('color_scheme_mode') ?? "default";
      final int? seedVal = prefs.getInt('seed_color');
      if (seedVal != null) _seedColorValue = Color(seedVal);
      _isLoading = false;
    });
  }

  Future<void> _saveIntSetting(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("设置已保存，重启 App 后生效"),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildColorModeChip(String label, String mode) {
    final isSelected = _colorSchemeMode == mode;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => _setColorMode(mode),
      selectedColor: MiuiTheme.primaryColor.withOpacity(0.15),
      labelStyle: TextStyle(
        color: isSelected ? MiuiTheme.primaryColor : MiuiTheme.textSecondary,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        fontSize: 13,
      ),
      side: BorderSide(
        color: isSelected ? MiuiTheme.primaryColor : Colors.grey.withOpacity(0.3),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Future<void> _setColorMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    if (mode == "default") {
      seedColor.value = null;
      colorSchemeMode.value = "default";
      await prefs.setString('color_scheme_mode', "default");
      await prefs.remove('seed_color');
      setState(() {
        _colorSchemeMode = "default";
        _seedColorValue = MiuiTheme.primaryColor;
      });
    } else {
      setState(() => _colorSchemeMode = mode);
      await prefs.setString('color_scheme_mode', mode);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("主题色彩已更新"),
          behavior: SnackBarBehavior.floating,
          duration: Duration(milliseconds: 800),
        ),
      );
    }
  }

  Future<void> _selectPresetColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    seedColor.value = color;
    colorSchemeMode.value = "preset";
    await prefs.setInt('seed_color', color.value);
    await prefs.setString('color_scheme_mode', "preset");
    setState(() {
      _seedColorValue = color;
      _colorSchemeMode = "preset";
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("主题色彩已更新"),
          behavior: SnackBarBehavior.floating,
          duration: Duration(milliseconds: 800),
        ),
      );
    }
  }

  Future<void> _extractFromWallpaper(String wallpaperPath) async {
    final color = await extractWallpaperColor(wallpaperPath);
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    seedColor.value = color;
    colorSchemeMode.value = "wallpaper";
    await prefs.setInt('seed_color', color.value);
    await prefs.setString('color_scheme_mode', "wallpaper");
    setState(() {
      _seedColorValue = color;
      _colorSchemeMode = "wallpaper";
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("已从壁纸提取主题色"),
          behavior: SnackBarBehavior.floating,
          duration: Duration(milliseconds: 800),
        ),
      );
    }
  }

  Future<void> _resetToDefaultColor() async {
    final prefs = await SharedPreferences.getInstance();
    seedColor.value = null;
    colorSchemeMode.value = "default";
    await prefs.setString('color_scheme_mode', "default");
    await prefs.remove('seed_color');
    setState(() {
      _colorSchemeMode = "default";
      _seedColorValue = MiuiTheme.primaryColor;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("已恢复默认色彩"),
          behavior: SnackBarBehavior.floating,
          duration: Duration(milliseconds: 800),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: MiuiTheme.primaryColor),
        ),
      );
    }

    return ValueListenableBuilder<String?>(
      valueListenable: customWallpaperPath,
      builder: (context, path, _) {
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            title: const Text("高级设置"),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSectionHeader("外观与动画"),
              const SizedBox(height: 10),
              _buildSettingCard(
                children: [
                  _buildSettingTitle("分区卡片透明度 (需自定义背景)"),
                  const SizedBox(height: 2),
                  Text(
                    "控制背景图片上方卡片与列表项的透明度",
                    style: TextStyle(fontSize: 12, color: MiuiTheme.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<String?>(
                    valueListenable: customWallpaperPath,
                    builder: (context, wallpaperPath, _) {
                      final bool hasWallpaper = wallpaperPath != null;
                      return Slider(
                        value: _cardOpacity,
                        min: 0.1,
                        max: 1.0,
                        divisions: 18,
                        activeColor: hasWallpaper ? MiuiTheme.primaryColor : Colors.grey,
                        inactiveColor: Colors.grey.withOpacity(0.3),
                        label: "${(_cardOpacity * 100).toInt()}%",
                        onChanged: hasWallpaper
                            ? (v) => setState(() => _cardOpacity = v)
                            : null,
                        onChangeEnd: hasWallpaper
                            ? (v) async {
                                forumCardOpacity.value = v;
                                final prefs = await SharedPreferences.getInstance();
                                await prefs.setDouble('forum_card_opacity', v);
                              }
                            : null,
                      );
                    },
                  ),
                  Center(
                    child: Text(
                      "当前: ${(_cardOpacity * 100).toInt()}%",
                      style: const TextStyle(
                        color: MiuiTheme.primaryColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildSettingCard(
                children: [
                  _buildSettingTitle("页面切换动画"),
                  const SizedBox(height: 2),
                  Text(
                    "选择页面跳转时的过渡动画效果",
                    style: TextStyle(fontSize: 12, color: MiuiTheme.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _showTransitionPicker(context),
                      icon: const Icon(Icons.animation, size: 18),
                      label: Text(
                        _transitionLabels[_transitionType] ?? "默认",
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MiuiTheme.primaryColor,
                        side: const BorderSide(color: MiuiTheme.primaryColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              _buildSettingCard(
                children: [
                  _buildSettingTitle("主题色彩 (MD3 动态取色)"),
                  const SizedBox(height: 2),
                  Text(
                    "选择默认色彩、预设颜色或从壁纸提取主题色",
                    style: TextStyle(fontSize: 12, color: MiuiTheme.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  // Mode toggle: default / preset / wallpaper
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildColorModeChip("默认", "default"),
                      _buildColorModeChip("预设", "preset"),
                      _buildColorModeChip("壁纸", "wallpaper"),
                    ],
                  ),
                  // Preset color grid (only visible in preset mode)
                  if (_colorSchemeMode == "preset") ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _presetColors.map((color) {
                        final isSelected = _seedColorValue.value == color.value;
                        return GestureDetector(
                          onTap: () => _selectPresetColor(color),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? Colors.white : Colors.transparent,
                                width: 3,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: color.withOpacity(0.5),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: isSelected
                                ? const Icon(Icons.check, color: Colors.white, size: 20)
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  // Wallpaper extract button
                  if (_colorSchemeMode == "wallpaper") ...[
                    const SizedBox(height: 12),
                    ValueListenableBuilder<String?>(
                      valueListenable: customWallpaperPath,
                      builder: (context, wallpaperPath, _) {
                        return SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: wallpaperPath != null
                                ? () => _extractFromWallpaper(wallpaperPath)
                                : null,
                            icon: const Icon(Icons.palette, size: 18),
                            label: Text(wallpaperPath != null ? "从壁纸提取主题色" : "请先设置自定义壁纸"),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: MiuiTheme.primaryColor,
                              side: const BorderSide(color: MiuiTheme.primaryColor),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        );
                      },
                    ),
                    if (_colorSchemeMode == "wallpaper" && _seedColorValue != MiuiTheme.primaryColor) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: _seedColorValue,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "已提取主题色",
                            style: TextStyle(
                              fontSize: 12,
                              color: MiuiTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                  // Reset to default
                  if (_colorSchemeMode != "default") ...[
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _resetToDefaultColor,
                      icon: const Icon(Icons.restore, size: 16),
                      label: const Text("恢复默认色彩"),
                      style: TextButton.styleFrom(
                        foregroundColor: MiuiTheme.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 24),
              _buildSectionHeader("网络与加载引擎"),
              const SizedBox(height: 10),
              _buildSettingCard(
                children: [
                  _buildSettingTitle("图片下载超时时间 (秒)"),
                  const SizedBox(height: 2),
                  Text(
                    "国内直连备用域名时速度极慢。调小此值可让卡住的图片尽早报错；调大此值适合下载高清原图。",
                    style: TextStyle(fontSize: 12, color: MiuiTheme.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Slider(
                    value: _imageTimeout,
                    min: 5,
                    max: 60,
                    divisions: 11,
                    activeColor: MiuiTheme.primaryColor,
                    label: "${_imageTimeout.toInt()} 秒",
                    onChanged: (v) => setState(() => _imageTimeout = v),
                    onChangeEnd: (v) => _saveIntSetting(
                      'image_timeout_seconds',
                      v.toInt(),
                    ),
                  ),
                  Center(
                    child: Text(
                      "当前: ${_imageTimeout.toInt()} 秒",
                      style: const TextStyle(
                        color: MiuiTheme.primaryColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              _buildSectionHeader("图片缓存策略"),
              const SizedBox(height: 10),
              _buildSettingCard(
                children: [
                  _buildSettingTitle("最大图片缓存数量 (张)"),
                  const SizedBox(height: 4),
                  Slider(
                    value: _cacheMaxObjects,
                    min: 200,
                    max: 3000,
                    divisions: 14,
                    activeColor: MiuiTheme.primaryColor,
                    label: "${_cacheMaxObjects.toInt()} 张",
                    onChanged: (v) => setState(() => _cacheMaxObjects = v),
                    onChangeEnd: (v) =>
                        _saveIntSetting('cache_max_objects', v.toInt()),
                  ),
                  Center(
                    child: Text(
                      "当前: ${_cacheMaxObjects.toInt()} 张",
                      style: const TextStyle(
                        color: MiuiTheme.primaryColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSettingTitle("缓存最长保留时间 (天)"),
                  const SizedBox(height: 4),
                  Slider(
                    value: _cacheStaleDays,
                    min: 1,
                    max: 30,
                    divisions: 29,
                    activeColor: MiuiTheme.primaryColor,
                    label: "${_cacheStaleDays.toInt()} 天",
                    onChanged: (v) => setState(() => _cacheStaleDays = v),
                    onChangeEnd: (v) =>
                        _saveIntSetting('cache_stale_days', v.toInt()),
                  ),
                  Center(
                    child: Text(
                      "当前: ${_cacheStaleDays.toInt()} 天",
                      style: const TextStyle(
                        color: MiuiTheme.primaryColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: MiuiTheme.orange.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: MiuiTheme.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "更改以上设置需彻底关闭并重新打开 App 才会生效。",
                        style: TextStyle(
                          color: MiuiTheme.orange,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  void _showTransitionPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Text(
                        "选择页面切换动画",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Divider(),
                    ..._transitionLabels.entries.map((entry) {
                  final bool isSelected = _transitionType == entry.key;
                  return ListTile(
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? MiuiTheme.primaryColor.withOpacity(0.1)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _iconForTransition(entry.key),
                        color: isSelected ? MiuiTheme.primaryColor : Colors.grey,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      entry.value,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected
                            ? MiuiTheme.primaryColor
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: MiuiTheme.primaryColor, size: 20)
                        : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onTap: () async {
                      setState(() => _transitionType = entry.key);
                      transitionAnimationType.value = entry.key;
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('transition_animation_type', entry.key);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("已切换为: ${entry.value}"),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
      },
    );
  }

  IconData _iconForTransition(String type) {
    switch (type) {
      case "fade":
        return Icons.blur_on;
      case "slide_left":
        return Icons.arrow_back_ios;
      case "slide_up":
        return Icons.vertical_align_top;
      case "scale":
        return Icons.zoom_out_map;
      case "slide_right":
        return Icons.arrow_forward_ios;
      case "rotation":
        return Icons.rotate_right;
      default:
        return Icons.swipe;
    }
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 15,
        color: MiuiTheme.primaryColor,
      ),
    );
  }

  Widget _buildSettingTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 14,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }

  Widget _buildSettingCard({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
