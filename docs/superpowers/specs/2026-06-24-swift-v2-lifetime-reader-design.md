# Swift v2 Lifetime Reader Design

Date: 2026-06-24

Repository: `D:\Gemini反重力\SourceReadSwift`

Baseline Flutter product: `D:\Gemini反重力\read`

Objective: build a native iOS reader that the owner can use for life. This is not a temporary prototype, not a commercial cross-platform compromise, and not a demo that looks finished while core reading and source behavior are broken.

## 1. Product promise

The app is a long-term personal reading home.

It must feel good every day, not merely pass a build. A bookworm may open the reader thousands of times over many years, so the product standard is higher than a normal utility app:

- The reader page is the center of the product.
- UI smoothness and taste are not decoration; they are core requirements.
- Source compatibility matters because unreadable books kill the product.
- A beautiful shell without working reading is unacceptable.
- A powerful source engine with poor reading experience is also unacceptable.

## 2. Lessons from the failed Swift attempt

The previous Swift build failed because it tried to become a new app before it became the right app.

The failures to avoid:

1. Designing screens from imagination instead of treating Flutter as the product baseline.
2. Shipping a visual shell before page behavior, taps, import, and reader settings were reliable.
3. Treating SwiftUI smoothness as automatic instead of designing hit testing, keyboard behavior, scroll performance, and state transitions.
4. Treating source compatibility as a few parser patches instead of a runtime architecture problem.
5. Calling incomplete surfaces "usable" before device-level verification.

The new rule: Flutter defines the product surface; Swift defines the native experience; source compatibility is implemented as a real runtime, not scattered helpers.

## 3. Technology direction

### 3.1 Swift owns the experience layer

Swift is the main app technology for:

- iOS-native navigation.
- Bookshelf, search, reader, settings, source management, and import screens.
- Reader gestures, page turning, scroll performance, haptics, Dynamic Type, accessibility, and status bar behavior.
- File import, share/open-in handling, local notifications if needed, system privacy surfaces, and App Store readiness.
- WKWebView-based source execution and verification browser surfaces.

Swift is selected because the target product is a personal iOS app, not a cross-platform commodity.

### 3.2 Rust is the preferred future core for deterministic heavy logic

Rust is not required before the first Swift UI milestone, but the architecture must leave a clean place for it.

Rust is the preferred home for:

- Source import normalization.
- URL directive parsing.
- Rule tokenization.
- Regex-heavy cleanup.
- Charset and byte utilities where Swift gets awkward.
- Content normalization.
- Fixture-driven source tests.
- Batch source check scheduling if it becomes complex.

Rust must not be introduced as complexity theater. It enters only when an interface is stable enough to test from Swift.

### 3.3 WKWebView / JavaScriptCore owns JS source execution

Lightweight JavaScript can run in JavaScriptCore where practical.

Source formats that depend on browser behavior, cookies, WebView UA, Cloudflare-like checks, page scripts, or light dynamic rendering should run through WKWebView.

The target source runtime follows the idea proven by Qingyue Shiguang: run source JavaScript in a WebView-like JS host and provide app abilities through a bridge.

## 4. Supported source routes

The first product line focuses on three routes:

1. Legado / Yuedu 3.0 JSON.
2. iOS-compatible JSON used by apps such as Dushu Shoushou, Qianyue, Yuanyue, Yuan Yuedu, and similar clients.
3. Qingyue Shiguang-style JS/HTML functional sources.

Xiangse Guige XBS is explicitly not in the first implementation route. It is a separate source format and should not pollute the first engine design.

## 5. Architecture

```text
Swift App
  App shell
  Native UI modules
  Reader UI and gestures
  Import and document access
  WKWebView source host
  Bridge handlers

Domain layer
  Book model
  Chapter model
  Source model
  Reader settings
  Progress
  Bookmarks
  Purify rules
  Source health

SourceRuntime
  Import classifier
  Legado JSON adapter
  iOS-compatible JSON adapter
  Qingyue functional source adapter
  Unified source execution interface

Core utilities
  URL directives
  Rule extraction
  Charset decoding
  Regex cleanup
  Cache and cookie contracts
  Diagnostics

Optional Rust Core
  Deterministic parsing
  Normalization
  Rule/token utilities
  Fixture test helpers
```

## 6. Unified source execution interface

All source formats must eventually map to one internal interface:

```text
search(keyword, page) -> [BookCandidate]
bookInfo(bookUrl) -> BookDetail
chapters(tocUrl/bookUrl) -> [Chapter]
content(chapterUrl) -> ChapterContent
find(categoryUrl, page) -> [BookCandidate]
login() -> LoginResult
test(keyword) -> SourceTestReport
```

This prevents the app from growing four unrelated engines.

## 7. Qingyue Shiguang lessons to absorb

Qingyue Shiguang proves that a source runtime can be cross-platform by making source scripts depend on a bridge instead of a native language.

Swift should absorb this structure:

- A source is allowed to expose async JS functions such as:
  - `search(key, page)`
  - `info(bookurl)`
  - `chapter(tocUrl)`
  - `content(url)`
  - `getfinds()`
  - `find(url, page)`
  - `getloginurl()`
  - `login()`
  - `imagedecrypt(url, image)`
- The app provides bridge abilities:
  - HTTP GET/POST/HEAD.
  - Cookie get/set/remove.
  - Cache get/set/remove.
  - WebView fetch/render/source capture.
  - Browser verification.
  - Device/platform info.
  - Base64/hash/encoding helpers.
  - Log and debug capture.

Swift should not copy Qingyue UI. It should copy the runtime idea.

## 8. Legado compatibility strategy

Legado compatibility remains the main source-quantity target.

However, Legado sources were originally shaped around Android/Rhino/Java-like host APIs. Swift does not get this for free.

The Swift runtime must provide a compatibility layer for common patterns:

- `@js:` and `<js>`.
- `{{key}}`, `{{page}}`, source variables, and page arithmetic.
- URL directives for method, headers, body, charset, webView, and related flags.
- `java.ajax`, `java.get`, `java.post`, `java.connect`.
- `java.put`, `java.getString`, `java.getStringList`, `java.getElements`.
- Cookie and cache helpers.
- Base64, MD5, SHA, HMAC, AES/RSA where real fixtures justify support.
- CSS/JSoup-like extraction, JSONPath-like extraction, XPath subset, regex replacement.
- GBK/GB2312/GB18030 decoding.
- WebView fallback for sources that cannot be solved by static HTTP.

Unsupported Java/Rhino-only features such as arbitrary `Packages.*` and full `JavaImporter` must be classified clearly instead of silently failing.

## 9. UI product baseline

Flutter is the product baseline for:

- Main tab structure: home, discover, settings.
- Bookshelf sections: currently reading, latest updates, shelf.
- Search/discover flow.
- Source manager, import, test, and diagnostics concepts.
- Reader settings and reader behavior.
- Purify rules, history, stats, RSS, and about surfaces.

Swift is allowed to improve visual taste and native feel, but not remove required behavior.

The locked baseline decision is A:

- `D:\Gemini反重力\read` is the only product baseline for UI structure, navigation, page inventory, and user-facing behavior.
- Swift may improve animation quality, native touch response, blur, haptics, typography, and long-session smoothness.
- Swift may not invent a different product flow when the Flutter product already defines the flow.
- Every Swift screen must have a parity checklist against the Flutter screen before it is treated as complete.
- A control that exists in Flutter must either work in Swift or be explicitly deferred in the execution checklist.

The source-engine decision is different:

- The old Flutter source engine is not the implementation baseline.
- Flutter source code is used as a compatibility reference, fixture provider, field-map reference, and regression corpus.
- Swift source compatibility should be rebuilt around a clean runtime: normalized source model, URL directives, HTTP/cookie/cache bridge, rule extractors, diagnostics, and WKWebView/JS host when needed.
- Broken behavior in Flutter source compatibility should not be copied into Swift.

The visual target is:

- Apple Podcasts-like depth where appropriate.
- Native iOS large titles and readable hierarchy.
- Frosted glass only where it supports navigation or reading focus.
- Immediate touch response.
- No dead taps.
- No keyboard lifting the bottom chrome unless the screen intentionally opts into it.
- Smooth 120 Hz scroll targets on ProMotion devices.

## 10. Reader design

The reader is the first-class product core.

Required reader capabilities:

- TXT and EPUB local books.
- Online source books.
- Scroll mode.
- Page mode.
- Cover transition mode.
- Font size, line height, paragraph spacing, title spacing, page padding, top/bottom padding.
- Background themes and custom colors later if stable.
- Reader top and bottom bars with native blur.
- TOC.
- Bookmarks.
- Progress restore by chapter and position.
- Tap zones.
- Source switching.
- Content purify.
- Chapter cache.
- TTS and auto-scroll after the core reader is stable.

Reader acceptance standard:

- Settings change the current page immediately.
- Page mode changes actual layout and gesture behavior.
- Scroll never fights tap zones or selection.
- Returning to a book restores the visible position.
- The reader can be used for hours without feeling like a demo.

## 11. Visual-first milestone

Before source engine work resumes, Swift v2 must pass a visual shell milestone.

The shell includes:

1. Reader page.
2. Home page.
3. Search/discover page.
4. Settings page.
5. Source manager entry page.

The first two visual gates are:

1. Reader page: because this is where the user lives.
2. Home page: because this is where the product greets the user.

No page may look finished if its controls are intentionally nonfunctional without being labeled as a prototype in the design phase.

## 12. Implementation phases

### Phase 0 - Final audit and spec lock

Output:

- This design document.
- Updated progress log.
- No business source-code implementation.

Exit criteria:

- The user agrees this is the Swift v2 direction.

### Phase 1 - Native visual shell

Goal: produce a Swift app shell that looks and feels worth continuing.

Scope:

- Rebuild or heavily revise reader shell.
- Rebuild home shell.
- Establish design tokens: colors, blur, type scale, spacing, cards, haptics.
- Use real sample data where needed.
- Avoid fake source-engine claims.

Exit criteria:

- User visually approves the reader page and home page.

### Phase 2 - Reader daily-use core

Goal: make reading local books comfortable.

Scope:

- TXT import.
- EPUB import.
- Chapter model.
- Reader item model.
- Progress restore.
- Reader settings that actually affect layout.
- TOC and bookmarks.

Exit criteria:

- A local book can be imported and read comfortably.

### Phase 3 - Source runtime foundation

Goal: build the engine skeleton without chasing every source failure.

Scope:

- Import Legado JSON and iOS-compatible JSON.
- Preserve raw JSON.
- Normalize source fields.
- Build unified source execution interface.
- Implement HTTP, cookie, cache, URL directive, charset, basic CSS/JSON extraction.
- Add source test reports.

Exit criteria:

- Selected fixture sources can run search -> info -> chapters -> content.

### Phase 4 - JS/WebView host

Goal: make complex sources possible.

Scope:

- WKWebView source sandbox.
- Bridge handlers.
- Qingyue-style functional source adapter.
- Common Legado JS host APIs.
- WebView verification flow.

Exit criteria:

- Sources requiring JS or WebView can be tested and reported instead of silently failing.

### Phase 5 - Product completion

Scope:

- Source manager.
- Batch source check.
- Search UX.
- Source switching.
- Purify rules.
- RSS.
- Reading history.
- Stats.
- App Store privacy and release hardening.

Exit criteria:

- The app can be treated as a serious release candidate.

## 13. Non-negotiable acceptance gates

The product is not done until all of these are true:

1. Reader is visually approved.
2. Reader is functionally comfortable for local books.
3. Source import works from paste, URL, and local file.
4. Search can run across imported sources.
5. A searched book can open detail, TOC, and content.
6. Reader settings take effect instantly.
7. App has no dead taps in main flows.
8. Keyboard interactions do not trap the user.
9. Pull-to-refresh and async UI never get stuck.
10. Source failures produce readable diagnostics.
11. CI can build an unsigned IPA.
12. The user can self-sign and test on iPhone.

## 14. Development rules

1. Do not call a prototype a product.
2. Do not hide broken controls behind good visuals.
3. Do not chase random source failures before the runtime foundation exists.
4. Do not rewrite adjacent code without a direct reason.
5. Do not push for every small patch.
6. Commit coherent milestones.
7. Keep old Flutter as product baseline.
8. Keep Qingyue Shiguang as source-runtime reference.
9. Keep Xiangse Guige XBS out of the first source engine route.
10. Prefer verifiable implementation over impressive-looking scope.

## 15. Immediate next action after this spec

After user approval of this spec, start Phase 1:

1. Audit Flutter page inventory and write a Swift parity ledger.
2. Fix the Swift app shell to match Flutter's product navigation model before polishing page interiors.
3. Produce visual companion screens only for layout or style choices that benefit from side-by-side comparison.
4. Implement the reader, home, discover, settings, and source-manager surfaces against the parity ledger.
5. Keep source-engine work separate from UI parity: import formats and fixtures may be absorbed, but the old engine is not copied.
6. Verify tap response, keyboard behavior, reader scroll/page behavior, local import, and search/detail/reader entry before calling any milestone testable.
