# 更新日志

## v2.1.0 (2026-07-08) 

### 新增功能
- **MD3 动态取色**：高级设置中新增色彩方案选项，支持三种模式
  - 默认色彩：使用应用内置主题色
  - 预设颜色：提供 12 种预设种子色供选择
  - 壁纸取色：从自定义壁纸中自动提取平均色作为主题色
- **首次启动引导页**：新增 `first_launch_page.dart`，优化首次使用体验
- **MIUI 主题系统**：新增 `miui_theme.dart`，基于 MD3 `ColorScheme.fromSeed` 动态生成完整主题（亮色/暗色），覆盖 Card、AppBar、NavigationBar、BottomSheet、Dialog、Chip、InputDecoration、Button 等全部组件样式

### 修复与优化
- **过渡动画选择器溢出**：修复高级设置中页面切换动画选择弹窗底部溢出 58 像素的问题
- **全站热点卡片透明度**：全站热点卡片现在支持自定义壁纸下的透明度调节，与论坛卡片同步
- **透明度实时生效**：修改论坛卡片透明度后无需刷新页面，退出设置即刻生效（所有页面改用 `AnimatedBuilder` + `Listenable.merge` 监听双重通知器）
- **用户详情页卡片布局**：修复 `_buildThreadTile` 中板块名称标签在超长时正确截断显示省略号，阅读量和评论数右对齐并与板块、日期保持同一行

### 涉及文件
| 文件 | 变更类型 |
|------|----------|
| `lib/main.dart` | 重构 - 全局色彩状态、壁纸取色、AnimatedBuilder 迁移 |
| `lib/settings_page.dart` | 新增 - MD3 色彩方案设置 UI、底部弹窗溢出修复 |
| `lib/miui_theme.dart` | **新增** - MD3 动态主题构建器 |
| `lib/first_launch_page.dart` | **新增** - 首次启动引导 |
| `lib/user_detail_page.dart` | 修复 - 帖子卡片底部布局 |
| `lib/thread_list_page.dart` | 优化 - AnimatedBuilder 迁移 |
| `lib/history_page.dart` | 优化 - AnimatedBuilder 迁移 |
| `lib/favorite_page.dart` | 优化 - AnimatedBuilder 迁移 |
| `lib/bookmark_page.dart` | 优化 - AnimatedBuilder 迁移 |
| `lib/notification_page.dart` | 优化 - AnimatedBuilder 迁移 |
| `lib/search_page.dart` | 优化 - AnimatedBuilder 迁移 |
| `lib/forum_model.dart` | 优化 - 模型字段调整 |
| `lib/login_page.dart` | 优化 |
| `lib/thread_detail_page.dart` | 优化 |
| 平台生成文件 (linux/windows/macos) | 自动生成 |
