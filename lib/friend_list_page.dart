import 'dart:io';

import 'package:flutter/material.dart';
import 'main.dart';

import 'forum_extras_api.dart';
import 'user_detail_page.dart';

/// 好友列表（module=friend）。
class FriendListPage extends StatefulWidget {
  final String uid;
  const FriendListPage({super.key, required this.uid});

  @override
  State<FriendListPage> createState() => _FriendListPageState();
}

class _FriendListPageState extends State<FriendListPage> {
  List<FriendEntry> _friends = [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final friends = await fetchFriends(widget.uid);
      if (mounted) setState(() => _friends = friends);
    } catch (e) {
      if (mounted) _error = "加载失败: $e";
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation:
          Listenable.merge([customWallpaperPath, transparentBarsEnabled]),
      builder: (context, _) {
        final wallpaperPath = customWallpaperPath.value;
        final useTransparent =
            wallpaperPath != null && transparentBarsEnabled.value;
        return Scaffold(
          backgroundColor: wallpaperPath != null
              ? (useTransparent
                  ? Colors.transparent
                  : Theme.of(context).colorScheme.surfaceContainerHighest)
              : null,
          extendBodyBehindAppBar: useTransparent,
          appBar: AppBar(
            title: const Text("好友"),
            backgroundColor: useTransparent ? Colors.transparent : null,
            elevation: useTransparent ? 0 : null,
          ),
          body: Stack(
            children: [
                if (wallpaperPath != null)
                  Positioned.fill(
                    child: Image.file(
                      File(wallpaperPath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(),
                    ),
                  ),
                if (wallpaperPath != null)
                  Positioned.fill(
                    child: Container(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.black.withOpacity(0.6)
                          : Colors.white.withOpacity(0.3),
                    ),
                  ),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.zero,
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error.isNotEmpty
                          ? Center(child: Text(_error))
                          : _friends.isEmpty
                              ? const Center(
                                  child: Text("暂无好友",
                                      style: TextStyle(color: Colors.grey)),
                                )
                              : ListView.builder(
                                  itemCount: _friends.length,
                                  itemBuilder: (context, i) {
                                    final f = _friends[i];
                                    return ListTile(
                                      leading: CircleAvatar(
                                          child: Text(f.username.isNotEmpty
                                              ? f.username[0]
                                              : "?")),
                                      title: Text(f.username),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () => adaptivePush(
                                        context,
                                        UserDetailPage(
                                          username: f.username,
                                          uid: f.uid,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
