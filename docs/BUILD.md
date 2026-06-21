# Build Notes

Windows cannot build or run an iOS SwiftUI app locally because Xcode, the iOS SDK, `xcodebuild`, Simulator, code signing, and App Store upload tools only run on macOS.

This project should use this workflow:

1. Develop and commit on Windows.
2. Push to GitHub.
3. Let GitHub Actions run the macOS build.
4. Use the CI log to fix Swift/Xcode errors from Windows.
5. Use a real Mac only when you need Simulator debugging, device debugging, signing, TestFlight, or App Store upload.

## Windows commands

```powershell
cd D:\Gemini反重力\SourceReadSwift
git status -sb
git push origin codex/native-swift-rewrite
```

Then open GitHub:

- Repository -> Actions -> iOS
- Open the latest run
- If it fails, copy the first Swift/Xcode error block back into Codex

## macOS / GitHub Actions commands

```bash
brew install xcodegen
xcodegen generate
xcodebuild \
  -project SourceReadSwift.xcodeproj \
  -scheme SourceReadSwift \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

For unit tests, CI picks the first available iPhone simulator:

```bash
DEVICE_ID="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ {print $2; exit}')"
xcodebuild \
  -project SourceReadSwift.xcodeproj \
  -scheme SourceReadSwift \
  -destination "id=$DEVICE_ID" \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## Signing and App Store

CI build/test does not require signing. Real App Store delivery still needs:

- Apple Developer Program account
- Bundle Identifier
- Team ID
- signing certificate
- provisioning profile
- App Store Connect app record

Those can be added later after the native core is stable.

## Unsigned IPA for self-signing

If you already have your own signing workflow, use the `Unsigned IPA` GitHub Actions workflow.

It builds an unsigned `iphoneos` app and uploads:

```text
SourceReadSwift-unsigned.ipa
```

Download it from:

```text
GitHub repository -> Actions -> Unsigned IPA -> latest run -> Artifacts
```

Then re-sign that IPA with your own certificate/profile/tooling.

## Current quality rules

- Every network/rule/JS failure must return `SourceEngineError`.
- New work should be committed in small, recoverable commits.
- UI direction stays native SwiftUI with iOS Podcasts-style structure.
- MVP scope is novel book sources first; manga/video/audio are not in the first target.
