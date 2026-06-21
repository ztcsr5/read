# App Store readiness checklist

Date: 2026-06-21

This file tracks release gates for the native Swift rewrite. Passing CI or producing an unsigned IPA is not enough to call the app App Store-ready.

## Required before App Store submission

- [ ] macOS CI build passes from a clean checkout.
- [ ] XCTest suite passes on an iOS simulator.
- [ ] Unsigned IPA workflow produces an installable archive for user-side signing tests.
- [ ] Manual device QA covers:
  - [ ] Fresh install.
  - [ ] Source import from paste, file, URL, and share links.
  - [ ] Search, detail, TOC, content, add-to-bookshelf, reopen reader.
  - [ ] Local TXT and EPUB import.
  - [ ] RSS article list.
  - [ ] Reader settings, bookmarks, TTS, auto-scroll, source switching.
  - [ ] Offline/weak-network errors and recovery actions.
  - [ ] Light/dark mode and Dynamic Type.
- [ ] No visible mojibake in runtime UI.
- [ ] No debug-only seeded source data in release builds.
- [ ] No placeholder controls that appear enabled but do nothing.

## Privacy and permissions

- [x] `PrivacyInfo.xcprivacy` exists.
- [x] UserDefaults required-reason API is declared for app preference storage.
- [ ] Re-audit privacy manifest after adding analytics, crash reporting, cache-size calculation, or more filesystem metadata APIs.
- [ ] App Store privacy nutrition labels must match actual behavior before upload.

## Network policy

Current state:

- The app allows arbitrary loads because public novel/RSS sources may still use HTTP or non-standard TLS.
- This is functional for a source-reader app, but it needs explicit App Review justification.

Before submission:

- [ ] Prefer HTTPS sources where possible.
- [ ] Keep arbitrary-load usage tied to user-imported source URLs.
- [ ] Add review notes explaining that the app is a user-configured reader client and must request user-provided HTTP/HTTPS sources.
- [ ] Reconsider narrowing ATS exceptions if the final source model allows it.

## Local network

Current state:

- `NSLocalNetworkUsageDescription` exists for future local source import/export/editor flows.
- The local web editor/server is not yet complete.

Before submission:

- [ ] If local web editor remains incomplete, remove the local network permission string and any local-network code path from release.
- [ ] If local web editor ships, it must be user-started, token-protected, documented, and off by default.

## Build handoff

Windows cannot verify iOS builds locally. Use GitHub Actions only after a coherent local milestone:

1. Push `codex/native-swift-ci`.
2. Run the iOS build/test workflow.
3. Fix the first compiler/test failure.
4. Run unsigned IPA workflow only when CI is green and the build is worth device testing.
