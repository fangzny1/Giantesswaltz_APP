import 'package:flutter/material.dart';
import 'history_manager.dart';
import 'thread_detail_page.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<HistoryItem> _list = [];
  bool _isEditMode = false;
  final Set<String> _selectedTids = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    final data = await HistoryManager.getHistory();
    setState(() => _list = data);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? "已选 ${_selectedTids.length} 项" : "足迹 (30天内)"),
        actions: [
          if (!_isEditMode)
            IconButton(
              icon: const Icon(Icons.edit_note),
              onPressed: () => setState(() => _isEditMode = true),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: () {
                HistoryManager.clearAll();
                _loadData();
                setState(() => _isEditMode = false);
              },
              tooltip: "清空全部",
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () async {
                await HistoryManager.deleteItems(_selectedTids);
                setState(() {
                  _isEditMode = false;
                  _selectedTids.clear();
                });
                _loadData();
              },
            ),
          ],
        ],
      ),
      body: _list.isEmpty
          ? const Center(child: Text("还没有留下足迹"))
          : ListView.builder(
              itemCount: _list.length,
              itemBuilder: (context, index) {
                final item = _list[index];
                final date = DateTime.fromMillisecondsSinceEpoch(
                  item.timestamp,
                );
                return ListTile(
                  leading: _isEditMode
                      ? Checkbox(
                          value: _selectedTids.contains(item.tid),
                          onChanged: (v) {
                            setState(() {
                              if (v!)
                                _selectedTids.add(item.tid);
                              else
                                _selectedTids.remove(item.tid);
                            });
                          },
                        )
                      : const Icon(Icons.history),
                  title: Text(
                    item.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    "${item.author} · ${date.month}-${date.day} ${date.hour}:${date.minute}",
                  ),
                  onTap: () {
                    if (_isEditMode) {
                      setState(() {
                        if (_selectedTids.contains(item.tid))
                          _selectedTids.remove(item.tid);
                        else
                          _selectedTids.add(item.tid);
                      });
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (c) => ThreadDetailPage(
                            tid: item.tid,
                            subject: item.subject,
                          ),
                        ),
                      );
                    }
                  },
                );
              },
            ),
    );
  }
}
