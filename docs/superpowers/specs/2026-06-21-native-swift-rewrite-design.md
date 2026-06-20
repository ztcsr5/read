# Native Swift Rewrite Design

## 背景

Flutter 版 `D:\Gemini反重力\read` 在 `feat/source-engine-v1` 的最新提交 `94120e4` 已把部分 JS 执行迁到 iOS Native JSCore，但真机结果仍显示只有固定少数书源稳定可用，部分书源详情页仍停在 skeleton loading。继续修补 Dart parser、QuickJS fallback、MethodChannel 异步路径的收益有限。

## 决策

新建独立项目 `D:\Gemini反重力\SourceReadSwift`，做纯 Swift/SwiftUI 全量重写。旧 Flutter 项目仅作为需求、UI 信息、书源数据和问题清单参考，不再作为核心代码基础。

## 范围

MVP 只支持小说书源。

纳入：

- SwiftUI 书架、发现、书源管理、详情、目录、阅读、设置；视觉方向沿用旧 Flutter 版产品思路，即 iOS Podcasts 风格的大标题、圆角卡片、胶囊筛选、柔和背景、原生动效。
- Swift 原生 LegadoCore。
- JSON 书源导入和持久化。
- 搜索、详情、目录、正文主链路。
- JavaScriptCore 规则执行。
- SwiftSoup/Jsoup 桥接。
- URLSession 请求、Cookie 持久化、WKWebView fallback。
- 结构化诊断，不允许 UI 无限 loading。

暂不纳入：

- 漫画、视频、有声。
- 账号同步。
- App Store 完整上架物料。
- 与旧 Flutter 数据库的完整自动迁移。

## 架构

```text
SwiftUI Features
  Podcasts-style Bookshelf / Discover / SourceManager / Reader / Settings
        ↓
LegadoCore
  SourceEngine
  RuleResolver
  JSCoreRuntime
  JsoupBridge
  SourceNetworkClient
  SourceCookieStore
  WebViewFallback
  Diagnostics
        ↓
Foundation / JavaScriptCore / SwiftSoup / WebKit
```

## 成功标准

第一阶段成功标准：

- 项目能生成 Xcode 工程。
- SwiftUI App 可启动。
- UI 风格与旧 Flutter 方向一致，接近 iOS Podcasts：大标题、卡片列表、胶囊控件、底部 Tab、柔和分组背景。
- Core 模型和诊断类型可单测。
- 能导入一条 BookSource JSON 并发起搜索入口调用。
- 所有 Core API 均返回成功或结构化错误，不出现永久 loading。

第二阶段成功标准：

- 在真机上用用户现有书源库搜索“斗破苍穹”。
- 搜索命中源数显著超过 Flutter 版固定可用源。
- 点击搜索结果能进入详情，不再无限 skeleton。
- 至少打通搜索、目录、正文各 1 个 HTML 源和 1 个 JSON/API 源。

## 风险

- 没有 macOS/Xcode 的本机环境，Windows 侧只能生成文件和静态检查，编译需在 Mac 或 GitHub Actions 上跑。
- 源阅只能作为行为参考，不能直接复制二进制逻辑。
- WebView 过盾、登录、签名鉴权仍需要真机验证。
