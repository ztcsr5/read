# Flutter baseline audit for native Swift parity

Date: 2026-06-23

Flutter baseline: `D:\Gemini反重力\read`

Swift target: `D:\Gemini反重力\SourceReadSwift`

User requirement: the Flutter app is the product baseline for UI, interactions, reader behavior, settings, bookshelf, import flows, source management, diagnostics, RSS, and daily-use completeness. The only exception is book-source compatibility: the old Flutter source engine is an absorption target and acceptance-test source, but Swift must build a stronger native compatibility engine.

## 0. Audit status

This audit was performed before new Swift implementation work.

Checked local state:

- Flutter repo branch: `feat/source-engine-v1...ztcsr5/feat/source-engine-v1`
- Flutter dirty files: `nul`, `源阅_strings_analysis.txt`
- Flutter `lib`: 105 Dart files, about 177,780 words by graphify detection.
- Swift repo branch: `codex/native-swift-ci`
- Swift dirty file from earlier CI logs: `ci-log/run-27952116519/`

Graphify was installed and detection ran against `D:\Gemini反重力\read\lib`; it detected a code-only corpus. Its AST extraction failed on Windows multiprocessing/stdin for Dart files, so this document is based on direct code audit with `rg`, targeted file reads, route inventory, model inventory, and feature-by-feature inspection.

## 1. Non-negotiable product definition

The Swift rewrite is not acceptable merely because it compiles, produces an unsigned IPA, or has a smooth-looking prototype. It is acceptable only when:

1. Every user-facing Flutter route has a Swift equivalent or an explicitly documented replacement.
2. The visible page hierarchy matches the Flutter app: `主页` / `发现` / `设置`, iOS Podcasts-like large-title layout, same section order, same core affordances.
3. The reader is the actual product center: opening a book, reading, switching chapters, changing appearance/layout, bookmarks, TOC, source switching, TTS, auto-scroll, and progress restore must all work.
4. Local import works from picker, share/file handoff, TXT, and EPUB.
5. Source import works from paste, local JSON file, URL, wrapped JSON, source catalog, RSS, and `yuedu`/Legado style import links.
6. Source search, add-to-bookshelf, detail, TOC, chapter content, refresh catalog, download chapters, source switch, and diagnostics form a complete daily loop.
7. UI is responsive and native: no dead taps, no stuck pull-to-refresh, no keyboard trapping, no tab-switch jank, no fake 120 Hz claims.
8. App Store readiness is treated as a release standard: clear permissions, privacy manifest, stable error states, no debug placeholders, no broken controls.

## 2. Flutter architecture baseline

### 2.1 App shell

Evidence:

- `D:\Gemini反重力\read\lib\main.dart`
- `D:\Gemini反重力\read\lib\app\app.dart`
- `D:\Gemini反重力\read\lib\app\routes.dart`
- `D:\Gemini反重力\read\lib\features\home\views\home_page.dart`

Behavior:

- Uses `CupertinoApp.router`.
- Uses Riverpod.
- Initializes Isar before app launch.
- Restores `LegadoSessionStore`.
- Forces portrait orientation.
- Uses transparent status bar style.
- Root is a `StatefulShellRoute.indexedStack`.
- Main tabs are:
  - `/bookshelf` -> `主页`
  - `/explore` -> `发现`
  - `/settings` -> `设置`
- Bottom tab bar is a standard `CupertinoTabBar` with purple active tint `0xFF5856D6`.
- File URLs are intercepted in router redirect and passed to `pendingImportFilePathProvider`.

Swift parity requirement:

- Keep three-tab mental model exactly.
- Preserve independent tab state.
- Do not let custom tab overlays block taps or get lifted by keyboard.
- If using a custom SwiftUI tab bar for Podcasts-style polish, it must be tested for hit-testing, keyboard avoidance, safe area, 120 Hz scrolling, and route preservation.

### 2.2 Routes

Required route/function inventory from Flutter:

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

Swift gap:

- Current Swift has a subset of these screens.
- `source_verify`, `source_catalog`, `book_source`, `source_explore`, `source_diagnostic`, complete `webview_import`, full reader details, and full library/group flows are not at Flutter parity.

## 3. Design system baseline

Evidence:

- `D:\Gemini反重力\read\lib\app\theme\colors.dart`
- `D:\Gemini反重力\read\lib\app\theme\typography.dart`
- `D:\Gemini反重力\read\lib\app\theme\dimensions.dart`
- `D:\Gemini反重力\read\lib\app\theme\app_theme.dart`

Baseline:

- Product style is Cupertino-first, not generic Material.
- Primary purple: `0xFF5856D6`, dark purple `0xFF5E5CE6`.
- Light background: iOS system gray 6 `0xFFF2F2F7`.
- Secondary background: white.
- Dark secondary background: `0xFF1C1C1E`.
- Typography uses SF Pro Text / SF Pro Display:
  - Large title: 34, weight 700.
  - Title1: 28, weight 700.
  - Title2: 22, weight 700.
  - Headline: 17, weight 600.
  - Body: 17, weight 400.
  - Footnote: 13.
- Core spacing:
  - 4 / 8 / 16 / 24 / 32.
  - Radius 8 / 12 / 16 / 24.
  - Minimum touch target 44.
- Themes:
  - system
  - light
  - dark
  - eyeCare

Swift parity requirement:

- Do not use oversized custom typography that destroys Flutter proportions.
- Page titles, section headers, row heights, cards, and empty states must map to these values unless the Swift native control enforces slightly different dimensions.
- Eye-care mode must affect global surfaces and reader defaults, not just a settings checkmark.

## 4. Data and persistence baseline

Evidence:

- `D:\Gemini反重力\read\lib\data\models\book.dart`
- `D:\Gemini反重力\read\lib\data\models\chapter.dart`
- `D:\Gemini反重力\read\lib\data\models\bookmark.dart`
- `D:\Gemini反重力\read\lib\data\models\book_source.dart`
- `D:\Gemini反重力\read\lib\data\models\book_group.dart`
- `D:\Gemini反重力\read\lib\data\models\reading_progress.dart`
- `D:\Gemini反重力\read\lib\data\models\reading_stats.dart`
- `D:\Gemini反重力\read\lib\data\models\source_catalog.dart`
- `D:\Gemini反重力\read\lib\data\models\rss_source.dart`
- `D:\Gemini反重力\read\lib\data\repositories\book_repository.dart`
- `D:\Gemini反重力\read\lib\data\repositories\source_repository.dart`
- `D:\Gemini反重力\read\lib\data\repositories\stats_repository.dart`

Model surface that Swift must cover:

- `Book`
  - `title`
  - `author`
  - `coverPath`
  - `filePath`
  - `fileType`
  - `totalChapters`
  - `currentChapter`
  - `currentPosition`
  - `readingProgress`
  - `lastReadTime`
  - `dateAdded`
  - `tags`
  - `isFavorite`
  - `isFromSource`
  - `sourceUrl`
  - `fileSize`
  - `groupId`
- `Chapter`
  - book ID, title, index, content, URL, downloaded flag, word count.
- `Bookmark`
  - supports bookmark, highlight, and note.
  - stores color, note, selected text, chapter title, created/updated timestamps.
- `BookGroup`
  - group name/order and book assignment.
- `ReadingProgress`
  - durable chapter/position restore.
- `ReadingStats`
  - today duration, total duration, consecutive days.
- `BookSource`
  - modern and legacy Legado fields.
  - JSON rule fields for search/detail/TOC/content/explore.
  - custom config for headers, cookie, method, body, charset, login URL, JS libs, webview flags, single URL, source comments, cookie jar, response time, etc.
- `SourceCatalog`
  - imported source repositories.
- `RssSource` and `RssArticle`
  - feed lists and article reader.

Swift gap:

- Current Swift uses JSON persistence and has partial models.
- It does not yet represent the complete Flutter model surface and therefore cannot reproduce all flows.

## 5. Bookshelf and local library baseline

Evidence:

- `D:\Gemini反重力\read\lib\features\bookshelf\views\bookshelf_page.dart`
- `D:\Gemini反重力\read\lib\features\bookshelf\views\library_page.dart`
- `D:\Gemini反重力\read\lib\features\bookshelf\viewmodels\bookshelf_viewmodel.dart`
- `D:\Gemini反重力\read\lib\features\bookshelf\widgets\book_card.dart`
- `D:\Gemini反重力\read\lib\widgets\book_cover.dart`

Home baseline:

- `CupertinoPageScaffold`.
- `CustomScrollView`.
- `CupertinoSliverRefreshControl`.
- `CupertinoSliverNavigationBar` large title `主页`.
- Top trailing:
  - local file import button.
  - circular profile/action button.
- On appear:
  - `loadBooks()`.
  - `refreshOnlineBookUpdates()`.
- On app resume:
  - reload books.
  - refresh online updates.
- Sections in order:
  1. `正在阅读`
  2. `最新更新`
  3. `书架`

`正在阅读`:

- Horizontal list.
- Height about 260.
- Large hero cards about `screenWidth * 0.78`.
- Dark/podcast-like gradient or solid hero card.
- Cover around 72 x 96.
- Shows title, author, read percent.
- Bottom pill `继续阅读`.
- Delete action.
- Tap opens `/reader/:id`.
- Long press opens delete action sheet.

`最新更新`:

- Uses `book.totalChapters > (book.currentChapter + 1)`.
- Vertical row layout.
- Cover around 70 x 100.
- Title, author, update indicator/red dot.
- Tap opens reader.

`书架`:

- Header row with chevron.
- Tap navigates to `/library`.
- Must be a real navigation target, not a static label.

Profile action sheet:

- `阅读历史`
- `书源管理`
- `批量检测书源`
- `Web / JSON 写源`
- `设置`
- `关于`

Local import baseline:

- `FilePicker.platform.pickFiles`.
- Allowed extensions: `txt`, `epub`.
- `withData: true`.
- TXT parse through `TxtParser`.
- EPUB parse through `EpubParser`.
- External file handoff uses `pendingImportFilePathProvider`.
- Saves `Book` and `Chapter` list.

Library baseline:

- Page title `所有书籍`.
- Horizontal group chips.
- Create group.
- Group manager.
- Manage mode.
- Multi-select/delete.
- Move books between groups.
- 3-column grid.
- Long press book options.

Swift required fixes:

- Pull-to-refresh must never get stuck.
- `正在阅读`, `最新更新`, and `书架` headers/rows must be tappable where Flutter makes them tappable.
- Local import must work from document picker and share handoff.
- Library/group management must be implemented, not left as placeholders.

## 6. Reader baseline

Evidence:

- `D:\Gemini反重力\read\lib\features\reader\views\reader_page.dart`
- `D:\Gemini反重力\read\lib\features\reader\viewmodels\reader_viewmodel.dart`
- `D:\Gemini反重力\read\lib\features\reader\widgets\reader_settings_panel.dart`
- `D:\Gemini反重力\read\lib\features\reader\views\reader_toc_page.dart`
- `D:\Gemini反重力\read\lib\features\reader\views\reader_book_details_page.dart`
- `D:\Gemini反重力\read\lib\features\reader\views\reader_bookmarks_page.dart`
- `D:\Gemini反重力\read\lib\features\reader\widgets\source_selection_bottom_sheet.dart`
- `D:\Gemini反重力\read\lib\features\reader\services\tts_service.dart`

This is the largest missing parity area in Swift.

### 6.1 Immersive reader shell

Flutter behavior:

- Enters immersive sticky system UI on init.
- Restores edge-to-edge on dispose.
- Uses background derived from reader setting.
- Has animated top/bottom overlays.
- Overlay animation duration about 250 ms with ease-out cubic.
- Saves progress on scroll, app pause, and dispose.
- Detects text selection and avoids treating selection as tap.
- Horizontal drag velocity over about 650 can go back.
- Uses `_AppleBouncingScrollPhysics` with low drag threshold.
- Uses `RepaintBoundary` per reader item.
- Uses `SelectionArea` for text selection.

Swift required:

- Fullscreen reader must hide tab chrome and mini UI.
- Tap, selection, scroll, page mode, and back gestures must not fight.
- Touch response must be immediate.
- Reader scroll must be the first place to optimize for 120 Hz.

### 6.2 Reader content model

Flutter model:

- `ReaderItem`
  - `chapterIndex`
  - `chapter`
  - `paragraphIndex`
  - `charOffset`
  - `text`
  - `isTitle`
  - `isDivider`
- `ReaderNavigationTarget`
  - chapter index and optional char offset.
- `_flattenChapters` creates title item, paragraph items, divider.
- Online books lazily refresh chapter content if cached content is empty, too short, suspicious, or a URL.
- Purify rules are applied before display.
- Dense content is normalized and split.
- HTML entities are decoded.
- Duplicate chapter titles are removed from content.

Swift required:

- Reader must be item-based, not a raw text blob.
- Persist and restore by chapter + character offset.
- Content normalization must be ported.
- Suspicious cached content detection must be ported.

### 6.3 Reader modes

Flutter modes:

- `scroll`: vertical continuous scroll.
- `pageTurn`: horizontal page view.
- `cover`: horizontal page view with cover/translation/shadow effect.

Flutter page behavior:

- Builds page cache from state/screen/settings.
- Splits long paragraphs using measured text height.
- Footer displays progress.
- `allowImplicitScrolling: true`.
- Preloads next chapter around 80% in scroll mode.

Swift required:

- All three modes must actually change layout and gesture behavior.
- Settings changes must invalidate page cache immediately.
- The user's current complaint that appearance changes do nothing is a release blocker.

### 6.4 Tap zones

Flutter behavior:

- 3 x 3 tap zone grid.
- Default zones map to previous page, next page, menu, and disabled.
- User can edit each zone in settings.
- Actions:
  - previous page
  - next page
  - previous chapter
  - next chapter
  - menu
  - disabled

Swift required:

- Implement tap-zone editor and persist it.
- Tap center must show menu reliably.
- Tap on text selection must not accidentally turn page.

### 6.5 Reader settings

Flutter defaults:

- font size: 19
- line height: 1.72
- title spacing: 24
- paragraph spacing: 18
- top padding: 28
- bottom padding: 18
- paragraph indent: 2
- footer height: 26
- page padding: 24
- font weight index: -1/system
- background: system/default

Persisted keys:

- `reader.fontSize`
- `reader.lineHeight`
- `reader.letterSpacing`
- `reader.titleSpacing`
- `reader.paragraphSpacing`
- `reader.topPadding`
- `reader.bottomPadding`
- `reader.paragraphIndent`
- `reader.footerHeight`
- `reader.fontWeightIndex`
- `reader.pagePadding`
- `reader.isJustify`
- `reader.keepScreenOn`
- `reader.volumeKeyTurn`
- `reader.background`
- `reader.background.v2`
- `reader.customBackgroundColor`
- `reader.mode`
- `reader.tapZoneActions`
- `reader.customWallpaperPath`

Settings panel baseline:

- Bottom sheet height about 420.
- Rounded top radius about 20.
- Handle capsule.
- Segmented tabs:
  - `外观`
  - `排版`
  - `高级`
- `外观`:
  - font size slider.
  - background circles.
  - custom wallpaper picker.
- `排版`:
  - step rows for font size, letter spacing, title spacing, page padding, top/bottom padding, line height, paragraph spacing, indent, footer height.
  - font weight segmented: system / normal / medium / bold.
- `高级`:
  - page mode segmented.
  - tap zone 3 x 3 editor.
  - toggles: keep screen on, volume key turn, justify.

Swift required:

- Reader settings panel must be feature-complete.
- Each control must visually and functionally affect current page immediately.
- Persisted settings must survive app restart.

### 6.6 Reader top and bottom bars

Flutter top bar:

- Frosted blur panel.
- Back button.
- Center title and current chapter subtitle.
- Bookmark toggle.
- More sheet with:
  - `阅读设置`
  - `文本内容格式`
  - `换源`
  - `书籍详情`

Flutter bottom bar:

- Frosted blur panel.
- Chapter/page progress area.
- `上一章` and `下一章`.
- Page count within chapter.
- Tool buttons:
  - `目录`
  - `换源`
  - `朗读` / `停止`
  - `自动` / `暂停`
  - `设置`

Swift required:

- Same top/bottom tool surface.
- TTS and auto-scroll are not optional parity items.
- Source switch must be reachable from reader.

### 6.7 TOC, bookmarks, details, download

TOC page:

- Segmented title: `目录` / `书签`.
- Search by chapter name or index.
- Order toggle.
- Refresh catalog.
- Download options:
  - cache next 50 chapters.
  - download full book.
- Shows downloaded checkmark.

Book details:

- Cover and metadata.
- Continue reading.
- Full download.
- Intro expand/collapse.
- Catalog preview.
- Full TOC.
- Mark as read.
- Order toggle.
- Refresh catalog.
- Bookshelf toggle.
- On exit, asks whether to add non-favorite online book to bookshelf.

Swift required:

- Current Swift reader cannot be considered usable until this surface exists.

## 7. Discover/search baseline

Evidence:

- `D:\Gemini反重力\read\lib\features\explore\views\explore_page.dart`
- `D:\Gemini反重力\read\lib\features\explore\viewmodels\explore_viewmodel.dart`
- `D:\Gemini反重力\read\lib\features\explore\views\book_source_browser_page.dart`
- `D:\Gemini反重力\read\lib\features\explore\views\book_source_explore_page.dart`
- `D:\Gemini反重力\read\lib\features\explore\views\web_browser_page.dart`
- `D:\Gemini反重力\read\lib\features\explore\views\web_source_page.dart`

Discover UI:

- Title `发现`.
- Segmented tabs:
  - `找书`
  - `订阅`
  - `写源`
- `找书`:
  - search field placeholder `搜索书名或作者`.
  - smart web novel mode button.
  - purple source manager card.
  - fuzzy/precise segmented control.
  - search summary:
    - checked sources
    - matched sources
    - result count
  - result filter scope:
    - all
    - title
    - author
    - source
  - result filter search field.
  - cancel search.
  - verification prompt if needed.
- `订阅`:
  - RSS source list.
- `写源`:
  - Web source card.

Search engine:

- Searches enabled book sources sorted by weight/name.
- Batches of 8 concurrent sources.
- Uses cancel token.
- Result caps:
  - precise: 240.
  - fuzzy: 500.
- Ranking:
  - exact title: 1000.
  - title starts with query: 850.
  - fuzzy contains: 700.
  - author exact/contains adjustments.
- Dedupes by title, author, source URL, file path.
- Add-to-bookshelf:
  - saves basic book.
  - tries parse detail.
  - tries fetch chapter list.
  - failure to fetch catalog does not block adding; reader can retry.
- Search failures are compacted and sampled.
- Verification/login errors expose verification route.

Swift required:

- Search must be a robust pipeline, not a single-source demo.
- UI updates must be throttled without delaying taps.
- Results must be tappable and open book detail/reader.

## 8. Source management baseline

Evidence:

- `D:\Gemini反重力\read\lib\features\settings\views\source_management_page.dart`
- `D:\Gemini反重力\read\lib\features\settings\viewmodels\book_source_viewmodel.dart`
- `D:\Gemini反重力\read\lib\features\settings\views\source_test_page.dart`
- `D:\Gemini反重力\read\lib\features\settings\views\source_batch_check_page.dart`
- `D:\Gemini反重力\read\lib\features\settings\views\source_verification_page.dart`
- `D:\Gemini反重力\read\lib\features\settings\views\source_json_editor_page.dart`
- `D:\Gemini反重力\read\lib\features\settings\views\source_catalog_browser_page.dart`
- `D:\Gemini反重力\read\lib\features\settings\views\webview_import_page.dart`
- `D:\Gemini反重力\read\lib\features\settings\services\local_source_web_service.dart`

Source manager UI:

- Custom iOS navigation bar.
- Tabs:
  - `书源`
  - `仓库`
  - `RSS`
- Web local editor service card at top.
- Search field: `搜索名称、地址、分组`.
- Empty text differs by tab.
- Manage mode:
  - select all.
  - invert.
  - test selected.
  - enable selected.
  - disable selected.
  - delete selected.
- Book source row:
  - tap opens single-source search page.
  - actions:
    - explore/compass.
    - JSON editor.
    - diagnostic.
    - source test.
    - delete.
- Catalog row:
  - import/open preview.
- RSS row:
  - article list.

Import sheet:

- Paste JSON / HTTP address / share page / `yuedu` link.
- Choose local JSON file.
- Open built-in browser import.
- Auto-generate source from website.
- New blank JSON source.
- Auto-detect and import.

Import normalization:

- Accepts raw JSON object/array.
- Accepts URL.
- Normalizes GitHub `blob` to raw URL.
- Strips BOM.
- Extracts first JSON value from surrounding text.
- Supports wrappers:
  - `data`
  - `list`
  - `items`
  - `bookSources`
  - `sources`
  - `bookSource`
- Detects kind:
  - book source.
  - source catalog.
  - RSS.
- Imports from bytes, file path, and URL.
- Detects Cloudflare challenge page.

Local web editor service:

- Starts an `HttpServer` on local network.
- Uses access token.
- Shows multiple local URLs.
- Has local-network permission probe.
- Endpoints:
  - `GET /health`
  - `GET /`
  - `GET /index.html`
  - `GET /api/status`
  - `GET /api/sources`
  - `GET /api/sources/export`
  - `POST /api/sources`
  - `POST /api/sources/import`
  - `GET /api/sources/:id`
  - `PUT /api/sources/:id`
  - `DELETE /api/sources/:id`
  - `POST /api/sources/:id/test`
- CORS enabled.
- Web editor supports list/search/edit/test/import/export/delete.

Swift required:

- Source local-file import must work. Current user report says files are still gray/dead; this must be treated as a hard bug.
- Web editor must not disappear. It needs deterministic lifecycle state and visible URL/error.
- Batch actions and import modes must match Flutter before product testing.

## 9. Source testing and diagnostics baseline

Single-source test:

- Page title `书源测试`.
- Keyword default `斗破苍穹`.
- Buttons:
  - `开始测试`
  - `跳验证 / 保存站点 Cookie`
  - `抓取诊断 (收集详细日志)`
- Test chain:
  1. search URL
  2. search result
  3. book detail
  4. TOC
  5. content
- Distinguishes:
  - pass.
  - definite fail.
  - blocked / should retest.
  - needs login.
  - needs verify.
- Shows sample content.
- Expandable logs.
- Copy full report.

Batch source check:

- Starts automatically.
- Default keyword `斗破苍穹`.
- Max concurrency: 2.
- Timeout: 25 seconds.
- Filters:
  - all
  - success
  - failed
  - blocked
  - skipped
  - needs login
  - needs verify
- Displays progress, stats cards, failure-stage summary.
- Can copy report.
- Can one-click disable only definite failed sources.
- Must not disable blocked/login/verify sources.

Diagnostic center:

- Compatibility analyzer detects risky patterns, XPath ambiguity, JSONPath issues, webview/cookie/Cloudflare requirements.
- Rule suggest/rank engines inspect HTML to propose replacement selectors.
- Auto-repair service normalizes legacy aliases, selectors, XPath prefixes, URL rules, and rule maps.
- Health history is shown with trend chart.

Swift required:

- Current Swift one-key source check is not enough. It must classify like Flutter and generate actionable reports.
- Diagnostics are crucial for real source compatibility.

## 10. Legado/source compatibility capability baseline

Evidence:

- `D:\Gemini反重力\read\lib\data\parsers\legado_parser.dart`
- `D:\Gemini反重力\read\lib\data\parsers\legado\legado_js_engine.dart`
- `D:\Gemini反重力\read\lib\data\parsers\legado\legacy_js_evaluator.dart`
- `D:\Gemini反重力\read\lib\data\parsers\legado\legado_rule_evaluator.dart`
- `D:\Gemini反重力\read\lib\data\parsers\legado\legado_request_builder.dart`
- `D:\Gemini反重力\read\lib\data\parsers\legado\legado_session_store.dart`
- `D:\Gemini反重力\read\lib\data\parsers\legado\cloudflare_interceptor.dart`
- `D:\Gemini反重力\read\lib\data\parsers\legado_response_decoder.dart`

Absorb these capabilities into Swift acceptance tests:

- Request construction:
  - `{{key}}`, `{{keyword}}`, `{{page}}`.
  - source variables.
  - arithmetic page expressions.
  - POST body config.
  - headers/cookie/charset/method/body.
  - old rule URL conversion.
- Response decoding:
  - UTF-8.
  - GBK/GB2312/GB18030 fallback.
  - charset from header/meta.
  - binary/text handling.
- Rule systems:
  - CSS.
  - XPath-ish.
  - JSONPath-ish.
  - regex replacement.
  - `@put` / `@get`.
  - `@js` and `<js>`.
  - `||`, `&&`, `##`, negative/reverse/index semantics.
  - fallback extraction for malformed rules.
- JavaScript:
  - JavaScriptCore/QuickJS/native fallback concept.
  - `java.ajax`.
  - `java.put` / `java.get`.
  - Base64, MD5, AES, RSA, HMAC, gzip/deflate helpers.
  - DOM/jsoup bridge helpers.
  - cookie/user-agent bridge.
- Parser flows:
  - search books.
  - book detail.
  - chapter list.
  - chapter content.
  - explore books.
  - RSS articles.
  - RSS content.
- Runtime recovery:
  - frequency-control retry.
  - fallback keyword retry.
  - login detection.
  - Cloudflare/security verification detection.
  - suspicious fake success detection.
  - source-specific check keyword.

Swift principle:

- Do not blindly copy old parser internals.
- Build a Swift-native engine with this capability matrix and tests.
- Acceptance is measured by imported JSON success rate and source test reports, not by superficial search success on one easy source.

## 11. Local file parsing baseline

Evidence:

- `D:\Gemini反重力\read\lib\data\parsers\txt_parser.dart`
- `D:\Gemini反重力\read\lib\data\parsers\epub_parser.dart`

TXT:

- UTF-8 strict decode.
- GBK fallback via `fast_gbk`.
- Chapter regex supports Chinese `第...章/回/节` and `Chapter N`.
- If no chapter match, split by fixed chunks.

EPUB:

- Uses `epubx`.
- Recursively extracts nested chapters.
- Joins paragraph text.
- Extracts cover as base64 data URI when available.

Swift required:

- TXT/EPUB import must produce real `Book + Chapter` records and immediately open/read.
- Unsupported PDF should not be advertised until implemented, even though Flutter constants mention PDF.

## 12. Settings, history, stats, purify, RSS baseline

Evidence:

- `D:\Gemini反重力\read\lib\features\settings\views\settings_page.dart`
- `D:\Gemini反重力\read\lib\features\settings\views\purify_rules_page.dart`
- `D:\Gemini反重力\read\lib\features\settings\providers\purify_rules_provider.dart`
- `D:\Gemini反重力\read\lib\features\settings\views\reading_history_page.dart`
- `D:\Gemini反重力\read\lib\features\stats\views\stats_page.dart`
- `D:\Gemini反重力\read\lib\features\explore\views\rss_source_articles_page.dart`
- `D:\Gemini反重力\read\lib\features\explore\views\rss_article_reader_page.dart`

Settings baseline:

- Appearance section:
  - follow system.
  - light.
  - dark.
  - eye-care.
- Content settings:
  - source management.
  - purify rules.
- General:
  - clear cache.
  - reading history.
  - about.

Purify:

- Add manual rule.
- Import lines.
- URL subscription import.
- Refresh subscriptions.
- Enable/disable/delete.
- Preview.

History:

- Shows recent read books.
- Opens reader.

Stats:

- Today reading.
- Total reading time.
- Consecutive reading days.

RSS:

- List source articles.
- Open RSS article reader.
- Fetch content.

Swift required:

- These are not core-engine features, but they are product-completeness features.
- They can follow reader/source stabilization, but must be in the release checklist.

## 13. Current Swift gap matrix

Current Swift files inspected:

- `D:\Gemini反重力\SourceReadSwift\SourceReadSwift\App\RootTabView.swift`
- `D:\Gemini反重力\SourceReadSwift\SourceReadSwift\Features\Bookshelf\BookshelfView.swift`
- `D:\Gemini反重力\SourceReadSwift\SourceReadSwift\Features\Discover\DiscoverView.swift`
- `D:\Gemini反重力\SourceReadSwift\SourceReadSwift\Features\Reader\ReaderView.swift`
- `D:\Gemini反重力\SourceReadSwift\SourceReadSwift\Features\SourceManager\SourceManagerView.swift`
- `D:\Gemini反重力\SourceReadSwift\SourceReadSwift\Features\Settings\SettingsView.swift`
- `D:\Gemini反重力\SourceReadSwift\SourceReadSwift\Core\Engine\SourceEngine.swift`
- `D:\Gemini反重力\SourceReadSwift\SourceReadSwift\Core\Rules\*.swift`
- `D:\Gemini反重力\SourceReadSwift\SourceReadSwift\Core\Storage\*.swift`

Gaps by area:

| Area | Flutter baseline | Current Swift | Status |
| --- | --- | --- | --- |
| Root tabs | Cupertino tab shell, no dead taps | custom page/tab shell | needs hit-test/perf validation |
| Home | pull refresh, hero cards, latest updates, shelf navigation, profile sheet | partial | incomplete |
| Local import | TXT/EPUB picker + file handoff | implemented but user reports dead/gray files | broken |
| Library | groups, manage mode, grid | missing/partial | incomplete |
| Discover | 3 tabs, search filters, progress, cancel, RSS, write source | partial | incomplete |
| Source import | paste/file/URL/browser/catalog/RSS/yuedu | partial | incomplete/broken on device |
| Web editor | full local HTTP editor | partial NWListener/local view | not parity |
| Source test | 5-stage detailed report | partial | incomplete |
| Batch check | classified 7 states, report, disable only failed | partial | incomplete |
| Verification | WebView cookie save | missing/partial | incomplete |
| Diagnostic center | analyzer/suggest/rank/repair/history | missing | missing |
| Reader shell | immersive, overlays, gestures, selection | partial | unacceptable |
| Reader modes | scroll/page/cover | partial and user reports no effect | broken |
| Reader settings | full appearance/layout/advanced | partial | incomplete |
| TOC/bookmark/download | full | partial/missing | incomplete |
| Book details | full | partial/missing | incomplete |
| TTS/auto-scroll | yes | partial/missing | incomplete |
| Source switch | search alternatives and switch | partial/missing | incomplete |
| Purify | rules + URL subscription | partial | incomplete |
| RSS | sources/articles/reader | partial | incomplete |
| History/stats | present | partial/missing | incomplete |
| Source engine | huge capability surface | narrower Swift engine | needs compatibility sprint |

## 14. Implementation order after this audit

Do not keep patching random UI bugs. Use this order.

### Phase A - Interaction blockers and product shell

Goal: the app stops feeling dead or broken.

1. Fix local document import for book and source files on actual iOS:
   - use security-scoped resources correctly.
   - copy picked files into app container before parsing.
   - accept file extensions even when UTType is generic.
   - support `onOpenURL` and document types.
   - never open picker behind another modal.
2. Fix home taps:
   - reading cards open reader.
   - latest rows open reader.
   - shelf header opens library.
3. Fix pull-to-refresh:
   - no infinite/stuck state.
   - async task always completes on main actor.
4. Fix keyboard behavior:
   - bottom tab does not rise.
   - text fields can dismiss keyboard by tapping/dragging outside.
5. Fix tab switching:
   - no blocking overlays.
   - remove expensive synchronous work from tab body construction.

### Phase B - Reader parity rebuild

Goal: a book can be read daily.

1. Rebuild reader around `ReaderItem` model.
2. Implement scroll/pageTurn/cover with real layout changes.
3. Implement settings panel parity.
4. Implement top/bottom overlay parity.
5. Implement TOC/bookmarks/download.
6. Implement source switching.
7. Implement TTS and auto-scroll.
8. Implement content cleanup/purify/dense-line splitting.
9. Persist progress by chapter + char offset.

### Phase C - Source/import/search parity

Goal: user can import real JSON sources and find/read books.

1. Port import normalizer tests from Flutter.
2. Implement paste/file/URL/webview/catalog/RSS/yuedu import.
3. Implement source manager parity rows/actions.
4. Implement source verification WebView cookie save.
5. Implement single-source test parity.
6. Implement batch check parity.
7. Implement search scoring/dedupe/progress/cancel/filter.
8. Add source compatibility fixtures and test reports.

### Phase D - Bookshelf/library/settings/RSS/stats completion

Goal: product surface is complete.

1. Library groups/manage mode.
2. Reading history.
3. Reading stats.
4. Purify subscriptions.
5. RSS article flows.
6. About/privacy/App Store copy.

### Phase E - Performance and App Store hardening

Goal: release candidate.

1. Profile scroll and tab transitions.
2. Eliminate synchronous parsing/network on main thread.
3. Use lazy lists and stable identifiers.
4. Add haptics only where useful.
5. Accessibility pass.
6. Dark/light/eye-care pass.
7. Privacy manifest/permissions review.
8. GitHub Actions unsigned IPA only after meaningful milestones.

## 15. Acceptance tests before calling it a product

Minimum manual test set:

1. Fresh install opens home without jank.
2. Pull refresh completes.
3. Import TXT from Files.
4. Import EPUB from Files.
5. Import JSON source from local file.
6. Import JSON source from paste.
7. Import JSON source from URL.
8. Import source catalog and import selected source.
9. Search `斗破苍穹` across enabled sources.
10. Add a result to bookshelf.
11. Open reader and read first chapter.
12. Change font size, line height, background, page mode; verify instant effect.
13. Open TOC and jump chapter.
14. Add/remove bookmark.
15. Refresh catalog.
16. Cache next 50 chapters.
17. Switch source.
18. Run single-source test.
19. Run batch check.
20. Open verification WebView and save cookie.
21. Import purify URL.
22. View reading history.
23. Use settings theme switch.
24. Tab switch repeatedly while search field/keyboard is active.
25. Scroll reader and bookshelf on ProMotion device; no visible hitching.

## 16. Immediate next action

Start with Phase A and B, not random cosmetic patches.

The first implementation batch should touch only:

- `D:\Gemini反重力\SourceReadSwift\SourceReadSwift\Shared\Import\UniversalDocumentPicker.swift`
- `D:\Gemini反重力\SourceReadSwift\SourceReadSwift\App\RootTabView.swift`
- `D:\Gemini反重力\SourceReadSwift\SourceReadSwift\Features\Bookshelf\BookshelfView.swift`
- `D:\Gemini反重力\SourceReadSwift\SourceReadSwift\Features\Reader\ReaderView.swift`
- `D:\Gemini反重力\SourceReadSwift\SourceReadSwift\Features\Reader\ReaderSettingsModels.swift`
- supporting storage/model files only if required for reader progress and local import correctness.

Do not push or run Actions for every small patch. Build locally where possible, then use Actions after a coherent milestone.
