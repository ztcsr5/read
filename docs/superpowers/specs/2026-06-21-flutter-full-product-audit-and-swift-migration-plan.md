# Flutter full product audit and Swift migration plan

Date: 2026-06-21

Branch: `codex/native-swift-ci`

Objective: rebuild SourceRead as a native Swift iOS app that preserves the old Flutter product's UI layout, feature set, source compatibility, reading behavior, and daily-use reliability, while improving native smoothness and App Store readiness.

## 0. Source engine migration principle

The old Flutter source engine is an absorption target, not a code-copy target.

For UI, reader features, bookshelf behavior, settings, history, and product flows, Flutter is the parity baseline. For source compatibility success rate, Swift must use a new Swift-native engine architecture. The Flutter parser is used to extract capability requirements, edge cases, and acceptance tests, but the Swift engine should improve request handling, charset decoding, JavaScript execution, WebView fallback, diagnostics, and recovery instead of mechanically porting legacy implementation details.

Acceptance is based on import/search/detail/TOC/content success rate against tests and realistic sources, not on how closely the Swift code resembles the old Flutter parser.

## 1. Non-negotiable standard

This migration is not considered complete because it can compile, pass CI, or export an unsigned IPA. Those are only delivery mechanics.

The product is complete only when:

1. Every Flutter route has a Swift equivalent, or an explicit documented replacement.
2. Every Flutter persistent model has a Swift persistence equivalent.
3. Existing Flutter source import and Legado compatibility tests are ported or mirrored in Swift.
4. Realistic book source JSON imports work from paste, file, URL, wrapped JSON, and yuedu/legado links.
5. Search, add-to-bookshelf, book detail, TOC, chapter content, progress restore, bookmarks, settings, and source switching form a working daily reading loop.
6. Reader UI and settings match the Flutter product's functional surface while using native SwiftUI smoothness.
7. App Store compliance work is finished: privacy manifest, permissions copy, network security decisions, no debug placeholders, stable error states, accessibility, dark/light themes, release CI artifacts.

## 2. Flutter product inventory

The old Flutter branch `origin/main` is the behavior baseline.

### 2.1 Navigation/routes

Flutter route file: `lib/app/routes.dart`

Required Swift equivalents:

- `/bookshelf`
- `/explore`
- `/settings`
- `/reader/:bookId`
- `/sources`
- `/source_test`
- `/source_batch_check`
- `/source_verify`
- `/source_catalog`
- `/book_source`
- `/source_explore`
- `/source_diagnostic`
- `/source_json_editor`
- `/web_source`
- `/webview_import`
- `/library`
- `/about`
- `/reading_history`
- `/purify`
- `/rss_articles`
- `/rss_reader`

The Swift tab shell must keep the Flutter app's mental model: bookshelf/home first, discover/search second, settings/source management third. Modal/detail routes must remain reachable without burying core flows.

### 2.2 Persistence/data models

Flutter persistence file: `lib/app/database/database_provider.dart`

Flutter uses Isar schemas:

- `Book`
- `Bookmark`
- `BookSource`
- `Chapter`
- `ReadingProgress`
- `ReadingStats`
- `BookGroup`
- `RssSource`
- `SourceCatalog`

Swift must provide equivalent durable storage. Current Swift JSON persistence is acceptable as an intermediate implementation, but the model surface must match Flutter before product completion.

### 2.3 Bookshelf and local library

Flutter references:

- `lib/features/bookshelf/views/bookshelf_page.dart`
- `lib/features/bookshelf/views/library_page.dart`
- `lib/features/bookshelf/viewmodels/bookshelf_viewmodel.dart`

Existing Flutter behavior:

- Load all favorited/added books.
- Sort by recent reading.
- Import local TXT/EPUB files.
- Accept external `file://` imports.
- Save parsed chapters.
- Delete books.
- Create/delete groups.
- Move books between groups.
- Track pending import file path.

Swift target:

- Bookshelf grid/list with Flutter-style layout and native transitions.
- Real persisted books, chapters, groups, and progress.
- Local TXT/EPUB import through document picker and file URL handoff.
- Group management.
- Recent books section.
- Empty states that guide import/search instead of placeholder-only UI.

### 2.4 Discover/search

Flutter references:

- `lib/features/explore/views/explore_page.dart`
- `lib/features/explore/viewmodels/explore_viewmodel.dart`

Existing Flutter behavior:

- Three discover modes: find books, subscription/RSS, write/manage source.
- Search enabled sources.
- Concurrent source search in batches of 8.
- Search cancellation.
- Fuzzy and exact modes.
- Result de-duplication.
- Exact search ranking: exact title first, then stronger chapter/word signals.
- Failed source search exposes site verification path.
- `addToBookshelf(Book)` tries detail, TOC, and saves book even if TOC fetch fails.

Swift target:

- Discover must not be a cosmetic search box. It must execute the same multi-source flow.
- Add-to-bookshelf must persist book metadata, source identity, TOC where available, and still allow retry if detail/TOC fails.
- Search failures must be visible per source with actionable test/diagnostic entry.

### 2.5 Source management, catalog, RSS, import

Flutter references:

- `lib/features/settings/viewmodels/book_source_viewmodel.dart`
- `lib/features/settings/views/source_management_page.dart`
- `lib/features/settings/views/source_catalog_browser_page.dart`
- `lib/features/settings/views/source_json_editor_page.dart`
- `lib/features/settings/views/webview_import_page.dart`
- `lib/features/explore/views/rss_source_articles_page.dart`
- `lib/features/explore/views/rss_article_reader_page.dart`

Existing Flutter behavior:

- Manage book sources, RSS sources, and source catalogs together.
- Smart import from JSON, URL, file, yuedu links, legado links, and shared text.
- GitHub `blob` URL to raw URL normalization.
- URL import with `User-Agent` and broad `Accept` headers.
- Cloudflare/challenge page detection.
- JSON normalization from wrappers: `data`, `list`, `items`, `bookSources`, `sources`, `bookSource`.
- Detect imported item kind: book source, source catalog, RSS.
- File import from bytes/path.
- Delete, batch delete, enable, disable.
- Save JSON edits.
- Import from catalog repository.
- Clear user-facing success/error/message state.

Swift target:

- `SourceStore` must become a source registry, not just a list of `BookSource`.
- It must store:
  - Book sources
  - RSS sources
  - Source catalogs
  - Import reports
  - Source health/last test data
- Source import tests from Flutter must be ported first, then implementation changed until tests pass.

### 2.6 Legado/source compatibility engine

Flutter references:

- `lib/data/parsers/legado_parser.dart`
- `lib/data/parsers/legado/legado_js_engine.dart`
- `lib/data/parsers/legado/legado_request_builder.dart`
- `lib/data/parsers/legado/legado_rule_evaluator.dart`
- `lib/data/parsers/legado/legado_session_store.dart`
- `lib/data/parsers/legado/cloudflare_interceptor.dart`

Existing Flutter behavior:

- Dio network layer with Cloudflare interceptor.
- WebView fallback and cookie manager.
- Session store.
- GBK/GB2312/GB18030 detection and decoding.
- HTML/XML/JSON parsing.
- CSS selector, XPath-ish, JSONPath-ish rule extraction.
- JavaScript rule execution:
  - `@js`
  - `<js>...</js>`
  - `java.ajax`
  - `java.put`
  - MD5/Base64 helper aliases
- `searchUrl` construction:
  - `{{key}}`
  - `{{keyword}}`
  - `{{page}}`
  - `{{source.key}}`
  - raw JS search URL
  - embedded POST config
  - headers/body/charset
- Search, book detail, TOC, content:
  - `searchBooks`
  - `parseBookInfo`
  - `getChapterList`
  - `getChapterContent`
- Explore and RSS:
  - `parseExploreBooks`
  - `parseRssArticles`
  - `parseRssContent`
- Fallback parsers for malformed/partial HTML and JSON.
- Diagnostics through `testSource`, `LegadoTestReport`, and `LegadoTestStep`.
- Broken-source handling:
  - Cloudflare detection
  - duplicate path retry
  - content `replaceRegex`
  - `sourceRegex`
  - `webJs`
  - `nextContentUrl`
  - suspicious chapter detection

Swift target:

- Current Swift parser pieces must be treated as partial.
- Compatibility must be driven by a Swift test matrix ported from Flutter tests plus selected real source fixtures.
- WebView fallback must be explicit and user-visible because it affects App Store privacy/permission copy and runtime behavior.

### 2.7 Reader

Flutter references:

- `lib/features/reader/viewmodels/reader_viewmodel.dart`
- `lib/features/reader/views/reader_page.dart`
- `lib/features/reader/widgets/reader_settings_panel.dart`
- `lib/features/reader/views/reader_toc_page.dart`
- `lib/features/reader/views/reader_book_details_page.dart`
- `lib/features/reader/views/reader_bookmarks_page.dart`
- `lib/features/reader/widgets/source_selection_bottom_sheet.dart`
- `lib/features/reader/services/tts_service.dart`

Existing Flutter state/features:

- Book, chapters, loaded chapters, flattened reader items.
- Current chapter index, scroll position, char offset, percentage progress.
- Loading more and error states.
- Font size, line height, letter spacing.
- Title spacing, paragraph spacing.
- Top/bottom padding, paragraph indent, footer height.
- Font family and font weight.
- Page padding and text justification.
- Built-in backgrounds, custom color, custom wallpaper.
- Modes: scroll, page turn, cover.
- Keep screen on.
- Volume key page turn.
- 3x3 tap zone action map.
- Bookmarks.
- Auto-scroll and speed.
- TTS playback state.
- Immersive mode.
- Infinite scroll loading.
- Overlay top/bottom bars.
- TOC, source switching, bookmark toggle, book details.
- Save progress on scroll, app pause, and dispose.
- Restore progress on re-entry.
- Exit confirm add-to-bookshelf for non-favorite online book.

Swift target:

- Reader is a product core, not a demo view.
- Swift reader must match Flutter feature surface first, then improve native smoothness.
- Must preserve:
  - Scroll mode
  - Page mode
  - Cover transition mode
  - 3x3 tap zones
  - Full settings panel
  - TOC/bookmark/detail/source switch flows
  - Progress persistence
  - Offline chapter cache
  - TTS

### 2.8 Settings, statistics, history, purify rules

Flutter references:

- `lib/features/settings/views/settings_page.dart`
- `lib/features/settings/views/reading_history_page.dart`
- `lib/features/settings/views/purify_rules_page.dart`
- `lib/features/stats/views/stats_page.dart`
- `lib/data/repositories/stats_repository.dart`

Existing behavior:

- Appearance modes: system/light/dark/eye-care.
- Source management entry.
- Purify rules.
- Clear cache.
- Reading history.
- About page.
- Today reading duration.
- Total duration.
- Consecutive days.
- Words/pages/sessions.

Swift target:

- Settings must be functional, persisted, and connected to reader/search/source behavior.
- Reading history and stats must read from real progress/session records.

### 2.9 Local web source service

Flutter reference:

- `lib/features/settings/services/local_source_web_service.dart`

Existing behavior:

- Local HTTP server on ports 1122-1132.
- LAN and loopback URLs.
- Access token.
- Local network permission probe.
- CORS.
- `/health`
- `/api/status`
- `/api/sources`
- Source CRUD.
- `/api/sources/import`
- `/api/sources/:id/test`
- Embedded responsive HTML editor/workbench.

Swift target:

- Implement only after core product is usable.
- Must be App Store reviewed carefully because it opens a local HTTP service and requests local network permission.
- Must have explicit user start/stop, token display, and privacy explanation.

### 2.10 Diagnostics and auto-repair

Flutter references:

- `lib/features/source_diagnostic/services/source_diagnostic_service.dart`
- `lib/features/source_diagnostic/services/compatibility_analyzer.dart`
- `lib/features/source_diagnostic/services/redesign_detector.dart`
- `lib/features/source_diagnostic/services/rule_rank_engine.dart`
- `lib/features/source_diagnostic/services/rule_suggest_engine.dart`
- `lib/features/source_diagnostic/services/source_auto_repair_service.dart`
- `lib/features/source_diagnostic/services/source_generator_service.dart`
- `lib/features/source_diagnostic/views/source_diagnostic_page.dart`

Swift target:

- Source tests must first be practical and reliable.
- Auto-repair/generation comes after parser parity; otherwise it will generate suggestions for an incomplete engine.

### 2.11 Flutter acceptance tests to mirror

Flutter test references:

- `test/source_import_test.dart`
- `test/source_import_link_parser_test.dart`
- `test/legado_engine_test.dart`
- `test/local_source_web_service_test.dart`
- `test/parser_test.dart`

Swift must port or mirror these as XCTest. New Swift code is not accepted without tests for import/parser behavior.

## 3. Current Swift status

Current Swift branch has:

- Native SwiftUI app shell.
- Root tabs.
- Partial Bookshelf/Discover/Settings UI.
- Basic source manager.
- Basic book source JSON import.
- Partial Legado parser modules.
- Basic search/detail/TOC/content flow.
- Basic reader controls.
- Bookshelf and progress persistence added in `a35b460`.
- Source import now handles more Legado/Yuedu wrappers, aliases, request headers, POST/body directives, and embedded share JSON.
- Source manager now has a practical search/detail/TOC/content diagnostic chain with stage-specific failure advice.
- Reader now has usable native TTS controls, auto-scroll controls, TOC jump, source switching entry, and recovery actions when a saved online book fails to reopen.
- Local TXT and EPUB import paths exist, with a minimal EPUB parser and fixture test.
- Unit tests for partial parser/request/source store pieces.

Current Swift gaps:

- UI does not yet fully match the Flutter product's functional layout.
- No full route parity.
- Source import taxonomy is still incomplete compared with Flutter, although RSS and catalogs now exist as first-class stored items.
- `BookSource` model drops many raw fields and aliases needed for real Legado compatibility.
- Reader is far from Flutter feature parity.
- Local TXT/EPUB import exists but needs device verification, richer EPUB coverage, external file handoff validation, and cache/progress integration hardening.
- Groups, bookmarks, stats, reading history, purify rules, diagnostics, source testing, batch checking, JSON editor, WebView import, and local web editor service are missing or partial.
- Current IPA size is not a quality signal. A small Swift IPA is normal, but this specific app is small also because many product modules are still absent.

## 4. Target Swift architecture

### 4.1 App layer

- `SourceReadSwiftApp`
- `AppState`
- `RootTabView`
- App-wide navigation coordinator
- App-wide settings store

Responsibilities:

- Bootstrap stores.
- Restore user state.
- Own global presentation routes.
- Keep tabs aligned with Flutter mental model.

### 4.2 Domain models

Required model groups:

- `BookRecord`
- `ChapterRecord`
- `BookmarkRecord`
- `ReadingProgressRecord`
- `ReadingStatsRecord`
- `BookGroupRecord`
- `BookSourceRecord`
- `RssSourceRecord`
- `SourceCatalogRecord`
- `SourceHealthRecord`
- `DiagnosticReportRecord`
- `PurifyRuleRecord`

Compatibility rule: raw source JSON must be retained losslessly enough to re-export and re-edit.

### 4.3 Persistence/repositories

Suggested staged persistence:

1. Continue JSON file persistence for speed while expanding models.
2. Introduce repository interfaces:
   - `BookRepository`
   - `SourceRepository`
   - `StatsRepository`
   - `SettingsRepository`
3. Keep storage implementation swappable.
4. If JSON files become fragile, move to SQLite/CoreData/GRDB later without changing UI/domain APIs.

### 4.4 Source engine

Required modules:

- Import link parser
- Import normalizer/classifier
- Request builder
- URL directive parser
- Response text decoder
- Cookie/session store
- JS runtime bridge
- Rule resolver
- HTML/XML parser
- JSON parser
- Search/detail/TOC/content pipelines
- RSS parser
- WebView fallback
- Diagnostic runner

Parser work must be test-first because regressions here make the whole product unusable.

### 4.5 UI modules

Swift modules should map to Flutter features:

- Bookshelf
- Library/local import
- Discover/search
- Reader
- Source manager
- Source catalog browser
- Source JSON editor
- Source test/batch check/verify
- WebView import
- RSS articles/reader
- Source diagnostic
- Purify rules
- Reading history
- Stats
- About/settings

### 4.6 Reader engine

Split reader into smaller units:

- `ReaderSessionStore`: loads book/chapters/progress/bookmarks.
- `ReaderContentLoader`: loads/caches chapter content.
- `ReaderLayoutSettings`: persisted typography/background/tap-zone settings.
- `ReaderNavigationModel`: chapter/page/scroll state.
- `ReaderTTSController`: native speech.
- `ReaderView`: SwiftUI rendering and gestures.

This prevents one giant reader file from becoming unmaintainable.

## 5. Gap table

| Flutter feature | Current Swift status | Required Swift implementation | Acceptance test | Priority |
| --- | --- | --- | --- | --- |
| Main tabs | Partial | Match bookshelf/discover/settings flow and Flutter information hierarchy | Manual UI checklist | P0 |
| All Flutter routes | Partial | Add Swift screens or documented replacements | Route parity checklist | P0 |
| Book persistence | Partial | Full book/chapter/progress/bookmark/group storage | XCTest repository round trip | P1 |
| Reading progress | Partial | Chapter, scroll, char offset, percentage, last read | Reopen restores exact state | P1 |
| Source import links | Partial/unknown | Port yuedu/legado/shared-text parser | Port `source_import_link_parser_test.dart` | P1 |
| JSON import wrappers | Partial | Support `data/list/items/bookSources/sources/bookSource` | Port `source_import_test.dart` | P1 |
| Source catalogs | Partial | Model/import/list/catalog import and import status exist; rich remote browsing/filtering still needed | XCTest + UI smoke | P2 |
| RSS | Partial | RSS model/import/article list exists; in-app article reader and rule-based RSS content still needed | RSS fixture test | P2 |
| Source manager batch ops | Partial | Batch delete/enable/disable exists; batch test still needed | Unit + UI smoke | P2 |
| Source JSON editor | Partial | Book source JSON edit/save exists; RSS/catalog edit and lossless re-export still needed | Edit-save-import test | P2 |
| GBK decoding | Partial | Ensure GBK/GB2312/GB18030 detection | Decoder tests | P3 |
| Search URL JS/POST/header | Partial | Template/JS search URL, source variables, POST/header directives | Request builder tests | P3 |
| `@js`/`<js>` rules | Partial | JSCore bridge with java/network/base64/hash/CryptoJS subset helpers | JS rule fixtures | P3 |
| HTML/CSS rules | Partial | Full common selector attr/text rules | Parser tests | P3 |
| JSONPath-ish rules | Partial | Match Flutter resolver behavior | Parser tests | P3 |
| Book detail | Partial | Full metadata parsing and fallback | Fixture tests | P4 |
| TOC | Partial | TOC parse, relative URLs, duplicate retry | Fixture tests | P4 |
| Content | Partial | replaceRegex, nextContentUrl, purify | Fixture tests | P4 |
| Add to bookshelf | Partial | Save detail/TOC/progress and tolerate TOC failure | End-to-end mocked source test | P4 |
| Local TXT | Partial | File picker, parse, save chapters, external file handoff | Local fixture import test + device import | P5 |
| Local EPUB | Partial | EPUB parser/import, multi-file spine, metadata, device import | EPUB fixture import test + device import | P5 |
| Reader scroll mode | Partial | Infinite load, progress save, overlay | Manual + state tests | P6 |
| Reader page/cover modes | Partial | Basic page/cover mode entry exists; true text pagination still needs refinement | UI smoke | P6 |
| Reader settings | Partial | Typography/background/mode/tap-zone settings exist; full Flutter settings surface still needs completion | Settings persistence test | P6 |
| Bookmarks | Partial | Add/remove/list/jump exists with paragraph-level position, sorted list metadata, and current-position highlighting; needs device smoke | XCTest + UI smoke | P6 |
| Source switch | Partial | Switch source, match chapter title, error-page recovery | Mocked source test | P6 |
| TTS | Partial | Native speech start/stop/next, queue state, interruption handling | Manual + state test | P6 |
| Chapter cache/preload | Partial | Online chapter content cache and next-chapter preload exist; cache count/size/expiry exist and need deeper device QA | Cache store tests + reader smoke | P6 |
| Diagnostics | Partial | Single-source deep test, selected-source batch search check, and persisted search health history exist; full batch detail/TOC/content still needed | Diagnostic fixture test | P7 |
| Auto repair | Missing | Rule suggestion after parser parity | Golden suggestions | P7 |
| Local web editor | Missing | Explicit start/stop local server + token | Local API tests | P8 |
| Purify rules | Partial | Editor, persistence, duplicate-safe import, built-in presets, preview testing, bulk enable/disable, and content application exist; diagnostics integration still needed | Content purification + store persistence tests | P9 |
| Reading history/stats | Partial | Per-book history and aggregate stats screen exist; daily/weekly charts and richer session timeline still needed | Repository + UI smoke | P9 |
| App Store hardening | Partial | Privacy, permissions, accessibility, release checks | Release checklist + CI | P10 |

## 6. Implementation plan

### P0 - Baseline preservation and verification

1. Keep `origin/main` Flutter as immutable baseline.
2. Keep Swift branch buildable after every commit.
3. Verify CI and unsigned IPA for current `HEAD`.
4. Create route parity checklist.
5. Create UI parity checklist from Flutter screenshots and files.
6. Add a release-readiness checklist under docs.

Exit criteria:

- CI status for latest Swift commit is known.
- Plan document is committed.
- No further feature work proceeds without mapping to this plan.

### P1 - Core persistence and import-test foundation

1. Add Swift records for all Flutter Isar schemas.
2. Introduce repository interfaces.
3. Expand JSON persistence or add a storage layer that can round-trip all records.
4. Implement `SourceImportLinkParser` in Swift.
5. Port `source_import_link_parser_test.dart`.
6. Expand source JSON normalization/classification.
7. Port `source_import_test.dart`.

Exit criteria:

- Paste/file/link import tests pass.
- Duplicate source update behavior passes.
- Catalog/RSS/book-source classification tests pass.

### P2 - Source manager, catalogs, RSS

1. Make `SourceStore` manage book sources, RSS sources, and catalogs.
2. Add source management tabs/sections matching Flutter.
3. Add batch enable/disable/delete.
4. Add source JSON editor.
5. Add catalog browser/import.
6. Add RSS article list and RSS reader.
7. Add WebView import screen stub with real import handoff.

Exit criteria:

- User can import a real mixed source pack and see correct categories.
- User can enable/disable/delete/edit sources.
- Catalog import and RSS read flow are usable.

### P3 - Legado engine parity

1. Audit every parser capability against Flutter `legado_parser.dart`.
2. Complete request builder: headers, body, POST config, charset, page/key/source substitution.
3. Complete response decoder.
4. Complete HTML/CSS/XML/JSON extraction.
5. Complete JSCore helpers for common `java.*` rules.
6. Complete cookie/session handling.
7. Complete WebView fallback boundary.
8. Port `legado_engine_test.dart` and `parser_test.dart`.

Exit criteria:

- Common realistic sources search, detail, TOC, and content flow pass.
- Engine errors are diagnostic, not silent.

### P4 - End-to-end online book flow

1. Search across enabled sources in concurrent batches.
2. Add cancellation.
3. Rank and deduplicate results.
4. Detail view loads metadata/TOC.
5. Add-to-bookshelf persists source/book/chapter data.
6. Reader gateway opens saved online books.
7. Chapter content is lazy-loaded and cached.

Exit criteria:

- User can import sources, search a book, add it, open it, read chapters, close app, reopen, and continue.

### P5 - Local TXT/EPUB library

1. Implement document picker.
2. Port TXT parsing.
3. Add EPUB dependency or parser.
4. Save local book records and chapters.
5. Handle external `file://` handoff.

Exit criteria:

- TXT and EPUB fixture imports work and open in the same reader.

### P6 - Full reader parity

1. Split reader into session/content/settings/navigation/TTS modules.
2. Implement full settings panel.
3. Implement scroll mode parity.
4. Implement page mode.
5. Implement cover transition mode.
6. Implement 3x3 tap zones.
7. Implement bookmarks UI.
8. Implement TOC and jump behavior.
9. Implement source switching.
10. Implement auto-scroll.
11. Implement TTS.
12. Implement progress save on app lifecycle.

Exit criteria:

- Reader can be used daily without missing core Flutter controls.
- Settings persist and are applied immediately.

### P7 - Source diagnostics and repair tools

1. Add source test screen.
2. Add batch check screen.
3. Add verification WebView.
4. Add diagnostic report model.
5. Add compatibility analyzer.
6. Add rule suggestions only after engine behavior is reliable.

Exit criteria:

- Broken source failures show which step failed and why.

### P8 - Local web source editor

1. Decide App Store-safe implementation constraints.
2. Add explicit local server start/stop.
3. Add token.
4. Add `/health`, `/api/status`, `/api/sources`, import, CRUD, and test endpoints.
5. Add embedded editor page.
6. Port local web service tests.

Exit criteria:

- Feature is off by default, user-controlled, documented, and test-covered.

### P9 - Settings, purify, history, stats, about

1. Persist app appearance.
2. Add purify rules editor and content application.
3. Add reading history.
4. Add reading stats/session tracking.
5. Add cache clearing.
6. Add about page and build metadata.

Exit criteria:

- Settings are connected to real behavior and not static rows.

### P10 - App Store hardening

1. Review privacy manifest.
2. Review local network and arbitrary load usage.
3. Remove debug placeholders and seeded fake source UI from release.
4. Add accessibility labels and dynamic type support.
5. Verify dark/light/eye-care modes.
6. Stabilize error states and empty states.
7. Run CI on every commit.
8. Produce unsigned IPA artifact.
9. Write user handoff instructions for self-signing.

Exit criteria:

- The product can be handed off as a serious App Store candidate build, not a prototype.

### P11 - Full QA matrix

QA must cover:

- Fresh install.
- Upgrade from previous Swift data.
- Source import from paste/file/URL/link/catalog.
- Search success/failure/cancel.
- Add-to-bookshelf success/partial failure.
- Reader modes/settings/progress/bookmarks/TTS.
- Local TXT/EPUB.
- RSS.
- Diagnostics.
- Offline/weak network.
- Dark/light/large text.
- iPhone small and large screens.
- Release IPA artifact.

## 7. Development rules from this plan

1. Do not add UI that looks finished but has no real backend behavior unless explicitly marked as blocked and temporary.
2. Do not call a feature complete until it has persistence, error handling, and at least a smoke test or fixture test.
3. Do not chase random one-off source failures before source import and parser tests are ported.
4. Prefer small, verifiable commits by priority stage, but do not stop at arbitrary five-step chunks.
5. If a Swift design differs from Flutter, document the reason and user-visible effect.
6. Keep old Flutter behavior as the reference even when current Swift UI feels smoother.

## 8. Immediate next tasks

1. Keep working locally without pushing every small commit, because GitHub Actions quota is limited.
2. Finish the next coherent product milestone before pushing:
   - Reader error recovery and source switching polish.
   - Source diagnostics/reporting polish.
   - Parser/import compatibility tests for the newly supported aliases.
   - Documentation of what is still missing before device QA.
3. After a coherent milestone is committed, push once and run CI/IPA only when the app is worth testing.
4. Then continue into P3/P6 work:
   - More JS API compatibility.
   - More HTML/JSON rule operators.
   - Reader page mode/tap-zone/settings parity.
   - Bookmarks/history/stats/purify parity.

## 10. Current local milestone notes

This local milestone is intentionally not pushed yet.

Completed since the initial audit:

- Broadened source import/link compatibility:
  - Embedded JSON extraction from share links.
  - Wrapped object import for `bookSource`, `bookSources`, `sources`, `data`, `list`, and `items`.
  - Request method/body/header aliases.
  - Dictionary POST body handling.
- Improved Swift source engine compatibility:
  - JS bridge variable storage and network helper directives.
  - Charset-aware response decoding.
  - More HTML/JSON rule transforms.
  - Content cleanup rules.
- Improved reader daily-use flow:
  - Native TTS and auto-scroll controls are functional.
  - Source switching can update an existing bookshelf item without changing its identity.
  - Saved online reader failure now exposes "try another source" and "retry current source" actions.
- Added local EPUB import:
  - ZIP/OPF/spine parser.
  - Minimal EPUB fixture test.
- Improved source diagnostics:
  - Source manager test output now reports search/detail/TOC/content stages.
  - Failure output includes stage-specific suggestions instead of only raw errors.
- Improved source maintenance:
  - Book source batch select/enable/disable/delete.
  - Destructive batch delete confirmation.
  - Book source JSON edit/save by `bookSourceUrl`.
  - Import reports now distinguish added, updated, and ignored items instead of estimating from total count.
- Improved reader controls:
  - Reader bottom overlay now shows chapter count and percentage.
  - Previous/next chapter buttons are available when chapter switching is possible.
  - Bookmark list entries can jump to their chapter.
  - Basic scroll/page/cover mode switch is persisted.
  - 3x3 tap zone actions are configurable and covered by unit tests.
- Improved RSS and history:
  - Discover and Source Manager can open a real RSS/Atom article list.
  - RSS feed parsing is covered by unit tests.
  - Reading sessions now record open time, session count, and total reading duration per book.
- Improved purify rules:
  - Settings now exposes a purify rule editor.
  - Rules persist to app support storage and can be added, deleted, disabled, or batch-imported by line.
  - Duplicate rules are ignored during add/import to avoid noisy cleanup lists.
  - Enabled global purify rules are applied after source-level content cleanup.
  - Content parsing and store persistence are covered by unit tests.
- Improved reading statistics:
  - Settings and profile now expose an aggregate reading stats screen.
  - Stats summarize total books, local/online split, read books, bookmarks, reading sessions, total duration, average progress, most-read book, and recent reads.
  - Aggregation is covered by unit tests instead of being UI-only placeholder data.
- Improved source diagnostics:
  - Source Manager management mode now supports selected-source batch search checks.
  - Batch results classify each source as PASS/WARN/FAIL and surface focused search-stage advice.
  - Single-source deep testing remains available for search -> detail -> TOC -> content verification.
- Improved source catalogs:
  - Catalog import now records imported count, last status, and last imported time.
  - Catalog rows surface import count and recent import time instead of hiding status in JSON.
  - Catalog status persistence is covered by unit tests.
- Improved JSCore compatibility:
  - Added MD5/SHA256 native helpers.
  - Added common Legado aliases: `java.md5`, `java.hexMd5`, `java.MD5`, `java.sha256`, `java.base64`, `java.decodeBase64`, `md5`, `hexMd5`, `atob`, and `btoa`.
  - Added a minimal `CryptoJS.MD5(...).toString()` / `CryptoJS.SHA256(...).toString()` compatibility shim.
  - `java.ajax`, `java.get` URL loads, and `java.post` now return response-like objects with `body()` while preserving string coercion.
  - Added minimal chainable `java.connect(...)` and `org.jsoup.Jsoup.connect(...)` support for GET/POST requests with headers, user-agent, and form body data.
  - Added URI/base64/hash aliases: `java.encodeURI`, `java.encodeURIComponent`, `java.decodeURI`, `java.decodeURIComponent`, `java.md5Encode`, `java.base64DecodeToString`, `java.base64Decoder`, `java.unbase64`, and global `unbase64`.
  - Added `java.sha1`, `CryptoJS.SHA1`, `CryptoJS.HmacSHA256`, and minimal `CryptoJS.enc.Utf8/Hex/Base64` parse/stringify support for common signing snippets.
  - `java.getString(rule)`, `java.getStringList(rule)`, and `java.getElements(rule)` can now read from the current global `html` / `result` content, matching common one-argument Legado JS snippets.
  - `java.getString(rule, true/false)` and `java.getStringList(rule, true/false)` treat the boolean as a Legado-style extraction flag instead of accidentally using it as the rule string.
  - JS string lists now expose Java List-style `.get(index)`, `.size()`, and `.isEmpty()` aliases while still behaving like arrays.
  - JS strings expose Java-style `.contains(...)`, `.startsWith(...)`, `.endsWith(...)`, `.equals(...)`, `.equalsIgnoreCase(...)`, and `.replaceAll(...)` aliases for common Legado snippets.
- Improved search URL compatibility:
  - `{{source.xxx}}` placeholders now resolve from imported raw source fields and normalized source metadata.
  - Search URL JavaScript can read `source.bookSourceUrl`, `source.bookSourceName`, aliases, and raw custom fields.
  - Single-brace `{key}/{keyword}/{page}/{baseUrl}` placeholders and safe `{{(page - 1) * 10}}`-style page arithmetic are supported.
  - Source-variable search URL behavior is covered by unit tests.
- Audited `legado-for-mac-pub` as a reference:
  - See `docs/superpowers/specs/2026-06-21-legado-for-mac-reference-audit.md`.
  - Adopted source URL arithmetic/placeholder behavior.
  - Identified chapter cache/preload, richer bookmarks, scoped purify rules, and connector semantics as future clean-room implementation targets.
- Improved chapter cache/preload:
  - Online chapter content is cached by source URL, chapter URL, and active purify-rule signature.
  - Reader loading checks cache before network and saves successful chapter parses.
  - Reader preloads upcoming chapters in the background when a chapter opens; the count is configurable from reader settings, with 0 disabling preload.
  - Settings cache cleanup now clears real chapter cache instead of being a placeholder, and shows cached chapter count plus estimated size.
  - Cache persistence, expiry, and purify-signature invalidation are covered by unit tests.
  - If a live reload fails but an older cached copy exists for the same source/chapter, the reader falls back to cached content instead of dropping the user into a hard failure state.
  - The reader now shows a non-blocking banner when it is displaying a cached copy after live loading fails.
- Improved HTML/JSON connector semantics:
  - Added top-level operator splitting so `||` inside CSS attributes, JSON quoted keys, brackets, or parentheses is not treated as a fallback connector.
  - HTML value and list rules now support `%%` interleaving, matching the old Flutter rule evaluator behavior for mixed free/VIP chapter lists.
  - JSON rules now support `%%` sequential merge and stringify merged arrays as newline-separated values.
  - `java.getStringList` now reuses the enhanced HTML list selector path, so JS rules can use `||` fallback and `%%` interleaving for list extraction.
  - JSoup-style selections now support `.get(index)`, `.first()`, `.size()`, and `.isEmpty()` for common `java.getElements(...).get(i).text()` source rules.
  - Tests cover HTML fallback, HTML node/value merge, JSON quoted fallback, and JSON merge extraction.
- Improved XPath compatibility:
  - Added a Swift-native translator for common XPath subsets used by old Legado sources: `//tag`, `@XPath:` / `xpath:` prefixes, `text()`, terminal attributes such as `@href/@src/@content`, id/class/attribute predicates, `contains(@class, ...)`, and final-node indexes including `last()`.
  - HTML value/list extraction and `java.getStringList` now route these XPath forms through SwiftSoup-backed extraction.
  - Full arbitrary XPath remains out of scope for this layer and should be handled later by a dedicated evaluator if real fixtures require it.
- Improved reader daily-use behavior:
  - Reader advanced settings now include a persisted "keep screen awake while reading" toggle.
  - Opening the reader applies the idle-timer preference; leaving the reader restores the previous app idle-timer state.
- Improved reader position recovery:
  - Bookshelf state now persists the current paragraph index in addition to chapter index/title.
  - Reader restores the stored paragraph when reopening the same chapter.
  - Page/cover mode selection, auto-scroll, tap page navigation, and speech-driven paragraph movement update the stored paragraph position.
  - Scroll mode tracks the top visible paragraph with a Geometry preference and persists it when the visible paragraph changes.
  - Manual scroll progress writes are debounced and flushed when the reader closes, reducing persistence work during fast scrolling.
  - Long chapters use sampled paragraph geometry tracking and direct index iteration to reduce layout measurement and temporary allocation during fast scrolling.
  - Tap-zone page movement updates the visible paragraph state immediately and persists it through the same debounced path.
- Improved reader bookmarks:
  - Bookmarks now store an optional paragraph index and snippet from the current visible/page paragraph.
  - Same-chapter bookmarks jump directly to the bookmarked paragraph; cross-chapter jumps pre-save the target paragraph so the next chapter restores near the bookmark.
  - The bookmark sheet now sorts by chapter/paragraph, shows total/current-chapter counts, displays saved time, and highlights the current paragraph bookmark.
- Improved purify rule management:
  - Settings now provides built-in presets for common ads, site-tail text, and noise cleanup.
  - Preset import skips duplicates and remains editable after import.
  - Rules can be bulk-enabled or bulk-disabled to diagnose false positives without deleting user content.
  - A local preview field shows enabled-rule cleanup results before users risk applying broad rules to real chapters.
  - Content cleanup now uses a shared safe regex evaluator, so invalid user regexes are ignored instead of breaking chapter rendering.
- Improved source diagnostics:
  - Batch source checks now persist the latest per-source search health, keyword, result count, message, and test time.
  - Source Manager rows surface the last pass/warn/fail state so bad sources remain visible after leaving the batch-check sheet.

Still not complete:

- No macOS build has been run after this local milestone.
- No IPA should be produced until this milestone is pushed and CI passes.
- Reader page mode, cover mode, richer bookmarks UI, daily/weekly stats charts, purify diagnostics integration, and full App Store hardening remain open.
- Source compatibility still needs more JS helper APIs, WebView fallback verification, anti-crawl handling, persisted health history, and larger real-source fixture coverage.

## 9. Definition of done

The native Swift rewrite is done only when:

- Route parity is complete.
- Model parity is complete.
- Source import parity is complete.
- Legado engine compatibility is strong enough for realistic daily sources.
- Reader parity is complete.
- Local import works.
- Source diagnostics are usable.
- Settings/history/stats/purify/about are functional.
- CI and unsigned IPA pass.
- App Store readiness checklist passes.

Anything before that is an in-progress milestone, not the final product.
