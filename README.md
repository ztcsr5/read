# SourceReadSwift

Native Swift/SwiftUI rewrite of the reading app.

The goal is not to keep patching the Flutter build. This repo is the native iOS route:

- SwiftUI native UI
- Swift native LegadoCore
- JavaScriptCore bridge
- SwiftSoup-backed Jsoup compatibility
- URLSession + WKWebView + CookieStore request loop
- novel book sources first

## Windows development

Windows can edit, commit, and push this project, but it cannot compile iOS apps locally.

Use GitHub Actions as the macOS build machine:

```powershell
cd D:\Gemini反重力\SourceReadSwift
git push origin codex/native-swift-rewrite
```

Then check:

```text
GitHub repository -> Actions -> iOS
```

If the CI run fails, copy the first Xcode/Swift error block back into Codex.

## Generate Xcode project on macOS

```bash
brew install xcodegen
xcodegen generate
open SourceReadSwift.xcodeproj
```

## Build on macOS

```bash
xcodebuild \
  -project SourceReadSwift.xcodeproj \
  -scheme SourceReadSwift \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

See `docs/BUILD.md` for Windows + CI details.

## Current stage goals

1. SwiftUI app skeleton.
2. Native LegadoCore models, diagnostics, and source import.
3. Search -> detail -> TOC -> content MVP.
4. JSCore / SwiftSoup / Cookie / WebView compatibility loop.
5. Native reading UI polish.
