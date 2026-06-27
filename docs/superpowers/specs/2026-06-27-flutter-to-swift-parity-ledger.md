# Flutter to Swift Parity Ledger

Date: 2026-06-27

Decision: `D:\Gemini反重力\read` is the only product baseline for Swift UI, navigation, and user-facing behavior. Source compatibility is rebuilt in Swift; Flutter source code is only a reference corpus and fixture source.

## Product Rules

- Keep Flutter page inventory unless explicitly deferred.
- Keep Flutter user flow unless Swift native behavior clearly improves touch response, animation, blur, haptics, accessibility, or long-session smoothness.
- Do not copy the old Flutter source engine as implementation.
- Do copy useful source field mapping, import formats, diagnostics ideas, and test cases.
- Treat a Swift page as incomplete until taps, navigation, loading, empty, error, keyboard, and refresh states are accounted for.

## App Shell

Flutter baseline:

- `lib/features/home/views/home_page.dart`
- Indexed branch shell with home, discover, settings.
- Floating iOS glass tab bar.
- `resizeToAvoidBottomInset: false` so keyboard does not lift the bottom chrome.

Swift target:

- `SourceReadSwift/App/RootTabView.swift`
- Persistent three-tab shell with floating native material tab bar.
- Keyboard dismissal on tab switch.
- No paged `TabView` as the primary shell unless the Flutter baseline changes.

Current status:

- Shell changed from paged `TabView` to persistent indexed `ZStack`.
- Added lightweight end-of-drag horizontal tab switching without live page offset, to avoid the previous keyboard/paging gesture conflict.
- Needs device verification for tab switching smoothness and keyboard behavior.

## Home / Bookshelf

Flutter baseline:

- `lib/features/bookshelf/views/bookshelf_page.dart`
- Sections: currently reading, latest updates, bookshelf.
- Currently reading is horizontal and tappable.
- Latest updates clears state by real seen/update semantics.
- Local import entry supports TXT and EPUB.
- Library entry opens full shelf.

Swift target:

- `SourceReadSwift/Features/Bookshelf/BookshelfView.swift`
- `SourceReadSwift/Features/Bookshelf/BookshelfReaderGatewayView.swift`

Current status:

- Visual shell exists.
- Recent, updates, and shelf sections exist.
- Local TXT/EPUB import exists.
- Opening a bookshelf item now clears its update badge.
- Home cards and rows have press feedback/haptics.
- The hero card no longer uses a playback-style icon.
- Needs parity pass for empty states, horizontal card feel, card tap transitions, update clear semantics, and import picker reliability on device.

## Discover / Search

Flutter baseline:

- `lib/features/explore/views/explore_page.dart`
- Tabs: search, subscriptions, source writing.
- Search field, web mode, source manager card, fuzzy/precise mode, result filtering, progress, cancel, verification retry.
- Search result opens detail and explicit add is separate from browsing.

Swift target:

- `SourceReadSwift/Features/Discover/DiscoverView.swift`
- `SourceReadSwift/Features/Discover/BookDetailView.swift`
- `SourceReadSwift/Features/Discover/SearchBookRow.swift`
- `SourceReadSwift/Features/Discover/SourceWritingView.swift`

Current status:

- Search tabs and basic cards exist.
- Result detail and explicit add flow exist.
- Search result browsing no longer implicitly adds to the shelf.
- Explicit add now asks for confirmation.
- After previewing a chapter from details, returning to the detail page can prompt whether to add the book.
- Needs parity pass for filters, verification retry, loading timing, result tap transition, search cancellation, and source failure diagnostics.

## Reader

Flutter baseline:

- `lib/features/reader/views/reader_page.dart`
- `lib/features/reader/widgets/reader_settings_panel.dart`
- Core modes: scroll, page turn, cover.
- Tap zones, overlay, settings panel, TOC, bookmarks, source switching, progress restore, TTS, auto scroll, content purify.
- Settings must affect the current reader immediately.

Swift target:

- `SourceReadSwift/Features/Reader/ReaderView.swift`
- `SourceReadSwift/Features/Reader/ReaderSettingsModels.swift`

Current status:

- Native reader shell, settings, TOC, bookmarks, TTS, auto scroll, tap zones, and modes exist.
- Cover mode has a distinct drag/transition path instead of behaving exactly like horizontal page mode.
- Reader system color scheme follows the selected reading background for better toolbar/status contrast.
- Needs strict parity pass for actual mode behavior, immediate layout changes, restore position, gesture conflict, toolbar color contrast, and long-scroll ProMotion feel.

## Settings

Flutter baseline:

- `lib/features/settings/views/settings_page.dart`
- Appearance: system, light, dark, eye-care.
- Content: source manager, purify rules.
- General: clear cache, reading history, about.
- Additional product surfaces are routed from settings or discover: source catalog, source test, source verification, batch check, JSON editor, webview import.

Swift target:

- `SourceReadSwift/Features/Settings/SettingsView.swift`
- `SourceReadSwift/Features/SourceManager/SourceManagerView.swift`

Current status:

- Appearance, source manager, purify, cache, history, stats, about, diagnostics exist.
- Settings now uses the shared theme-aware page background modifier.
- Batch source check can optionally deep-test the first search result through detail, TOC, and content.
- Needs parity pass for tap feedback, route inventory, source test/batch check/verification/editor surfaces, and cache behavior.

## Source Compatibility Boundary

Do not use Flutter as the implementation baseline.

Use Flutter for:

- JSON field names and import compatibility examples.
- Known failing source classes.
- Diagnostic categories.
- User-facing management flow.
- Regression fixtures.

Build Swift around:

- Unified `search -> info -> chapters -> content` interface.
- Legado/iOS JSON normalization.
- URL directives.
- HTTP, headers, cookies, cache, charset, and response metadata.
- CSS, JSONPath-like, XPath subset, regex, and purify extraction.
- WKWebView/JavaScriptCore source host for dynamic sources.
- Clear source test reports instead of silent failure.

Current status:

- Added old Legado field normalization in Swift `BookSource`.
- Supported old fields include `ruleSearchUrl`, `ruleSearchList`, `ruleSearchName`, `ruleSearchAuthor`, `ruleSearchNoteUrl`, `ruleBookName`, `ruleBookAuthor`, `ruleIntroduce`, `ruleChapterList`, `ruleChapterName`, `ruleContentUrl`, `ruleBookContent`, `ruleBookContentReplace`, `ruleContentUrlNext`, `ruleFind*`, `name/url/group`, `serialNumber/customOrder`, and old boolean spellings.
- Added JSON-string rule object decoding, so `ruleSearch: "{\"bookList\":\"...\"}"` becomes structured fields.
- Added `httpUserAgent` as a request User-Agent alias.
- Added tests for legacy field normalization and JSON-string rule decoding.

Deferred:

- Xiangse Guige XBS first-class implementation.
- Copying Flutter's old source engine.

## Next Implementation Queue

1. Finish shell behavior correction and verify static changes.
2. Home parity pass: horizontal currently-reading cards, row/card transitions, and import reliability.
3. Reader parity pass: settings panel behavior, mode switching, toolbar contrast, position restore.
4. Discover parity pass: result filters, verification retry, source diagnostics.
5. Source manager parity pass: local/paste/URL import, test, batch check, JSON editor.
6. New Swift source runtime fixtures from Flutter examples.
