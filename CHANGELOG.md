# 更新日志

## v2.1.0 (2026-07-13)
### 新增功能
- **发帖系统**：首页底部导航新增 `+` 发帖按钮，支持选择板块后发表新帖，含主题分类选择
- **编辑器工具栏**：发帖和回复页面新增完整的 BBCode 工具栏（加粗/斜体/下划线/颜色/引用/代码/链接/隐藏内容）
- **TXT/MD 导入**：支持导入 `.txt` / `.md` 文件，自动将 Markdown 转换为 BBCode，超 5 万字弹窗选分段导入
- **图片/附件上传**：支持上传图片（自动压缩）和通用附件（doc/pdf/zip 等），修复 `attachnew` 参数缺失问题
- **未使用附件检测**：嗅探时自动检测已上传未插入的附件，橙色横幅提示"插入全部"或"删除"
- **表情面板**：发帖和回复页面新增表情选择面板

### Bug 修复
- **字体大小不生效**：修复全量阅读模式下部分帖子因内含 `<font size>` BBCode 导致字号调节无效的问题，改用 `customStylesBuilder` 强制覆盖
- **图片上传后不显示**：添加上传图片/附件后 `attachnew[$aid]=1` 参数，修复 Discuz 不引用附件的问题
- **附件上传失败 -7**：分离图片上传和附件上传通道，修复非图片文件被服务器拒绝
- **状态栏黑块**：适配 Android 15+ 强制 edge-to-edge，设置半透明状态栏和导航栏
- **HTML 实体未解码**：修复 thread_detail_page、user_detail_page 标题中 `&amp;` 等实体未清洗的问题
- **书签进度条不更新**：修复 release 模式下全量阅读器书签跳转后进度条不动的问题，改为递归等待内容渲染完成
- **Gradle 下载慢**：改为腾讯云镜像 + 阿里云 Maven 镜像
- **正文无法发帖**：修复部份板块因 formhash 抓取失败、分类选择逻辑异常导致发帖按钮不可用的问题

### UI 优化
- **主题色跟随**：侧边栏菜单图标颜色改为 `Theme.of(context).colorScheme.primary`，跟随 MD3 动态取色
- **头像快捷入口**：大厅右上角头像点击跳转到"我的帖子"
- **板块选择器**：发帖时弹出按分区分类的板块列表

### 涉及文件
| 文件 | 变更类型 |
|------|----------|
| `lib/new_thread_page.dart` | **新增** - 发帖页面（WebView 嗅探 + 工具栏 + TXT导入 + 附件上传） |
| `lib/settings_page.dart` | 修改 - 新增发帖测试入口（已迁移到首页+按钮） |
| `lib/main.dart` | 修改 - 导航栏新增发帖按钮、论坛选择器、头像跳转、状态栏适配 |
| `lib/ultra_reader_page.dart` | 修改 - 字号强制覆盖、书签进度修复、内联 font-size 剥离 |
| `lib/thread_detail_page.dart` | 修改 - HTML 实体清洗、图片上传 bug 修复 |
| `lib/reply_native_page.dart` | 修改 - 工具栏增强、TXT导入、附件上传、未使用附件检测 |
| `lib/user_detail_page.dart` | 修改 - 标题 HTML 实体清洗 |
| `android/app/src/main/res/values/styles.xml` | 修改 - 透明状态栏配置 |
| `android/app/src/main/res/values-night/styles.xml` | 修改 - 透明状态栏配置 |
| `android/gradle/wrapper/gradle-wrapper.properties` | 修改 - 腾讯云镜像 |
