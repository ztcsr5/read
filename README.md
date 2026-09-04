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

## Stage 3 hardening checkpoint

- ProMotion is opt-in safe: `CADisableMinimumFrameDurationOnPhone` remains enabled and no idle `CADisplayLink` is kept alive. UIKit can adapt interactive work up to the device's supported ceiling (120 Hz on ProMotion models).
- Reader pagination and tap zones use the measured SwiftUI container size, not `UIScreen.main`, so rotation, Split View and Stage Manager resize correctly.
- TextKit visible-paragraph lookup is O(log n); bookshelf, Discover and RSS cover rows share a bounded decoded-image memory cache.
- Settings exposes the canonical `书源管理` and `Web 写源` routes; Discover remains focused on search.

CI proves compilation and XCTest only. Sustained 120 Hz, touch feel, LAN Web 写源 and self-sign installation still require a ProMotion iPhone and the unsigned IPA artifact.

## Stage 4 product parity checkpoint

- Active scenes record the device-capped refresh ceiling and keep `CADisableMinimumFrameDurationOnPhone` enabled; UIKit/SwiftUI can use ProMotion without an SDK-specific frame-range API that is unavailable in the iOS 16 CI toolchain.
- Reader settings can be dismissed by close button, backdrop tap or downward drag; chapter/content revisions reset stale playback and pagination state.
- Discover search has explicit clear/cancel controls and a model-level reset path; source cards expose a direct visual-details action.
- Root tab chrome follows keyboard safe-area changes, while Home, Discover and Settings use the same bounded large-title shell.

CI still proves compilation/tests and unsigned packaging only. Sustained 120 Hz and device/LAN behavior require a ProMotion iPhone check.
