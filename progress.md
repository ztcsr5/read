## 2026-06-26 - Task: Research mr for Flutter absorption

### What was done
- Downloaded `DandanLLab/mr` into `D:\Gemini反重力\references\mr` as a local read-only reference because `git clone` was blocked by the local Git proxy.
- Compared `mr` against the existing Flutter `read` project across source import, Legado rule parsing, JS bridge, source debugging, and reader modules.
- Produced a formal absorption report that keeps `read` UI/product structure as the baseline and treats `mr` as a module-level reference implementation.

### Testing
- Ran local source scans with `rg` and PowerShell against both `D:\Gemini反重力\references\mr` and `D:\Gemini反重力\read`.
- Verified `mr` license is MIT and recorded the licensing requirement in the report.
- No application source code was changed and no Flutter build/test was run in this research-only task.

### Notes
- Changed files:
  - `docs/2026-06-26-mr-flutter-absorption-report.md`: documented the `mr` absorption conclusion, module priorities, phased plan, and risks.
  - `progress.md`: recorded this research/documentation task.
- External reference:
  - `D:\Gemini反重力\references\mr`: local copy of `DandanLLab/mr` for comparison; not part of the `read` repository.
- Rollback: delete `docs/2026-06-26-mr-flutter-absorption-report.md` and this `progress.md` entry/file; optionally remove `D:\Gemini反重力\references\mr` if the local reference is no longer needed.
## 2026-06-26 - Task: Absorb mr source import compatibility

### What was done
- Extended the Flutter source import path to support `sourceUrls` repository documents, including recursive imports, URL-string entries, duplicate source replacement by `bookSourceUrl`, and loop prevention.
- Added support for the `#requestWithoutUA` suffix used by some source repositories, so remote imports can intentionally omit the default mobile Safari User-Agent.
- Added an initial JS/function-style source import path for lightweight sources with `search`, `explore`, `bookInfo`, `toc`, `content`, `nextTocUrl`, and `nextContentUrl` functions. Imported JS sources are stored as normal `BookSource` records with `engine: quickjs`, `sourceFormat: js`, and the original JS kept in `jsLib`/`customConfig`.
- Kept the existing Flutter UI/product structure untouched; this change only strengthens import compatibility and test coverage.

### Testing
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat pub get` successfully after an initial short timeout.
- Ran `D:\Gemini反重力\flutter\bin\dart.bat format lib\features\settings\viewmodels\book_source_viewmodel.dart lib\data\models\book_source.dart test\source_import_test.dart`.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\source_import_test.dart`: 14 tests passed.
- Ran `D:\Gemini反重力\flutter\bin\dart.bat analyze lib\features\settings\viewmodels\book_source_viewmodel.dart lib\data\models\book_source.dart test\source_import_test.dart`: no issues found.
- `flutter analyze` for the whole project crashed inside Flutter analysis server/LSP parsing and wrote `flutter_24.log`; the targeted `dart analyze` above passed for all changed files.

### Notes
- Changed files:
  - `lib/data/models/book_source.dart`: preserves `engine` and `sourceFormat` in `customConfig`.
  - `lib/features/settings/viewmodels/book_source_viewmodel.dart`: adds injectable remote fetcher, recursive `sourceUrls` handling, `#requestWithoutUA`, and JS source import conversion.
  - `test/source_import_test.dart`: stabilizes the test fixture text and adds coverage for recursive repositories, no-UA imports, and JS function source import.
- Existing untracked analysis artifacts (`graphify-out`, `.graphify_*`, `nul`, and `源阅_strings_analysis.txt`) were not touched.
- Rollback: revert the three changed files listed above and remove this `progress.md` entry.

## 2026-06-26 - Task: Execute JS function search book lists

### What was done
- Added a JS-only `bookList` execution path in `LegadoParser` for function-style sources imported as rules like `<js>search(key, page, result)</js>`.
- The JS output is decoded as a list, common wrapper objects (`list`, `books`, `bookList`, `items`, `records`, `rows`, `result`, `results`, `data`) are supported, and each map is converted through the existing JSON-to-`Book` parser.
- The same safe JS list path is available to explore parsing with an empty keyword, while normal CSS/JSON/regex rules continue through the old paths.
- Added a targeted parser test for imported JS function search results. On the current Windows machine the test compiles and passes but the assertions are skipped because the QuickJS bridge DLL is unavailable; environments with JS runtime available will execute the full assertions.

### Testing
- Ran `D:\Gemini反重力\flutter\bin\dart.bat format lib\data\parsers\legado_parser.dart test\legado_engine_test.dart`.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "parses imported js function search results"`: passed; current machine logs missing `quickjs_c_bridge_plugin.dll`, so the JS runtime-gated assertions are skipped.
- Ran `D:\Gemini反重力\flutter\bin\dart.bat analyze lib\data\parsers\legado_parser.dart`: no errors; existing info-level lints remain.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\source_import_test.dart test\compatibility_analyzer_test.dart test\source_check_classifier_test.dart`: 21 tests passed.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "keeps response data when leading js block only defines rule vars"`: passed.

### Notes
- Changed files:
  - `lib/data/parsers/legado_parser.dart`: JS-only list execution and decoding path for search/explore book lists.
  - `test/legado_engine_test.dart`: targeted JS function search parser coverage.
- Rollback: revert the two changed files listed above and remove this `progress.md` entry.

## 2026-06-26 - Task: Support java.connect direct body response aliases

### What was done
- Improved the ajax-backed `java.connect(url)` bridge for function-style JS sources.
- `java.connect(url).body()` now returns the same string-like body object as `java.connect(url).get().body()`, so both forms work:
  - `JSON.parse(java.connect(url).body())`
  - `java.connect(url).body().string()`
  - `java.connect(url).body().text()`
- Existing `get()`, `post()`, and `execute()` response behavior is preserved.

### Testing
- Ran `D:\Gemini反重力\flutter\bin\dart.bat format lib\data\parsers\legado\legado_js_engine.dart test\legado_engine_test.dart`.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "resolves java.connect direct body string alias"`: passed; current Windows machine still logs missing `quickjs_c_bridge_plugin.dll`, so runtime-gated assertions are skipped locally.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "resolves java.connect get body through ajax callback"`: passed.
- Ran `D:\Gemini反重力\flutter\bin\dart.bat analyze lib\data\parsers\legado\legado_js_engine.dart test\legado_engine_test.dart`: no compile errors; existing warning/info lints remain.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\source_import_test.dart test\compatibility_analyzer_test.dart test\source_check_classifier_test.dart test\diagnostic_report_test.dart`: 27 tests passed.

### Notes
- Changed files:
  - `lib/data/parsers/legado/legado_js_engine.dart`: direct `java.connect().body()` response alias.
  - `test/legado_engine_test.dart`: targeted connect body alias coverage.
- Rollback: revert the two changed files listed above and remove this `progress.md` entry.

## 2026-06-26 - Task: Support JS TOC chapter field aliases

### What was done
- Improved imported/function-style JS TOC parsing for chapter objects using modern or light-reader-style field names.
- JS `toc(result)` chapter title detection now recognizes:
  - `chapterTitle`, `chapter_title`, `text`, `label`, `ChapterTitle`
- JS `toc(result)` chapter URL detection now recognizes:
  - `href`, `path`, `contentUrl`, `content_url`, `readUrl`, `read_url`, `chapter_url`
- This lets rules with only `chapterList: <js>toc(result)</js>` parse returned objects like `{chapterTitle:"...", href:"..."}` without needing explicit Legado field mappings.

### Testing
- Ran `D:\Gemini反重力\flutter\bin\dart.bat format lib\data\parsers\legado_parser.dart test\legado_engine_test.dart`.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "parses imported js function toc field aliases"`: passed; current Windows machine still logs missing `quickjs_c_bridge_plugin.dll`, so runtime-gated assertions are skipped locally.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "parses imported js function toc container results"`: passed.
- Ran `D:\Gemini反重力\flutter\bin\dart.bat analyze lib\data\parsers\legado_parser.dart test\legado_engine_test.dart`: no compile errors; existing info-level lints remain.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\source_import_test.dart test\compatibility_analyzer_test.dart test\source_check_classifier_test.dart test\diagnostic_report_test.dart`: 27 tests passed.

### Notes
- Changed files:
  - `lib/data/parsers/legado_parser.dart`: JS TOC chapter title/url aliases.
  - `test/legado_engine_test.dart`: targeted TOC field alias coverage.
- Rollback: revert the two changed files listed above and remove this `progress.md` entry.

## 2026-06-26 - Task: Support JS bookInfo TOC URL aliases

### What was done
- Improved `ruleBookInfo` / imported JS `bookInfo(result)` compatibility for detail pages that return directory entry fields under non-Legado names.
- Book info URL extraction now recognizes additional TOC/catalog aliases:
  - `chapterUrl`, `chapterListUrl`, `chaptersUrl`
  - `listUrl`, `menuUrl`, `readUrl`
- The aliases apply to both normal JSON parsing and async/ajax-resolved JSON fields.
- This targets function-style sources where `bookInfo()` returns objects such as `{chapterListUrl: "/book/1/catalog"}` rather than `{tocUrl: "..."}`.

### Testing
- Ran `D:\Gemini反重力\flutter\bin\dart.bat format lib\data\parsers\legado_parser.dart test\legado_engine_test.dart`.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "uses imported js bookInfo chapter list url aliases"`: passed; current Windows machine still logs missing `quickjs_c_bridge_plugin.dll`, so runtime-gated assertions are skipped locally.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "keeps original book url when book info has no tocUrl rule"`: passed.
- Ran `D:\Gemini反重力\flutter\bin\dart.bat analyze lib\data\parsers\legado_parser.dart test\legado_engine_test.dart`: no compile errors; existing info-level lints remain.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\source_import_test.dart test\compatibility_analyzer_test.dart test\source_check_classifier_test.dart test\diagnostic_report_test.dart`: 27 tests passed.

### Notes
- Changed files:
  - `lib/data/parsers/legado_parser.dart`: bookInfo TOC/catalog alias extraction.
  - `test/legado_engine_test.dart`: JS bookInfo alias coverage.
- Rollback: revert the two changed files listed above and remove this `progress.md` entry.

## 2026-06-26 - Task: Map JS search field aliases into Book metadata

### What was done
- Improved JSON/JS search result field alias handling for function-style sources.
- Search/book JSON parsing now maps common modern source fields:
  - title/name aliases were already supported.
  - URL aliases such as `url` remain supported.
  - cover aliases such as `img` remain supported.
  - category/tag aliases now populate `Book.tags` through `_splitBookTags`.
  - latest chapter aliases now include `latest`, `latestChapterName`, `update`, `updateChapter`, and `newest`.
- This helps light-reader style JS sources that return objects like `{title,url,img,category,latest}` instead of Legado's `{name,bookUrl,coverUrl,kind,lastChapter}`.

### Testing
- Ran `D:\Gemini反重力\flutter\bin\dart.bat format lib\data\parsers\legado_parser.dart test\legado_engine_test.dart`.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "parses imported js function search field aliases"`: passed; current Windows machine still logs missing `quickjs_c_bridge_plugin.dll`, so runtime-gated assertions are skipped locally.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "parses imported js function search results"`: passed.
- Ran `D:\Gemini反重力\flutter\bin\dart.bat analyze lib\data\parsers\legado_parser.dart test\legado_engine_test.dart`: no compile errors; existing info-level lints remain.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\source_import_test.dart test\compatibility_analyzer_test.dart test\source_check_classifier_test.dart test\diagnostic_report_test.dart`: 27 tests passed.

### Notes
- Changed files:
  - `lib/data/parsers/legado_parser.dart`: search result metadata aliases.
  - `test/legado_engine_test.dart`: function-style search alias coverage.
- Rollback: revert the two changed files listed above and remove this `progress.md` entry.

## 2026-06-26 - Task: Decode JS function TOC/content container outputs

### What was done
- Improved function-style source execution for JS `toc(result)` outputs that return container objects instead of a raw array.
- Added JS chapter list decoding for common containers:
  - `list`, `chapters`, `chapterList`, `toc`, `items`, `rows`, `result`, `results`, `data`
  - one-level nested containers such as `{data:{chapters:[...]}}`
- Improved JS `content(result)` normalization for nested content containers:
  - `{data:{paragraphs:[...]}}`
  - `{chapter:{content:"..."}}`
  - nested `content/text/body/html/paragraphs/lines/data/result/chapter`
- This targets light-reader / modern function-style sources that do not always return a bare list/string.

### Testing
- Ran `D:\Gemini反重力\flutter\bin\dart.bat format lib\data\parsers\legado_parser.dart test\legado_engine_test.dart`.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "parses imported js function toc container results"`: passed; current Windows machine still logs missing `quickjs_c_bridge_plugin.dll`, so runtime-gated assertions are skipped locally.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "parses imported js function nested content results"`: passed; same QuickJS DLL limitation applies.
- Ran existing JS function regression tests:
  - `parses imported js function toc results`: passed.
  - `parses imported js function content results`: passed.
- Ran `D:\Gemini反重力\flutter\bin\dart.bat analyze lib\data\parsers\legado_parser.dart test\legado_engine_test.dart`: no compile errors; existing info-level lints remain.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\source_import_test.dart test\compatibility_analyzer_test.dart test\source_check_classifier_test.dart test\diagnostic_report_test.dart`: 27 tests passed.

### Notes
- Changed files:
  - `lib/data/parsers/legado_parser.dart`: JS TOC/content container output decoding.
  - `test/legado_engine_test.dart`: targeted TOC/content container coverage.
- Rollback: revert the two changed files listed above and remove this `progress.md` entry.

## 2026-06-26 - Task: Classify fetch/request JS sources as runtime dependent

### What was done
- Updated source compatibility diagnostics so JS rules using browser-style `fetch(...)`, `request(...)`, or `java.fetch(...)` are treated as HTTP bridge/runtime dependencies.
- Updated source check failure classification so fetch/request-based function sources are not misclassified as ordinary CSS/JSON rule failures when search/detail/toc/content returns empty.
- Added English/common fail-step aliases (`search`, `result`, `toc`, `chapter`, `content`) to the runtime-dependent blocked classification path. This keeps diagnostic behavior correct when UI logs or tests use English step names.

### Testing
- Ran `D:\Gemini反重力\flutter\bin\dart.bat format lib\features\source_diagnostic\services\compatibility_analyzer.dart lib\features\settings\services\source_check_classifier.dart test\compatibility_analyzer_test.dart test\source_check_classifier_test.dart`.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\compatibility_analyzer_test.dart --plain-name "detects fetch and request bridge dependencies"`: passed.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\source_check_classifier_test.dart --plain-name "blocks fetch and request function sources as runtime dependent"`: passed.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\compatibility_analyzer_test.dart test\source_check_classifier_test.dart test\diagnostic_report_test.dart`: 12 tests passed.
- Ran `D:\Gemini反重力\flutter\bin\dart.bat analyze lib\features\source_diagnostic\services\compatibility_analyzer.dart lib\features\settings\services\source_check_classifier.dart test\compatibility_analyzer_test.dart test\source_check_classifier_test.dart`: no issues found.

### Notes
- Changed files:
  - `lib/features/source_diagnostic/services/compatibility_analyzer.dart`: fetch/request bridge detection.
  - `lib/features/settings/services/source_check_classifier.dart`: runtime-dependent classification for fetch/request and English step aliases.
  - `test/compatibility_analyzer_test.dart`: diagnostic coverage.
  - `test/source_check_classifier_test.dart`: classification coverage.
- Rollback: revert the four changed files listed above and remove this `progress.md` entry.

## 2026-06-26 - Task: Import modern JS function-style sources

### What was done
- Extended JS source import detection beyond classic `function name(...)` declarations.
- Function-style source import now recognizes:
  - `async function search(...)`
  - `const explore = (...) => ...`
  - `let bookInfo = function(...) { ... }`
  - `const toc = async (...) => ...`
  - `var content = function(...) { ... }`
- This keeps the existing conversion target unchanged: imported JS functions are still stored as `jsLib` plus Legado-compatible `<js>functionName(...)</js>` rules.
- Scope stayed import-only; no UI changes and no parser architecture rewrite.

### Testing
- Ran `D:\Gemini反重力\flutter\bin\dart.bat format lib\features\settings\viewmodels\book_source_viewmodel.dart test\source_import_test.dart`.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\source_import_test.dart --plain-name "imports modern js function source declarations"`: passed.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\source_import_test.dart`: 15 tests passed.
- Ran `D:\Gemini反重力\flutter\bin\dart.bat analyze lib\features\settings\viewmodels\book_source_viewmodel.dart test\source_import_test.dart`: no issues found.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\compatibility_analyzer_test.dart test\source_check_classifier_test.dart test\diagnostic_report_test.dart`: 10 tests passed.

### Notes
- Changed files:
  - `lib/features/settings/viewmodels/book_source_viewmodel.dart`: modern JS function declaration detection.
  - `test/source_import_test.dart`: import coverage for async/function/arrow declarations.
- Rollback: revert the two changed files listed above and remove this `progress.md` entry.

## 2026-06-26 - Task: Add JS source/book/chapter context aliases

### What was done
- Extended JS runtime context compatibility for Legado / iOS-compatible / function-style sources.
- Added source aliases and helpers:
  - `source.sourceUrl`, `source.sourceName`
  - `source.getName()`, `source.getUrl()`, `source.getSourceUrl()`
  - `source.putVariable()` as an alias of `source.setVariable()`
- Added book aliases and helpers:
  - normalized `book.name/title`, `book.bookUrl/url/filePath`, `book.tocUrl`
  - `book.getName()`, `book.getTitle()`, `book.getAuthor()`, `book.getBookUrl()`, `book.getUrl()`, `book.getTocUrl()`, `book.getOrigin()`
  - `book.putVariable()` as an alias of `book.setVariable()`
- Added chapter aliases and helpers:
  - `chapter.chapterUrl`, `chapter.chapterIndex`, `chapter.isVolume`
  - `chapter.getName()`, `chapter.getTitle()`, `chapter.getUrl()`, `chapter.getChapterUrl()`, `chapter.getIndex()`, `chapter.getChapterIndex()`
- Updated parser-side JS variable maps so generated `source`, `book`, and `chapter` objects expose the same common field names before JS methods are injected.

### Testing
- Ran `D:\Gemini反重力\flutter\bin\dart.bat format lib\data\parsers\legado\legado_js_engine.dart lib\data\parsers\legado_parser.dart test\legado_engine_test.dart`.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "injects source book and chapter convenience aliases"`: passed; current Windows machine still logs missing `quickjs_c_bridge_plugin.dll`, so runtime-gated assertions are skipped locally.
- Ran parser context regression tests:
  - `uses book and chapter context variables for content rules`: passed.
  - `uses book context variables for detail toc url templates`: passed.
- Ran `D:\Gemini反重力\flutter\bin\dart.bat analyze lib\data\parsers\legado\legado_js_engine.dart lib\data\parsers\legado_parser.dart test\legado_engine_test.dart`: no compile errors; existing warning/info lints remain and cause a non-zero analyzer exit.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\source_import_test.dart test\compatibility_analyzer_test.dart test\source_check_classifier_test.dart test\diagnostic_report_test.dart`: 24 tests passed.

### Notes
- Changed files:
  - `lib/data/parsers/legado/legado_js_engine.dart`: runtime source/book/chapter helper aliases.
  - `lib/data/parsers/legado_parser.dart`: parser-side context field aliases.
  - `test/legado_engine_test.dart`: targeted context alias coverage.
- Rollback: revert the three changed files listed above and remove this `progress.md` entry.

## 2026-06-26 - Task: Add fetch/request JS bridge aliases

### What was done
- Extended the ajax-backed JS runtime bridge for modern function-style sources inspired by mr / light-reader style rules.
- Added `java.get(url, headers)`, `java.post(url, body, headers)`, and `java.fetch(url, options)` in the `evaluateWithAjax` trap.
- Added global `fetch(url, options)` and `request(url, options)` aliases so JS/HTML function sources can use browser-like request code without rewriting everything to `java.ajax`.
- The returned response is a string-like object, so both forms work:
  - `fetch(url).match(...)`
  - `fetch(url).body().string()`
  - `fetch(url).json()`

### Testing
- Ran `D:\Gemini反重力\flutter\bin\dart.bat format lib\data\parsers\legado\legado_js_engine.dart test\legado_engine_test.dart`.
- Ran targeted JS bridge tests:
  - `resolves global fetch through ajax callback`: passed.
  - `resolves request post options through ajax callback`: passed.
  - `resolves java fetch response aliases through ajax callback`: passed.
  - `resolves java.connect get body through ajax callback`: passed.
  - `resolves java.connect post body through ajax callback`: passed.
- Current Windows machine still logs missing `quickjs_c_bridge_plugin.dll`, so runtime-gated assertions are skipped locally.
- Ran `D:\Gemini反重力\flutter\bin\dart.bat analyze lib\data\parsers\legado\legado_js_engine.dart test\legado_engine_test.dart`: no compile errors; existing warning/info lints remain and cause a non-zero analyzer exit.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\source_import_test.dart test\compatibility_analyzer_test.dart test\source_check_classifier_test.dart test\diagnostic_report_test.dart`: 24 tests passed.

### Notes
- Changed files:
  - `lib/data/parsers/legado/legado_js_engine.dart`: ajax-backed HTTP bridge aliases and string-like response object.
  - `test/legado_engine_test.dart`: targeted coverage for global fetch/request/java.fetch aliases.
- Rollback: revert the two changed files listed above and remove this `progress.md` entry.

## 2026-06-26 - Task: Improve JS connect ajax bridge

### What was done
- Extended the Legado JS bridge for function-style sources that call `java.connect(url)` as a request builder.
- Added response-object compatibility for common JS source patterns:
  - `java.connect(url).get().body()`
  - `java.connect(url).post(body).body()`
  - `java.connect(url).execute().body()`
  - response aliases: `body()`, `bodyString()`, `text()`, `html()`, `string()`, `parse()`, and `toString()`.
- Preserved the existing direct `java.connect(url).body()` path so older rules continue to work.

### Testing
- Ran `D:\Gemini反重力\flutter\bin\dart.bat format lib\data\parsers\legado\legado_js_engine.dart test\legado_engine_test.dart`.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "resolves java.connect get body through ajax callback"`: passed; current Windows machine still logs missing `quickjs_c_bridge_plugin.dll`, so runtime-gated assertions are skipped.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "resolves java.connect post body through ajax callback"`: passed; same QuickJS DLL limitation applies.
- Ran `D:\Gemini反重力\flutter\bin\dart.bat analyze lib\data\parsers\legado\legado_js_engine.dart test\legado_engine_test.dart`: no compile errors; existing warning/info lints remain and cause a non-zero analyzer exit.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\source_import_test.dart test\compatibility_analyzer_test.dart test\source_check_classifier_test.dart test\diagnostic_report_test.dart`: 24 tests passed.

### Notes
- Changed files:
  - `lib/data/parsers/legado/legado_js_engine.dart`: `java.connect` request/response bridge.
  - `test/legado_engine_test.dart`: targeted get/post callback coverage.
- Rollback: revert the two changed files listed above and remove this `progress.md` entry.

## 2026-06-26 - Task: Export batch compatibility recommendations

### What was done
- Extended `SourceCompatibilityBatchReport` with JSON export so batch scan results can be saved to logs, files, or a future UI page.
- Added `recommendedFocus()` to translate dependency counts into practical next repair directions, such as:
  - expand JS runtime/function compatibility,
  - verify `java.ajax/connect/fetch/request` bridges,
  - separate WebView/Cookie/login requirements from real parser failures,
  - validate non-UTF8 decoding and Jsoup helper coverage.
- Added per-source JSON output with format, dependencies, issue count, and issue details.

### Testing
- Ran `D:\Gemini反重力\flutter\bin\dart.bat format lib\features\source_diagnostic\services\source_compatibility_batch_analyzer.dart test\compatibility_analyzer_test.dart`.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\compatibility_analyzer_test.dart`: 5 tests passed.
- Ran `D:\Gemini反重力\flutter\bin\dart.bat analyze lib\features\source_diagnostic\services\source_compatibility_batch_analyzer.dart test\compatibility_analyzer_test.dart`: no issues found.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\source_import_test.dart test\compatibility_analyzer_test.dart test\source_check_classifier_test.dart test\diagnostic_report_test.dart`: 29 tests passed.

### Notes
- Changed files:
  - `lib/features/source_diagnostic/services/source_compatibility_batch_analyzer.dart`: JSON export and recommendations.
  - `test/compatibility_analyzer_test.dart`: export/recommendation assertions.
- Rollback: revert the two changed files listed above and remove this `progress.md` entry.

## 2026-06-26 - Task: Add batch compatibility analyzer

### What was done
- Extended `CompatibilityAnalyzer` to scan `ruleExplore`, so JS/WebView/header/login risks in discover/explore rules are no longer missed.
- Added `SourceCompatibilityBatchAnalyzer`, a pure Dart batch summarizer for imported source sets.
- The batch report now provides:
  - total source count,
  - risky source count and ratio,
  - source format distribution (`js-function`, `legado-json`, `legado-mixed`, `unknown`),
  - dependency distribution (`javascript`, `http-js-bridge`, `webview`, `login`, `headers-cookie`, `non-utf8`, `jsoup`, `xpath`),
  - issue stage counts,
  - top issue reasons,
  - per-source items with detected format, dependencies, and diagnostic issues.
- This creates a reproducible way to import a real source pack later and immediately identify the next API/compatibility gaps to implement.

### Testing
- Ran `D:\Gemini反重力\flutter\bin\dart.bat format lib\features\source_diagnostic\services\compatibility_analyzer.dart lib\features\source_diagnostic\services\source_compatibility_batch_analyzer.dart test\compatibility_analyzer_test.dart`.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\compatibility_analyzer_test.dart`: 5 tests passed.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\source_import_test.dart test\compatibility_analyzer_test.dart test\source_check_classifier_test.dart test\diagnostic_report_test.dart`: 29 tests passed.
- Ran `D:\Gemini反重力\flutter\bin\dart.bat analyze lib\features\source_diagnostic\services\compatibility_analyzer.dart lib\features\source_diagnostic\services\source_compatibility_batch_analyzer.dart test\compatibility_analyzer_test.dart`: no issues found.

### Notes
- Changed files:
  - `lib/features/source_diagnostic/services/compatibility_analyzer.dart`: includes `ruleExplore`.
  - `lib/features/source_diagnostic/services/source_compatibility_batch_analyzer.dart`: new batch analyzer.
  - `test/compatibility_analyzer_test.dart`: explore scan and batch summary coverage.
- Rollback: revert the three changed files listed above and remove this `progress.md` entry.

## 2026-06-26 - Task: Cover JS function explore parsing

### What was done
- Added targeted coverage for `ruleExplore.bookList = <js>explore(baseUrl, result)</js>`.
- The test verifies that function-style explore results can return nested containers such as `{data:{items:[...]}}`.
- The test also covers modern field aliases from MR/轻悦-style scripts:
  - `title`
  - `writer`
  - `url`
  - `img`
  - `category`
- No production parser change was required because explore already reuses the JS book-list parser; this checkpoint locks that behavior against future regressions.

### Testing
- Ran `D:\Gemini反重力\flutter\bin\dart.bat format test\legado_engine_test.dart`.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "parses imported js function explore results"`: passed. Current Windows machine still logs missing `quickjs_c_bridge_plugin.dll`; Legacy first rejects the unknown `explore` call, then Node fallback passes.
- Re-ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "supports java ajaxAll head and getStrResponse helpers"`: passed.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\source_import_test.dart test\compatibility_analyzer_test.dart test\source_check_classifier_test.dart test\diagnostic_report_test.dart`: 27 tests passed.
- Ran `D:\Gemini反重力\flutter\bin\dart.bat analyze lib\data\parsers\legado\legado_js_engine.dart test\legado_engine_test.dart`: no compile errors; existing warning/info lints remain and cause a non-zero analyzer exit.

### Notes
- Changed files:
  - `test/legado_engine_test.dart`: targeted JS explore coverage.
- Rollback: revert the changed test file and remove this `progress.md` entry.

## 2026-06-26 - Task: Add ajaxAll/head/getStrResponse JS helpers

### What was done
- Added MR/Legado-compatible HTTP helper shims in QuickJS initialization, QuickJS AJAX trap, and Node fallback:
  - `java.ajaxAll(urls)`
  - `java.head(url, headers)`
  - `java.getStrResponse(url, rule)`
- `java.ajaxAll` returns response text arrays and supports both arrays and comma-separated URL strings.
- `java.head` returns the same response wrapper shape as `java.fetch/java.connect`, including `body()`, `bodyString()`, `text()`, and `statusCode()`.
- `java.getStrResponse` fetches text and optionally applies the existing HTML/JSON rule extraction path.
- Added a local `data:` URL based test so Windows Node fallback can verify this without hitting the external network, while QuickJS can still exercise the same script through its AJAX callback trap.

### Testing
- Ran `D:\Gemini反重力\flutter\bin\dart.bat format lib\data\parsers\legado\legado_js_engine.dart test\legado_engine_test.dart`.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "supports java ajaxAll head and getStrResponse helpers"`: passed. Current Windows machine still logs missing `quickjs_c_bridge_plugin.dll`; Legacy first rejects top-level `await`, then Node fallback passes.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\source_import_test.dart test\compatibility_analyzer_test.dart test\source_check_classifier_test.dart test\diagnostic_report_test.dart`: 27 tests passed.
- Ran `D:\Gemini反重力\flutter\bin\dart.bat analyze lib\data\parsers\legado\legado_js_engine.dart test\legado_engine_test.dart`: no compile errors; existing warning/info lints remain and cause a non-zero analyzer exit.

### Notes
- Changed files:
  - `lib/data/parsers/legado/legado_js_engine.dart`: HTTP helper shims in QuickJS, trap, and Node fallback.
  - `test/legado_engine_test.dart`: targeted helper coverage.
- Rollback: revert the two changed files listed above and remove this `progress.md` entry.

## 2026-06-26 - Task: Add JS regex and utility compatibility aliases

### What was done
- Added MR/轻悦-style utility bridge methods in QuickJS and Node fallback:
  - `java.getStr(key, defaultValue)`
  - `java.getJson(value)`
  - `java.putJson(key, value)`
  - `java.hexEncodeToString(value)`
  - `java.hexDecodeToString(value)`
  - `java.strToBytes(value)`
  - `java.bytesToStr(bytes)`
  - `java.digestBase64Str(value, algorithm)`
  - `java.hmacSHA256(value, key)`
- Added `java.regex` helpers:
  - `match(input, pattern)`
  - `matchAll(input, pattern)`
  - `replace(input, pattern, replacement)`
  - `test(input, pattern)`
- Kept these as compatibility shims only; no UI changes.

### Testing
- Ran `D:\Gemini反重力\flutter\bin\dart.bat format lib\data\parsers\legado\legado_js_engine.dart test\legado_engine_test.dart`.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "supports java regex and utility aliases"`: passed. Current Windows machine still logs missing `quickjs_c_bridge_plugin.dll`; the test passed through available fallback execution.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "supports java jsoup namespace and content rule overloads"`: passed.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\source_import_test.dart test\compatibility_analyzer_test.dart test\source_check_classifier_test.dart test\diagnostic_report_test.dart`: 27 tests passed.
- Ran `D:\Gemini反重力\flutter\bin\dart.bat analyze lib\data\parsers\legado\legado_js_engine.dart test\legado_engine_test.dart`: no compile errors; existing warning/info lints remain and cause a non-zero analyzer exit.

### Notes
- Changed files:
  - `lib/data/parsers/legado/legado_js_engine.dart`: utility and regex compatibility shims.
  - `test/legado_engine_test.dart`: targeted utility coverage.
- Rollback: revert the two changed files listed above and remove this `progress.md` entry.

## 2026-06-26 - Task: Support java.jsoup helpers and two-argument content rules

### What was done
- Added `java.jsoup` namespace helpers in QuickJS and Node fallback:
  - `java.jsoup.parse(html)`
  - `java.jsoup.select(html, selector)`
  - `java.jsoup.selectFirst(html, selector)`
  - `java.jsoup.getAttr(html, selector, attr)`
  - `java.jsoup.clean(html)`
- Added MR/轻悦-style two-argument content rule overloads:
  - `java.getString(content, rule)`
  - `java.getStringList(content, rule)`
- Node fallback now has a small HTML-rule extractor for CSS selector + `@text/@href/@src/@attr(...)` style rules so Windows fallback can exercise the same source scripts.

### Testing
- Ran `D:\Gemini反重力\flutter\bin\dart.bat format lib\data\parsers\legado\legado_js_engine.dart test\legado_engine_test.dart`.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "supports java jsoup namespace and content rule overloads"`: passed. Current Windows machine still logs missing `quickjs_c_bridge_plugin.dll`; the test passed through available fallback execution.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "supports global MR style helper aliases"`: passed.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\source_import_test.dart test\compatibility_analyzer_test.dart test\source_check_classifier_test.dart test\diagnostic_report_test.dart`: 27 tests passed.
- Ran `D:\Gemini反重力\flutter\bin\dart.bat analyze lib\data\parsers\legado\legado_js_engine.dart test\legado_engine_test.dart`: no compile errors; existing warning/info lints remain and cause a non-zero analyzer exit.

### Notes
- Changed files:
  - `lib/data/parsers/legado/legado_js_engine.dart`: `java.jsoup` namespace and two-argument HTML rule overloads.
  - `test/legado_engine_test.dart`: targeted namespace/overload coverage.
- Rollback: revert the two changed files listed above and remove this `progress.md` entry.

## 2026-06-26 - Task: Add MR-style global JS helper aliases

### What was done
- Added global shortcut aliases used by MR/轻悦-style function sources so scripts do not have to call everything through `java.*`:
  - `getString(...)`
  - `getStringList(...)`
  - `put(...)`
  - `getStr(...)`
  - `ajax(...)`
  - `getWebViewUA()`
  - `base64Encode(...)`
  - `base64Decode(...)`
  - `md5Encode(...)`
  - `sha256Encode(...)`
- Implemented the aliases in both QuickJS initialization and Node fallback.
- Added targeted coverage for direct storage, hash, base64, and UA shortcut calls.

### Testing
- Ran `D:\Gemini反重力\flutter\bin\dart.bat format lib\data\parsers\legado\legado_js_engine.dart test\legado_engine_test.dart`.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "supports global MR style helper aliases"`: passed. Current Windows machine still logs missing `quickjs_c_bridge_plugin.dll`; the test passed through available fallback execution.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "supports global html helper functions"`: passed.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\source_import_test.dart test\compatibility_analyzer_test.dart test\source_check_classifier_test.dart test\diagnostic_report_test.dart`: 27 tests passed.
- Ran `D:\Gemini反重力\flutter\bin\dart.bat analyze lib\data\parsers\legado\legado_js_engine.dart test\legado_engine_test.dart`: no compile errors; existing warning/info lints remain and cause a non-zero analyzer exit.

### Notes
- Changed files:
  - `lib/data/parsers/legado/legado_js_engine.dart`: QuickJS and Node fallback global shortcut aliases.
  - `test/legado_engine_test.dart`: targeted alias coverage.
- Rollback: revert the two changed files listed above and remove this `progress.md` entry.

## 2026-06-26 - Task: Add global HTML helpers for JS function sources

### What was done
- Added global JS helper aliases commonly used by modern function-style sources and MR/轻悦-style templates:
  - `select(html, selector)`
  - `selectFirst(html, selector)`
  - `getAttr(html, selector, attr)`
  - `clean(html)`
  - `htmlFormat(html)`
- Implemented the helpers in both QuickJS initialization and Node fallback so Windows development fallback behavior matches the runtime bridge as closely as possible.
- Added targeted coverage for selecting nodes, first text extraction, attribute extraction, and HTML cleanup.

### Testing
- Ran `D:\Gemini反重力\flutter\bin\dart.bat format lib\data\parsers\legado\legado_js_engine.dart test\legado_engine_test.dart`.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "supports global html helper functions"`: passed. Current Windows machine still logs missing `quickjs_c_bridge_plugin.dll`; the new test passed through available fallback execution.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "supports java.getElements bridge for html result rules"`: passed; same QuickJS DLL limitation applies.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "supports getStringList toArray and setContent in js bridge"`: passed; same QuickJS DLL limitation applies.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\source_import_test.dart test\compatibility_analyzer_test.dart test\source_check_classifier_test.dart test\diagnostic_report_test.dart`: 27 tests passed.
- Ran `D:\Gemini反重力\flutter\bin\dart.bat analyze lib\data\parsers\legado\legado_js_engine.dart test\legado_engine_test.dart`: no compile errors; existing warning/info lints remain and cause a non-zero analyzer exit.

### Notes
- Changed files:
  - `lib/data/parsers/legado/legado_js_engine.dart`: QuickJS and Node fallback global HTML helper aliases.
  - `test/legado_engine_test.dart`: targeted helper coverage.
- Rollback: revert the two changed files listed above and remove this `progress.md` entry.

## 2026-06-26 - Task: Execute JS function TOC and content rules

### What was done
- Verified and covered the existing JS-only TOC path for imported function-style rules like `<js>toc(result)</js>`.
- Added a JS-only content execution path for rules like `<js>content(result)</js>`, including support for JS returning:
  - a plain string,
  - a list of paragraph strings,
  - a map with `content`, `text`, `body`, `data`, or `result`.
- Normalized JS content output through the existing HTML-to-text cleaner so HTML fragments returned by JS are stripped consistently.

### Testing
- Ran `D:\Gemini反重力\flutter\bin\dart.bat format lib\data\parsers\legado_parser.dart test\legado_engine_test.dart`.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "parses imported js function toc results"`: passed; current machine logs missing `quickjs_c_bridge_plugin.dll`, so JS runtime-gated assertions are skipped.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "parses imported js function content results"`: passed; current machine logs missing `quickjs_c_bridge_plugin.dll`, so JS runtime-gated assertions are skipped.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name "parses imported js function search results"`: passed.
- Ran `D:\Gemini反重力\flutter\bin\dart.bat analyze lib\data\parsers\legado_parser.dart test\legado_engine_test.dart`: no errors; existing info-level lints remain.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\source_import_test.dart test\compatibility_analyzer_test.dart test\source_check_classifier_test.dart test\diagnostic_report_test.dart`: 24 tests passed.

### Notes
- Changed files:
  - `lib/data/parsers/legado_parser.dart`: JS-only content execution and output normalization.
  - `test/legado_engine_test.dart`: targeted imported JS function TOC/content coverage.
- Rollback: revert the two changed files listed above and remove this `progress.md` entry.

## 2026-06-26 - Task: Improve source compatibility diagnostics

### What was done
- Extended `CompatibilityAnalyzer` to flag imported JS/function-style sources, QuickJS metadata, `jsLib`, `webJs`, `bodyJs`, WebView/browser requirements, login/Cookie state, and custom request headers.
- Extended `SourceCheckClassifier` so sources that depend on JS runtime, browser/WebView, Cookie/header state, signing, throttling, or access control are classified as `blocked` instead of being incorrectly treated as dead/failed sources.
- Kept UI unchanged and focused on the measurement layer needed for later large-scale source compatibility work.

### Testing
- Ran `D:\Gemini反重力\flutter\bin\dart.bat format lib\features\source_diagnostic\services\compatibility_analyzer.dart lib\features\settings\services\source_check_classifier.dart test\source_check_classifier_test.dart test\compatibility_analyzer_test.dart`.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\source_check_classifier_test.dart test\compatibility_analyzer_test.dart`: 7 tests passed.
- Ran `D:\Gemini反重力\flutter\bin\dart.bat analyze lib\features\source_diagnostic\services\compatibility_analyzer.dart lib\features\settings\services\source_check_classifier.dart test\source_check_classifier_test.dart test\compatibility_analyzer_test.dart`: no issues found.
- Re-ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\source_import_test.dart`: 14 tests passed.

### Notes
- Changed files:
  - `lib/features/source_diagnostic/services/compatibility_analyzer.dart`: richer static runtime/access dependency detection.
  - `lib/features/settings/services/source_check_classifier.dart`: fewer false `failed` classifications for runtime-dependent sources.
  - `test/source_check_classifier_test.dart`: added JS function and browser/access-state cases.
  - `test/compatibility_analyzer_test.dart`: added analyzer coverage for JS function and WebView/Cookie/header dependencies.
- Rollback: revert the four changed files listed above and remove this `progress.md` entry.

## 2026-06-26 - Task: Add actionable diagnostic report summary

### What was done
- Extended `DiagnosticReport` with backward-compatible summary fields:
  - `primaryFailureStage`: first blocking stage (`search`, `detail`, `toc`, `content`, `compatibility`, or `none`).
  - `nextAction`: the most relevant next repair action inferred from the first issue/stage.
  - `stageSummaries`: compact per-stage status cards for search, detail, TOC, and content.
- Added `DiagnosticStageSummary` model and JSON round-trip support while keeping old saved diagnostic history readable.
- Fixed broken string literals in `ExploreViewModel` that were caused by mojibake and prevented broader tests from compiling.

### Testing
- Ran `D:\Gemini反重力\flutter\bin\dart.bat format lib\data\models\diagnostic_report.dart test\diagnostic_report_test.dart lib\features\explore\viewmodels\explore_viewmodel.dart`.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\diagnostic_report_test.dart test\source_check_classifier_test.dart test\compatibility_analyzer_test.dart`: 10 tests passed.
- Ran `D:\Gemini反重力\flutter\bin\dart.bat analyze lib\data\models\diagnostic_report.dart lib\features\source_diagnostic\services\source_diagnostic_service.dart lib\features\explore\viewmodels\explore_viewmodel.dart test\diagnostic_report_test.dart`: no issues found.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\legado_engine_test.dart --plain-name CompatibilityAnalyzer`: 2 tests passed. The QuickJS DLL warning is an environment/runtime availability message and did not fail the tests.
- Ran `D:\Gemini反重力\flutter\bin\flutter.bat test test\diagnostic_report_test.dart test\source_check_classifier_test.dart test\compatibility_analyzer_test.dart test\source_import_test.dart`: 24 tests passed.

### Notes
- Changed files:
  - `lib/data/models/diagnostic_report.dart`: report summary model, inference, JSON compatibility.
  - `lib/features/explore/viewmodels/explore_viewmodel.dart`: fixed malformed user-facing search failure strings.
  - `test/diagnostic_report_test.dart`: coverage for inferred summaries, backward compatibility, and JSON round-trip.
- Rollback: revert the three changed files listed above and remove this `progress.md` entry.
