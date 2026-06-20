# Build Notes

当前开发机是 Windows，未安装 `swift`、`xcodegen`、`xcodebuild`，因此本地不能直接编译 iOS App。

在 macOS / GitHub Actions 上执行：

```bash
brew install xcodegen
cd SourceReadSwift
xcodegen generate
xcodebuild \
  -project SourceReadSwift.xcodeproj \
  -scheme SourceReadSwift \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

真机签名构建需要配置：

- Apple Developer Team
- Bundle Identifier
- Signing Certificate
- Provisioning Profile

## 当前质量门

- 所有网络/解析 API 必须返回 `SourceEngineError`，不能让 UI 永久 loading。
- 新增功能必须有可恢复 git commit。
- SwiftUI 视觉方向保持 iOS Podcasts 风格。
- LegadoCore 优先小说书源；漫画、视频、有声不进入 MVP。

