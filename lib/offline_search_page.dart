import 'package:flutter/material.dart';

import 'offline_search_service.dart';
import 'thread_detail_page.dart';

/// 离线全文搜索：在已离线的帖子内容里搜台词/关键词，直达对应楼层。
class OfflineSearchPage extends StatefulWidget {
  const OfflineSearchPage({super.key});

  @override
  State<OfflineSearchPage> createState() => _OfflineSearchPageState();
}

class _OfflineSearchPageState extends State<OfflineSearchPage> {
  final TextEditingController _controller = TextEditingController();
  final OfflineSearchService _service = OfflineSearchService();

  bool _searching = false;
  String _lastQuery = "";
  List<OfflineSearchHit> _hits = [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _doSearch() async {
    final query = _controller.text.trim();
    if (query.isEmpty || _searching) return;
    setState(() {
      _searching = true;
      _lastQuery = query;
    });
    try {
      final hits = await _service.search(query);
      if (mounted) setState(() => _hits = hits);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _openHit(OfflineSearchHit hit) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (c) => ThreadDetailPage(
          tid: hit.tid,
          subject: hit.subject,
          initialAuthorId: hit.authorId,
          initialPage: hit.page,
          initialTargetPid: hit.isTitleHit ? null : hit.pid,
          initialTargetFloor: hit.isTitleHit ? null : "${hit.floor}",
        ),
      ),
    );
  }

  Widget _buildSnippet(OfflineSearchHit hit, ThemeData theme) {
    final text = hit.text;
    final from = (hit.matchStart - OfflineSearchService.snippetRadius)
        .clamp(0, text.length);
    final to = (hit.matchStart +
            hit.matchLength +
            OfflineSearchService.snippetRadius)
        .clamp(0, text.length);
    final matchEnd = (hit.matchStart + hit.matchLength).clamp(from, to);
    return Text.rich(
      TextSpan(
        children: [
          if (from > 0) const TextSpan(text: "…"),
          TextSpan(text: text.substring(from, hit.matchStart)),
          TextSpan(
            text: text.substring(hit.matchStart, matchEnd),
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(text: text.substring(matchEnd, to)),
          if (to < text.length) const TextSpan(text: "…"),
        ],
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13, height: 1.4),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text("离线全文搜索")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _doSearch(),
              decoration: InputDecoration(
                hintText: "搜索已离线帖子的正文内容…",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _doSearch,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          if (_searching) const LinearProgressIndicator(),
          if (!_searching && _lastQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _hits.isEmpty
                      ? "「$_lastQuery」没有命中。只搜索已离线帖子的标题、作者和正文，试试台词片段或作者名"
                      : "「$_lastQuery」命中 ${_hits.length} 楼",
                  style: TextStyle(color: theme.hintColor, fontSize: 12),
                ),
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _hits.length,
              itemBuilder: (context, i) {
                final hit = _hits[i];
                return ListTile(
                  title: Text(
                    hit.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hit.isTitleHit
                            ? "标题/作者命中 · 直达第一页"
                            : "第 ${hit.floor} 楼 · ${hit.author}",
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      _buildSnippet(hit, theme),
                    ],
                  ),
                  isThreeLine: true,
                  onTap: () => _openHit(hit),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
