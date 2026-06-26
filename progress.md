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
