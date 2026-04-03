import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // 图片缓存与网络设置
  double _imageTimeout = 15.0;
  double _cacheMaxObjects = 1000.0;
  double _cacheStaleDays = 7.0;

  bool _isLoading = true;

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
      _isLoading = false;
    });
  }

  Future<void> _saveIntSetting(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("设置已保存，重启 App 后生效")));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text("高级设置")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ================= 网络引擎设置 =================
          const Text(
            "网络与加载引擎",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
          ),
          const SizedBox(height: 10),
          Card(
            elevation: 0,
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withOpacity(0.5),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "图片下载超时时间 (秒)",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Text(
                    "国内直连备用域名时速度极慢。调小此值可让卡住的图片尽早报错，方便您手动点击重连；调大此值适合挂梯子时下载几MB的高清原图。",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Slider(
                    value: _imageTimeout,
                    min: 5,
                    max: 60,
                    divisions: 11,
                    label: "${_imageTimeout.toInt()} 秒",
                    onChanged: (v) => setState(() => _imageTimeout = v),
                    onChangeEnd: (v) =>
                        _saveIntSetting('image_timeout_seconds', v.toInt()),
                  ),
                  Center(
                    child: Text(
                      "当前: ${_imageTimeout.toInt()} 秒",
                      style: const TextStyle(
                        color: Colors.teal,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ================= 图片缓存设置 =================
          const Text(
            "图片缓存策略 (CachedNetworkImage)",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
          ),
          const SizedBox(height: 10),
          Card(
            elevation: 0,
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withOpacity(0.5),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "最大图片缓存数量 (张)",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Slider(
                    value: _cacheMaxObjects,
                    min: 200,
                    max: 3000,
                    divisions: 14,
                    label: "${_cacheMaxObjects.toInt()} 张",
                    onChanged: (v) => setState(() => _cacheMaxObjects = v),
                    onChangeEnd: (v) =>
                        _saveIntSetting('cache_max_objects', v.toInt()),
                  ),
                  Center(child: Text("当前: ${_cacheMaxObjects.toInt()} 张")),

                  const Divider(height: 30),

                  const Text(
                    "缓存最长保留时间 (天)",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Slider(
                    value: _cacheStaleDays,
                    min: 1,
                    max: 30,
                    divisions: 29,
                    label: "${_cacheStaleDays.toInt()} 天",
                    onChanged: (v) => setState(() => _cacheStaleDays = v),
                    onChangeEnd: (v) =>
                        _saveIntSetting('cache_stale_days', v.toInt()),
                  ),
                  Center(child: Text("当前: ${_cacheStaleDays.toInt()} 天")),
                ],
              ),
            ),
          ),

          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              "※ 更改以上设置需彻底关闭并重新打开 App 才会生效。",
              style: TextStyle(color: Colors.redAccent, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
