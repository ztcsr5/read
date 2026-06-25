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
