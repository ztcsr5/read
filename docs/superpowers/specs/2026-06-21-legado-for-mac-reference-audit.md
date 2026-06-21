# legado-for-mac-pub reference audit

Date: 2026-06-21

Reference:

- Local: `D:\QQ下载\Legado（开源阅读）的 macOS 版本\legado-for-mac-pub-main`
- Upstream: `https://github.com/Kequans/legado-for-mac-pub`

Purpose: identify compatible ideas that can improve `SourceReadSwift` without turning the iOS rewrite into a copy of the abandoned macOS project.

## Licensing boundary

The reference project is useful as an engineering reference, but it is GPL-3.0 licensed. For an App Store-grade iOS app, do not copy source files or large implementation blocks into `SourceReadSwift`. Use it as evidence for feature requirements, edge cases, and test fixtures, then implement clean Swift-native equivalents in our codebase.

## Useful architecture ideas

### Source engine

Observed files:

- `Sources/BookSource/BookSourceEngine.swift`
- `Sources/BookSource/RuleAnalyzer.swift`
- `Sources/BookSource/RuleConnector.swift`
- `Sources/BookSource/JavaScriptEngine.swift`

Useful ideas:

- Search URL handling covers comma-suffixed JSON request config, POST bodies, merged headers, `{key}` replacement, and page arithmetic such as `{{(page - 1) * 10}}`.
- Rule parsing is split into explicit layers: rule segmentation, connector handling, JS handling, regex cleanup, and final extraction.
- JS bridge keeps a persistent `java.put/get` cache and exposes network helpers.
- Regex cleanup supports `##pattern##replacement` style transforms.

Current SourceReadSwift status:

- Already has cleaner boundaries across `SearchURLResolver`, `SourceRequestBuilder`, `JSCoreRuntime`, HTML/JSON parsers, and diagnostics.
- Newly adopted from this audit: `{key}/{keyword}/{page}` single-brace placeholders and safe integer page arithmetic in `LegadoRuleResolver`.

Do next:

- Connector semantics for `||` and `%%` are now partially adopted in the Swift parser; remaining work is to extend the same top-level operator handling into deeper JS/template/XPath compatibility paths.
- Add more fixture tests for comma JSON request config and mixed JSON field + JS segment rules.
- Continue expanding JS response-object compatibility beyond the adopted `java.ajax(url).body()` path if real-source fixtures require it.

### Reader/cache

Observed files:

- `Sources/Views/ReaderView.swift`
- `Sources/Database/ChapterContentDAO.swift`
- `Sources/Models/ChapterContent.swift`
- `Sources/Config/AppConfig.swift`

Useful ideas:

- Cache chapter content by `chapterUrl`.
- Track cache time and clean old chapter cache after 30 days.
- Preload a configurable number of following chapters.
- Persist scroll position as a chapter-relative percentage.

Current SourceReadSwift status:

- Reader can load online/local chapters, track progress/session stats, switch source, and expose controls.
- Online chapter cache now exists and is used before network loads.
- Successful online chapter parses are cached by source URL, chapter URL, and active purify-rule signature.
- Reader loading preloads the next two chapters in the background.
- If a network reload fails after purify rules changed, reader loading can fall back to stale cached content for the same source/chapter instead of failing the reading session outright.
- Settings can show cache count/estimated size and clear/remove expired cache entries.

Do next:

- Surface a subtle "using cached copy" state in the reader when stale fallback is used.
- Make preload count configurable after the reader settings model is split into a dedicated view model.
- Add device QA for cache growth, low-storage behavior, airplane-mode reading, and cache cleanup.

### Data model

Observed files:

- `Sources/Database/DatabaseManager.swift`
- `Sources/Models/ReadingData.swift`
- `Sources/Models/ReaderConfig.swift`

Useful ideas:

- Separate bookmarks, reading records, replace rules, book chapters, and chapter contents as first-class persistence tables/models.
- Store bookmark position inside a chapter, not only chapter index.
- Store replace/purify rule name, group, order, regex flag, enabled flag, and scope.

Current SourceReadSwift status:

- JSON persistence is acceptable for the current rewrite milestone but not final App Store-grade durability.
- Bookmarks and purify rules exist but are simpler than the reference.

Do next:

- Extend bookmarks with paragraph/character offset.
- Extend purify rules with name, group, order, regex flag, and scope.
- Decide before release whether to stay on JSON stores or move durable app data to SQLite/GRDB.

### UI/product flow

Useful ideas:

- The reference keeps search -> read -> switch source and RSS -> parse/read as visible product flows.
- It exposes reader settings, chapter list, progress control, shortcuts, and cache behavior as user-facing controls.

Current SourceReadSwift status:

- Native SwiftUI shell and smoother interaction are better aligned with the user's desired iOS Podcasts-style product.
- Some reference UI is macOS-specific and should not be copied to iOS.

Do next:

- Keep our Flutter/iOS Podcasts UI baseline.
- Borrow only capability coverage: cache/preload status, richer bookmarks, exact progress restore, source switch clarity.

## Immediate adopted change

Implemented in `SourceReadSwift` after this audit:

- Single-brace search placeholders: `{key}`, `{keyword}`, `{page}`, `{baseUrl}`.
- Safe integer page arithmetic in `{{...}}`, e.g. `{{(page - 1) * 10}}`.
- JS network helpers now return response-like objects with `body()`, `text()`, `toString()`, and `valueOf()` while preserving string coercion.
- Unit coverage in `SourceReadSwiftTests/SearchURLResolverTests.swift`.
- Chapter content cache/preload and stale-cache fallback are now implemented in clean Swift-native storage code.

## Not worth copying

- The reference has several one-off URL fixes and site-specific patches. These should become diagnostics or generic URL normalization tests, not hardcoded special cases.
- The reference JavaScript MD5 implementation is a placeholder based on Swift hash value. Our implementation uses CryptoKit-backed MD5/SHA256 helpers instead.
- macOS keyboard shortcut handling is useful conceptually but not directly portable to iOS, except for future hardware keyboard support on iPad.
