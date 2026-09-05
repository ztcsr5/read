# Stage 20A：搜索体验与智能网页阅读设计

## 目标

把“智能网页小说模式”从含糊概念变成可发现、可解释、可回退的产品入口，并让发现页结果按书源分组，降低多源搜索时的信息噪声。

## 方案

- 发现页导航栏提供 `智能网页阅读` 入口。
- 入口先显示 `WKWebView` 网页预览；用户主动点击“提取正文并阅读”后，抓取页面 HTML 并在本地用 SwiftSoup 移除脚本、导航、表单、页眉页脚和侧栏。
- 优先读取 `article/main/content` 容器中的段落块；没有结构化段落时回退到纯文本分段。
- 提取结果进入原生 SwiftUI 文本阅读面板，保留返回网页动作；提取失败显示明确错误，不丢失原网页。
- 搜索结果按 `sourceName` 分组，组内沿用既有稳定排序、筛选、失败源和取消搜索状态。

## 验证

- SwiftSoup fixture 覆盖脚本/导航剔除、标题保留、重复段落去重和 malformed HTML 回退。
- Windows 执行 `git diff --check` 与静态检查；GitHub Actions 执行 iOS build/XCTest 和 unsigned IPA。
- 真机阶段再验证 WKWebView 登录态、动态页面、长文提取质量以及 ProMotion 帧时间。

## 非目标

- 本阶段不承诺任意公网页面都能抽取，也不替代 Legado 书源引擎。
- 本阶段不在 Windows 上伪造 Xcode 或真机性能结果。
