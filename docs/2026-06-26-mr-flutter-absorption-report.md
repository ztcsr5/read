# mr -> read Flutter 吸收审查报告

日期：2026-06-26

## 业务结论

`DandanLLab/mr` 值得吸收，但不适合整包覆盖 `read`。

正确方向是：保留 `read` 现有 Flutter UI、Riverpod、Isar、阅读页和产品结构，把 `mr` 当作第二套 Legado 兼容实现进行差分吸收。优先吸收导入兼容、规则链路分层、调试器交互、WebView/webJs 思路和部分 JS 桥接实现；不优先吸收它的整套 Provider/Hive 架构，也不直接替换我们已有的 QuickJS 路线。

## 已建立参考源

- `D:\Gemini反重力\references\mr`
- 来源：[DandanLLab/mr](https://github.com/DandanLLab/mr)
- 许可证：MIT License。吸收代码时必须保留原版权与 MIT 许可声明。

## 关键判断

### 1. 不能整包抄的原因

`mr` 的产品架构和 `read` 不一致：

- `mr`：Provider + Hive + 自带页面体系。
- `read`：Riverpod + Isar + 现有 Flutter iOS 播客风格 UI。
- `mr` 的 QuickJS C 源码/FFI/iOS 链接最近仍在频繁修 CI 和链接参数，不适合作为直接替换基础。
- `read` 已有大体量 Legado 解析器，直接替换会丢失已有兼容修复和 UI 接入。

结论：只做模块吸收，不做整包替换。

### 2. `mr` 最值得吸收的模块

| 优先级 | mr 模块 | 吸收价值 | 处理方式 |
|---|---|---|---|
| P0 | `lib/services/book_source_import_service.dart` | `sourceUrls` 递归、JS 函数式书源、动态字段容错、去重策略 | 直接对照移植逻辑到 `read` 导入服务 |
| P0 | `lib/services/source_engine/web_book.dart` | 搜索/发现/详情/目录/正文链路分层清楚 | 差分吸收链路组织和失败诊断 |
| P0 | `lib/services/source_engine/analyze_rule.dart` | CSS/JSONPath/XPath/JS/Regex/WebJs 模式分层清楚 | 按规则类型逐项对照补缺口 |
| P1 | `lib/pages/debug/book_source_debug_page.dart` | 日志、源码查看、调试入口整合 | 借鉴 UI 和交互，不搬 Provider 结构 |
| P1 | `lib/services/source_debug_service.dart` | 搜索/详情/目录/正文源码留存 | 接到 `read` 现有诊断页 |
| P1 | `lib/services/native/js_engine.dart` | `CryptoJS`、`java.*`、预缓存、追踪树 | 只吸收桥接函数和测试思路，不直接换底层 |
| P2 | `lib/pages/reader/*` | 小说/漫画阅读器功能完整 | 只吸收功能细节，不换 `read` 阅读页 UI |

### 3. `read` 已有基础，不能低估

本地扫描显示 `read` 的书源实现已经很重：

| 模块 | 规模 | 说明 |
|---|---:|---|
| `read/lib/data/parsers/legado_parser.dart` | 约 237 KB | 搜索、详情、目录、正文总入口 |
| `read/lib/data/parsers/legado/legado_rule_evaluator.dart` | 约 144 KB | 规则求值核心 |
| `read/lib/data/parsers/legado/legado_js_engine.dart` | 约 183 KB | QuickJS/JSCore/legacy JS 桥 |
| `mr/lib/services/source_engine/analyze_rule.dart` | 约 86 KB | mr 规则解析核心 |
| `mr/lib/services/source_engine/web_book.dart` | 约 78 KB | mr 链路执行核心 |
| `mr/lib/services/native/js_engine.dart` | 约 163 KB | mr JS 桥 |

这说明 `read` 不是缺一个引擎，而是需要用 `mr` 做差分修补和测试校准。

## 分阶段吸收计划

### 阶段 A：导入兼容增强

目标：先保证更多书源能进来。

吸收内容：

- `sourceUrls` 递归导入。
- URL 后缀 `#requestWithoutUA`。
- 单对象 JSON、数组 JSON、包装对象 JSON。
- 字段类型容错：字符串数字、字符串布尔、动态 Map。
- JS 函数式书源导入：从 JS 注释或变量中提取 name/url/group/search/detail/toc/content。
- 去重策略：同 `bookSourceUrl` 后者覆盖前者。

落点：

- `lib/features/settings/viewmodels/book_source_viewmodel.dart`
- `lib/data/parsers/source_import_link_parser.dart`
- 必要时新增 `lib/data/parsers/book_source_import_service.dart`

验证：

- 增加导入单元测试，覆盖普通 JSON、数组、`sourceUrls`、JS 书源、字符串布尔/数字。

### 阶段 B：规则链路差分补强

目标：提升 Legado JSON 搜索、详情、目录、正文成功率。

吸收内容：

- `AnalyzeRule` 的 RuleMode 分层：default/json/xpath/js/regex/webJs。
- CSS/JSoup 选择器边界处理。
- JSONPath 递归搜索、切片、过滤器。
- XPath 前缀和疑似 XPath 规则处理。
- `replaceRegex` 多行处理。
- `webJs` 用 WebView 渲染后再解析。
- 目录分页、正文分页和 nextUrl 处理。

落点：

- `lib/data/parsers/legado/legado_rule_evaluator.dart`
- `lib/data/parsers/legado_parser.dart`
- `lib/data/parsers/legado/legado_request_builder.dart`

验证：

- 以测试 fixture 驱动，不能凭感觉改。
- 每补一个规则类型，至少增加一组搜索/目录/正文测试。

### 阶段 C：JS 桥兼容补强

目标：减少 `java.ajax`、`CryptoJS`、复杂 JS 源失败。

吸收内容：

- `mr` 的 `JsTracer` 思路：记录 JS 调用、输入、输出、耗时、错误。
- `java.ajax/java.get/java.post/java.ajaxAll` 行为对照。
- `CryptoJS.AES/MD5/SHA/SHA256/HmacSHA256` API 表面对照。
- JS 预缓存策略对照。
- `source/book/chapter` 上下文注入对照。

不直接吸收：

- `mr/quickjs` C 源码和 iOS 链接方案。它近期仍在修 iOS 静态库链接，直接引入风险大。

落点：

- `lib/data/parsers/legado/legado_js_engine.dart`
- `lib/features/source_diagnostic/services/source_diagnostic_service.dart`

验证：

- JS 桥函数级测试。
- 复杂书源回归测试。

### 阶段 D：书源调试器增强

目标：让调书源不再靠猜。

吸收内容：

- 搜索源码、详情源码、目录源码、正文源码查看。
- 日志流展示、复制、导出。
- 按搜索/详情/目录/正文分阶段查看结果。
- 调试输入快捷切换。
- JS 执行追踪树。

落点：

- `lib/features/settings/views/source_test_page.dart`
- `lib/features/source_diagnostic/views/source_diagnostic_page.dart`
- `lib/features/settings/views/source_batch_check_page.dart`

验证：

- 先不要求 UI 全测；至少保证单源测试输出包含四段源码和阶段性日志。

### 阶段 E：阅读器局部吸收

目标：补功能，不换 UI。

吸收内容：

- 阅读记录细节。
- 本地 TXT/EPUB 解析边界。
- TTS 管理思路。
- 小说/漫画阅读器缓存和翻页细节。

不吸收：

- `mr` 页面整体布局。
- `mr` 主题系统整体替换。

落点：

- `lib/features/reader/views/reader_page.dart`
- `lib/features/reader/viewmodels/reader_viewmodel.dart`
- `lib/data/parsers/txt_parser.dart`
- `lib/data/parsers/epub_parser.dart`

## 第一轮施工建议

不做“小补丁”，而是做一个完整的 Flutter 书源增强迭代：

1. 建立 `BookSourceImportService` 或增强现有导入服务。
2. 补导入测试。
3. 把 `sourceUrls`、JS 书源、字段容错、去重策略全部落地。
4. 再进入规则引擎差分。
5. 最后升级诊断页，把失败阶段、源码和日志暴露给用户。

## 风险控制

- 每次吸收只围绕一个模块，避免 Provider/Hive 架构混入 `read`。
- 不改 UI 主结构，避免偏离用户想要的旧版 Flutter UI。
- 不直接引入 `mr` QuickJS C 源码，避免 iOS 打包重新爆炸。
- 所有来自 `mr` 的实质代码必须在文档和文件注释中保留 MIT 来源说明。

## 当前结论

`mr` 可以帮助我们把 Flutter 旧版先做强，尤其是书源导入、规则解析、调试器和 JS 桥兼容。Swift 不放弃，但现阶段应让 Flutter 旧版成为“功能完整、书源命中率高”的主可用版本；等 Flutter 规则链路稳定后，再把成熟规则经验迁移回 Swift。
