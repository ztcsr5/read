# SourceReadSwift

纯 Swift/SwiftUI 原生阅读 App 重写项目。

目标不是继续修补 Flutter 版，而是验证一条新的原生路线：

- SwiftUI 原生动态 UI。
- Swift 原生 LegadoCore。
- JavaScriptCore + SwiftSoup 风格 Jsoup 桥。
- URLSession + WKWebView + CookieStore 闭环。
- 小说书源优先，漫画/视频/有声暂不进入 MVP。

## 生成 Xcode 工程

本项目使用 XcodeGen 描述工程，避免手写 `.pbxproj`。

```bash
brew install xcodegen
xcodegen generate
open SourceReadSwift.xcodeproj
```

Windows 侧不能直接编译 iOS 工程，详见 `docs/BUILD.md`。

## 阶段目标

1. SwiftUI App 骨架。
2. LegadoCore 模型、诊断、书源导入。
3. 搜索 -> 详情 -> 目录 -> 正文 MVP。
4. JSCore / SwiftSoup / Cookie / WebView 过盾闭环。
5. 原生阅读 UI 打磨。
