# SourceReadSwift 下一大阶段施工计划

## 目标

把当前可构建的 SwiftUI 阅读器推进到可长期使用的原生 iOS 产品节点：高刷设备流畅、EPUB/RSS 可完整阅读、书源和规则可诊断编辑、阅读器支持朗读与自动推进，并持续完成 Flutter 功能 parity。

## 施工规则

- 以“大阶段”为交付单位，不再为单个小修频繁打断。
- 每个大阶段完成后统一提交、推送到 `ztcsr5/read`，再等待 iOS 和 unsigned IPA Actions。
- Windows 只做源码、测试、静态检查和 Git 操作；Xcode 编译/测试由 GitHub Actions 完成。
- 不宣称真机 120 FPS，直到 ProMotion 真机实测；CI 只证明编译与测试。

## 当前执行口令（2026-09-02）

- 主路线固定为原生 Swift/SwiftUI，不再回退到 Flutter 运行时。
- 交付按“大阶段”推进：阶段内连续施工，阶段末一次性提交、推送和跑 Actions。
- 高刷新目标为“允许 ProMotion 设备使用系统最高刷新率，并清理阅读热路径掉帧源”；只有拿到 ProMotion 真机或 Instruments 证据后，才把 120 Hz 写成实测结论。
- Windows 端负责源码、fixture、静态检查、Git；GitHub Actions 负责 Xcode 编译、XCTest 和 unsigned IPA。
- 每次阶段回报只包含：提交 SHA、Actions run、artifact、已验证项、未验证项和下一阶段入口。

## 大阶段验收门槛

每个阶段必须同时满足以下条件才算“阶段完成”：

1. 代码和测试变更通过 `git diff --check`。
2. iOS workflow 的 build/test 成功；失败必须读取 annotations 后修复并重跑。
3. unsigned IPA workflow 成功并产出可下载 artifact。
4. `progress.md` 记录本阶段范围、证据、未验证项和回滚点。
5. 不得把“代码已提交”或“Actions 已排队”写成“功能已验收”。

## 阶段 1：性能与内容基础闭环

状态：进行中

- 修复高刷新协调器的 SDK 兼容性。
- 完成 SwiftUI/阅读器热路径 profiling 埋点。
- EPUB：路径编码、OPF/spine、正文抽取、目录、缓存、阅读进度。
- RSS：Feed/Atom 列表、文章详情阅读、HTML 正文抽取、失败 fallback。
- 验收：Actions 编译、单元测试、unsigned IPA；保留性能 signpost。

### 阶段 1.1：高刷与阅读热路径（当前优先）

- 保留 `CADisableMinimumFrameDurationOnPhone = true` 和 `FrameRateCoordinator`，确保 ProMotion 设备不被应用主动锁到 60 Hz。
- 以 signpost、主线程任务、分页/布局、图片解码和网络回调为观测点，逐个消除阅读页长任务。
- 禁止在滚动/翻页热路径执行同步磁盘 IO、整本重排版和重复 JSON/HTML 解析。
- 对自动翻页、朗读高亮、章节切换增加状态互斥，避免多个定时器或任务重复驱动 UI。
- 验收分两层：CI 证明编译/测试；真机或 Instruments 再证明实际 120 Hz/帧时间。

## 阶段 2：书源诊断与规则编辑

- 建立 `SourceReadSwiftTests/Fixtures/` 书源 fixture 集。
- 覆盖 Legado HTML/JSON/JS、POST、分页、JXNode、headers/cookie/status。
- 规则编辑器支持分组编辑、语法校验、本地样本预览、单步执行、日志和导出。
- 书源详情测试支持搜索→详情→目录→正文完整链路。

### 阶段 2A：Legado JS compatibility gap audit（当前已开工）

- 对齐 Flutter `LegadoJsEngine` 的高频兼容面：`getStr/getJson/putJson`、默认值语义、字节/Base64/Hex 转换、`postForm/openUrl`、全局 helper。
- 补齐常见 Java/Android 命名空间占位：`java.net.URL`、`java.security.MessageDigest`、`javax.crypto.Mac/SecretKeySpec`、`java.io.ByteArrayInputStream`。
- 保留原生 SwiftSoup/JavaScriptCore 路线，不引入 Flutter runtime；所有网络通过现有 `RuleExecutionContext` mock/handler。
- 以 fixture + XCTest 锁定 API 行为，阶段末统一提交、推送并跑 iOS build/XCTest 与 unsigned IPA Actions。

## 阶段 3：阅读器高级能力

- `AVSpeechSynthesizer` 朗读控制器。
- 播放/暂停/继续、语速、章节自动衔接、后台状态处理。
- 自动翻页、定时翻页、滚动自动阅读、睡眠定时器。
- 朗读、手势、翻页、进度持久化状态机解耦。

## 阶段 4：Flutter parity 与产品收尾

- 对齐缓存、主题、字体、翻页、更新检测、导入导出、空/错/加载状态。
- 补齐批量书源诊断和数据恢复。
- 做长列表、键盘、文件选择器、网络失败、重复点击等回归。
- 完成 release workflow、artifact 摘要和自签安装说明。

## 执行顺序锁定

1. 先收口当前 Actions（iOS build/test + unsigned IPA），不在失败未定位前扩大代码面。
2. 再做 RSS 完整化和书源测试闭环，保证内容链路可诊断、可缓存、可恢复。
3. 再做阅读器朗读/自动翻页的状态机和章节自动衔接。
4. 最后按 Flutter parity ledger 做产品收尾、回归矩阵和发布包装。

## 每阶段固定验收

1. `git diff --check`
2. Actions iOS build/test
3. Actions unsigned IPA
4. 失败时读取 annotations，修复后重新跑
5. 更新 `progress.md`
6. 回报提交、运行链接、artifact 和未验证项
