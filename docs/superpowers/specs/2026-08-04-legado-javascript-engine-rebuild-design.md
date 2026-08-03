# Legado JavaScript 书源引擎重建设计

日期：2026-08-04
状态：已批准，进入实现

## 目标

在不更换 JavaScriptCore 的前提下，重建 Swift 版书源执行层，使其能够稳定运行安卓「阅读」的 JavaScript 书源，并把源阅读 1.5.0 已暴露的兼容接口作为最低 ABI 基线。实现必须保持纯原生 Swift、可由 GitHub Actions 在 macOS 构建和测试，并允许 Windows 端只负责提交代码与读取 CI 结果。

## 已确认事实

- 参考样本使用 JavaScriptCore 和 WebKit，不使用 QuickJS。
- 参考样本把 RuleResolver、Java 扩展、Book、Chapter、Jsoup 对象通过 `JSExport` 暴露给脚本。
- 参考样本具备 CSS、Jsoup、XPath、JSONPath、EasySoup、JavaScript 多类规则解析器。
- 当前 Swift 版主要依赖大型 JavaScript prelude 模拟 Java/Jsoup 对象，DOM 元素在跨调用时丢失原生身份和修改状态，是兼容性瓶颈。
- 参考样本的若干文件方法仍是空实现；本项目不复制缺陷，而是实现可用的沙箱文件能力。

## 架构

### 1. RuleExecutionContext

每次规则执行创建独立上下文，持有：

- `result`、`baseUrl`、`nextChapterUrl`
- 当前 `source`、`book`、`chapter`
- 执行期变量、持久变量、请求头、Cookie
- 网络、文件、日志能力的闭包

上下文不跨 JSContext 并发共享。一次执行中的 `put/get`、`setContent`、对象变量和后续规则都读取同一状态。

### 2. 原生 JSExport 主机桥

新增原生对象并通过 JavaScriptCore 注入：

- `LegadoJavaBridge`：ajax/fetch/post、编码、摘要、Cookie、文件、压缩包、变量、日志。
- `LegadoRuleBridge`：getString/getStringList/getElement/getElements/setContent 和上下文属性。
- `LegadoBookBridge`、`LegadoChapterBridge`、`LegadoSourceBridge`：兼容脚本常用属性与变量 API。
- `LegadoJsoupBridge`：parse/connect 入口。

旧 prelude 继续提供 Android/Java 类名、CryptoJS 别名和少量语法糖，但核心能力必须委托原生桥，不再自行维护平行状态。

### 3. 原生 DOM 对象图

SwiftSoup 的 Document/Element/Elements 用 NSObject 包装后直接暴露给 JS。对象保留同一个原生节点，因此 `select/remove/attr/html/text/parent/children` 等操作可串联且修改可见。第一阶段覆盖真实书源高频 API，未覆盖调用需要明确抛出或记录诊断，不能静默伪造成功。

### 4. 规则分派

`LegadoRuleResolver` 只负责模板和规则结构识别；实际解析由专用解析器分派：

1. JavaScript 段
2. JSONPath
3. XPath
4. CSS/Jsoup/EasySoup
5. 正则替换和连接运算

规则解析和 JavaScript 共用 RuleExecutionContext，保证 `result/baseUrl/book/chapter/source` 一致。

### 5. 网络、Cookie 与文件

- URLSession 与 WKWebView 共用 SourceCookieStore。
- 同步 JS 网络调用在独立串行执行队列中等待异步网络结果，设置硬超时和诊断。
- 文件接口只能访问应用 Documents/Caches 下的书源沙箱目录，禁止任意路径穿越。
- ZIP/TXT 接口使用 ZIPFoundation 与 Foundation 实现。

## 迁移策略

采用渐进替换：

1. 增加执行上下文、原生桥和原生 DOM，不破坏当前入口。
2. JSCoreRuntime 改为每次执行绑定上下文，并让 prelude 委托原生桥。
3. 现有测试全部保留，新增源阅读 ABI 测试和真实书源 fixture。
4. 再把解析器逐项迁到统一 RuleAnalyzer，最后删除重复的字符串 DOM 模拟。

## 错误处理

- JS 异常必须带阶段、脚本摘要和原始异常进入 SourceEngineError/DiagnosticSink。
- 网络、文件、规则解析失败不返回伪成功；允许兼容模式在单一规则失败后尝试下一条 `||` 分支。
- 每次执行结束清理 JS exception，避免污染后续脚本。

## 验收

- 原有单元测试不回退。
- 新增测试覆盖上下文状态回写、原生 DOM 身份/修改、ajaxAll、Cookie、Book/Chapter 变量、Jsoup parse/select 链。
- GitHub Actions 的 simulator build、unit tests、unsigned IPA 全部通过。
- 使用至少一组公开安卓阅读书源 fixture 完成搜索、详情、目录、正文端到端回归。

## 第一轮实施边界

本轮完成 RuleExecutionContext、原生 Java/Rule/Jsoup/DOM 桥、JSCoreRuntime 集成和 ABI 单测。AES、ZIP 文件读取、WKWebView 动态执行以及完整 RuleAnalyzer 放到后续批次，接口在本轮先稳定下来。
