import 'package:flutter/material.dart';
import 'offline_manager.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isSelectionMode ? "已选 ${_selectedTids.length} 项" : "离线缓存"),
        actions: [
          if (_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _deleteSelected,
            )
          else
            IconButton(
              icon: const Icon(Icons.checklist),
              onPressed: () => setState(() => _isSelectionMode = true),
              tooltip: "多选管理",
            ),
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
      body: _list.isEmpty
          ? const Center(
              child: Text("暂无离线帖子", style: TextStyle(color: Colors.grey)),
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
    );
  }
}
