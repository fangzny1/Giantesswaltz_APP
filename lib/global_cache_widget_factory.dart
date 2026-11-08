import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

import 'forum_model.dart';

/// 正文图片统一走 [globalImageCache] 磁盘缓存：
/// 与画廊/大图预览共用一份缓存，离线整本预取图片后，断网阅读也能出图。
class GlobalCacheWidgetFactory extends WidgetFactory {
  @override
  BaseCacheManager? get cacheManager => globalImageCache;
}
