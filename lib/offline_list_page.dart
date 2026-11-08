import 'dart:io';

import 'package:flutter/material.dart';
import 'package:giantesswaltz_app/main.dart';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'offline_manager.dart';
import 'offline_transfer.dart';
import 'offline_search_page.dart';
import 'thread_detail_page.dart';

class OfflineListPage extends StatefulWidget {
  const OfflineListPage({super.key});

  @override
  State<OfflineListPage> createState() => _OfflineListPageState();
}

class _OfflineListPageState extends State<OfflineListPage> {
  List<Map<String, dynamic>> _list = [];
  bool _isSelectionMode = false;
  final Set<String> _selectedTids = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    final data = await OfflineManager().getOfflineList();
    setState(() {
      _list = data;
    });
  }

  void _deleteSelected() async {
    if (_selectedTids.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("删除缓存"),
        content: Text("确定删除选中的 ${_selectedTids.length} 个记录吗？"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              for (var tid in _selectedTids) {
                await OfflineManager().deleteThread(tid);
              }
              setState(() {
                _isSelectionMode = false;
                _selectedTids.clear();
              });
              _loadData();
              if (mounted)
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text("删除成功")));
            },
            child: const Text("删除", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _exportBackup() async {
    try {
      final dirPath = await OfflineManager().getStoragePath();
      final dir = Directory(dirPath);
      final hasData = dir
          .listSync()
          .whereType<File>()
          .any((f) => f.path.endsWith('.json'));
      if (!hasData) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("暂无离线数据可导出")),
          );
        }
        return;
      }
      final bytes = buildOfflineZipBytes(dir);
      final tmp = await getTemporaryDirectory();
      final stamp = DateTime.now()
          .toString()
          .substring(0, 16)
          .replaceAll(':', '-');
      final out = File('${tmp.path}/gw_offline_backup_$stamp.zip');
      await out.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(out.path)],
        subject: 'GW 离线数据备份',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("导出失败: $e")),
        );
      }
    }
  }

  Future<void> _importBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      final path = result?.files.single.path;
      if (path == null) return;
      final dirPath = await OfflineManager().getStoragePath();
      final bytes = await File(path).readAsBytes();
      final count = restoreOfflineZipBytes(bytes, Directory(dirPath));
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "✅ 已导入 $count 个离线数据文件，图片会在阅读时自动重新缓存",
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("导入失败: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: customWallpaperPath,
      builder: (context, wallpaperPath, _) {
        return Scaffold(
          backgroundColor: wallpaperPath != null
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : null,
          appBar: AppBar(
            title: Text(
              _isSelectionMode ? "已选 ${_selectedTids.length} 项" : "离线缓存",
            ),
            actions: [
              if (_isSelectionMode)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _deleteSelected,
                )
              else ...[
                IconButton(
                  icon: const Icon(Icons.manage_search),
                  tooltip: "全文搜索离线内容",
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (c) => const OfflineSearchPage(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.checklist),
                  onPressed: () => setState(() => _isSelectionMode = true),
                  tooltip: "多选管理",
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (v) {
                    if (v == 'export') _exportBackup();
                    if (v == 'import') _importBackup();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'export',
                      child: Text("导出离线备份 (ZIP)"),
                    ),
                    PopupMenuItem(
                      value: 'import',
                      child: Text("导入离线备份 (ZIP)"),
                    ),
                  ],
                ),
              ],
            ],
            leading: _isSelectionMode
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _isSelectionMode = false;
                      _selectedTids.clear();
                    }),
                  )
                : null,
          ),
          body: Stack(
            children: [
              if (wallpaperPath != null) ...[
                Positioned.fill(
                  child: Image.file(File(wallpaperPath), fit: BoxFit.cover),
                ),
                Positioned.fill(
                  child: Container(color: Colors.black.withOpacity(0.5)),
                ),
              ],
              _list.isEmpty
                  ? const Center(
                      child: Text(
                        "暂无离线帖子",
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _list.length,
                      itemBuilder: (ctx, i) {
                        final item = _list[i];
                        final tid = item['tid'] as String;
                        final isSelected = _selectedTids.contains(tid);

                        return ListTile(
                          leading: _isSelectionMode
                              ? Checkbox(
                                  value: isSelected,
                                  onChanged: (v) {
                                    setState(() {
                                      if (v == true)
                                        _selectedTids.add(tid);
                                      else
                                        _selectedTids.remove(tid);
                                    });
                                  },
                                )
                              : CircleAvatar(
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                                  child: const Icon(Icons.download_done),
                                ),
                          title: Text(
                            item['subject'] ?? "无标题",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            "${item['author']} · 已缓存至第 ${item['max_page']} 页",
                          ),
                          trailing: _isSelectionMode
                              ? null
                              : const Icon(Icons.chevron_right),
                          onTap: () {
                            if (_isSelectionMode) {
                              setState(() {
                                if (isSelected)
                                  _selectedTids.remove(tid);
                                else
                                  _selectedTids.add(tid);
                              });
                            } else {
                              // 跳转阅读
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (ctx) => ThreadDetailPage(
                                    tid: tid,
                                    subject: item['subject'],
                                    // 【核心修复】传入离线保存的 authorId
                                    initialAuthorId: item['author_id'],
                                  ),
                                ),
                              );
                            }
                          },
                          onLongPress: () {
                            if (!_isSelectionMode) {
                              setState(() {
                                _isSelectionMode = true;
                                _selectedTids.add(tid);
                              });
                            }
                          },
                        );
                      },
                    ),
            ],
          ),
        );
      },
    );
  }
}
