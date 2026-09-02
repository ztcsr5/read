# SourceReadSwift 下一大阶段施工计划

## 目标

把当前可构建的 SwiftUI 阅读器推进到可长期使用的原生 iOS 产品节点：高刷设备流畅、EPUB/RSS 可完整阅读、书源和规则可诊断编辑、阅读器支持朗读与自动推进，并持续完成 Flutter 功能 parity。

## 施工规则

- 以“大阶段”为交付单位，不再为单个小修频繁打断。
- 每个大阶段完成后统一提交、推送到 `ztcsr5/read`，再等待 iOS 和 unsigned IPA Actions。
- Windows 只做源码、测试、静态检查和 Git 操作；Xcode 编译/测试由 GitHub Actions 完成。
- 不宣称真机 120 FPS，直到 ProMotion 真机实测；CI 只证明编译与测试。

## 阶段 1：性能与内容基础闭环

状态：进行中

- 修复高刷新协调器的 SDK 兼容性。
- 完成 SwiftUI/阅读器热路径 profiling 埋点。
- EPUB：路径编码、OPF/spine、正文抽取、目录、缓存、阅读进度。
- RSS：Feed/Atom 列表、文章详情阅读、HTML 正文抽取、失败 fallback。
- 验收：Actions 编译、单元测试、unsigned IPA；保留性能 signpost。

## 阶段 2：书源诊断与规则编辑

- 建立 `SourceReadSwiftTests/Fixtures/` 书源 fixture 集。
- 覆盖 Legado HTML/JSON/JS、POST、分页、JXNode、headers/cookie/status。
- 规则编辑器支持分组编辑、语法校验、本地样本预览、单步执行、日志和导出。
- 书源详情测试支持搜索→详情→目录→正文完整链路。

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

## 每阶段固定验收

1. `git diff --check`
2. Actions iOS build/test
3. Actions unsigned IPA
4. 失败时读取 annotations，修复后重新跑
5. 更新 `progress.md`
6. 回报提交、运行链接、artifact 和未验证项
