## 2026-06-27 - Task: P1/P1-1 novel reader text layout and font sizing
### What was done
- Kept the novel reader body on its own text scale so reader font-size settings render directly and are not multiplied by the app-wide text scaler.
- Made chapter titles render through one full-width centered title widget in both scroll and paged reading modes.
- Kept HTML chapter content aligned with plain text behavior by ignoring an empty font-family value.

### Testing
- `git diff --check` passed.
- `.\flutter.ps1 analyze lib/pages/reader/novel_reader_page.dart` could not run because Flutter SDK is not configured on this machine (`FLUTTER_ROOT`/PATH missing).

### Notes
- `lib/pages/reader/novel_reader_page.dart`: adjusted reader-body text scaling, chapter title layout, and HTML font-family handling.
- `progress.md`: added this task log.
- Rollback before staging: run `git restore -- lib/pages/reader/novel_reader_page.dart` and `Remove-Item -LiteralPath progress.md`; after commit, use that commit as the rollback point.

## 2026-06-27 - Task: P2 reader body theme settings
### What was done
- Changed reader style presets from background-only choices to paired background and body text color themes.
- Kept the custom background image entry intact, so users can still choose an image theme separately.
- Documented the reader UI boundary and theme behavior in `docs/reader-ui.md`.

### Testing
- `FLUTTER_ROOT=D:\Gemini反重力\flutter .\flutter.ps1 analyze lib/pages/reader/novel_reader_page.dart lib/widgets/reader/reader_settings_sheet.dart` passed.
- `git diff --check` passed.

### Notes
- `lib/widgets/reader/reader_settings_sheet.dart`: added reader theme presets with paired background and text colors.
- `lib/pages/reader/novel_reader_page.dart`: passed the current text color into the reader settings sheet and applied selected theme text colors through `ReaderProvider`.
- `docs/reader-ui.md`: documented reader UI scope, text layout behavior, and theme preset behavior.
- `progress.md`: appended this task log.
- Rollback before staging: run `git restore -- lib/widgets/reader/reader_settings_sheet.dart lib/pages/reader/novel_reader_page.dart` and `Remove-Item -LiteralPath docs/reader-ui.md`; remove this P2 section from `progress.md`. After commit, use that commit as the rollback point.

## 2026-06-28 - Task: P3 detail-page cache entry to chapter list
### What was done
- Changed the detail-page cache/download action from placeholder batch-download choices to opening the chapter list in cache-management mode.
- Added a cache-management banner on the chapter list that shows existing cached chapter count versus total text chapters.
- Kept the existing per-chapter cloud marker for uncached online chapters and did not add any batch download, parser, source, bridge, or network-request changes.
- Documented the UI-only cache-entry behavior in `docs/reader-ui.md`.

### Testing
- `FLUTTER_ROOT=D:\Gemini反重力\flutter .\flutter.ps1 analyze lib/pages/detail/detail_page.dart lib/pages/detail/chapter_list_page.dart lib/routes/app_routes.dart` passed.
- `git diff --check` passed.

### Notes
- `lib/pages/detail/detail_page.dart`: routed the detail cache action into the chapter list cache-management mode and removed the placeholder download choices.
- `lib/pages/detail/chapter_list_page.dart`: accepted cache-management mode and displayed existing cache progress from current chapter cache files.
- `lib/routes/app_routes.dart`: passed the cache-management route argument into the chapter list page.
- `docs/reader-ui.md`: documented the detail cache entry behavior and the unchanged B-line boundary.
- `progress.md`: appended this task log.
- Rollback before staging: run `git restore -- lib/pages/detail/detail_page.dart lib/pages/detail/chapter_list_page.dart lib/routes/app_routes.dart docs/reader-ui.md`; remove this P3 section from `progress.md`. After commit, use that commit as the rollback point.

## 2026-06-28 - Task: P3-1 chapter list cache
### What was done
- Added a chapter-list cache wrapper on the existing app cache store for saving, reading, and clearing directory metadata by book URL.
- Made the detail page and chapter list page show cached directory metadata when available, then refresh and overwrite the cache after a successful directory load.
- Kept the cached directory visible when a later refresh fails, instead of dropping the page to an empty chapter list.
- Linked the existing detail-page clear-cache action to clear the directory cache for that book.
- Documented that this cache stores chapter metadata only and does not change parser, source, bridge, or network behavior.

### Testing
- `FLUTTER_ROOT=D:\Gemini反重力\flutter .\flutter.ps1 analyze lib/services/storage_service.dart lib/pages/detail/detail_page.dart lib/pages/detail/chapter_list_page.dart lib/routes/app_routes.dart` passed.
- `git diff --check` passed.

### Notes
- `lib/services/storage_service.dart`: added chapter-list cache save/read/clear helpers using the existing cache Box.
- `lib/pages/detail/detail_page.dart`: loaded cached directories before refresh, saved fresh directories after success, and cleared directory cache with book cache cleanup.
- `lib/pages/detail/chapter_list_page.dart`: loaded cached directories before refresh and saved fresh directories after success.
- `lib/routes/app_routes.dart`: kept the cache-management route argument used by the P3 detail cache entry.
- `docs/reader-ui.md`: documented the chapter-list cache behavior and unchanged B-line boundary.
- `progress.md`: appended this task log.
- Rollback before staging: run `git restore -- lib/services/storage_service.dart lib/pages/detail/detail_page.dart lib/pages/detail/chapter_list_page.dart lib/routes/app_routes.dart docs/reader-ui.md`; remove this P3-1 section from `progress.md`. After commit, use that commit as the rollback point.

## 2026-06-28 - Task: P4 search page cache
### What was done
- Added search-result cache helpers on the existing app cache store, keyed by keyword and selected source URLs.
- Made the search provider show cached results while a fresh search is running for the same keyword/source set.
- Replaced the cached display when fresh source results arrive and saved the latest search results after the search completes.
- Documented that the cache stores search-result metadata only and does not change parser, source, bridge, or network behavior.

### Testing
- `FLUTTER_ROOT=D:\Gemini反重力\flutter .\flutter.ps1 analyze lib/providers/search_provider.dart lib/services/storage_service.dart` passed.
- `git diff --check` passed.

### Notes
- `lib/services/storage_service.dart`: added search-result cache save/read helpers using the existing cache Box.
- `lib/providers/search_provider.dart`: loaded cached search results before fresh search and saved latest results after completion.
- `docs/reader-ui.md`: documented search-result cache behavior and unchanged B-line boundary.
- `progress.md`: appended this task log.
- Rollback before staging: run `git restore -- lib/services/storage_service.dart lib/providers/search_provider.dart docs/reader-ui.md`; remove this P4 section from `progress.md`. After commit, use that commit as the rollback point.

## 2026-06-28 - Task: P4-1 detail page fallback from search cache
### What was done
- Added a per-book search metadata cache entry when search results are saved.
- Made the detail page fall back to cached search metadata by book URL when there is no bookshelf record and no route-provided book data.
- Documented that this fallback uses search-result metadata only and does not cache body content or change parser, source, bridge, or network behavior.

### Testing
- `FLUTTER_ROOT=D:\Gemini反重力\flutter .\flutter.ps1 analyze lib/services/storage_service.dart lib/pages/detail/detail_page.dart lib/providers/search_provider.dart lib/routes/app_routes.dart lib/pages/search/search_page.dart` passed.
- `git diff --check` passed.

### Notes
- `lib/services/storage_service.dart`: added per-book search metadata cache save/read helpers and indexed each saved search result by book URL.
- `lib/pages/detail/detail_page.dart`: used the per-book search cache as a fallback initial book record.
- `docs/reader-ui.md`: documented the detail-page fallback from search cache.
- `progress.md`: appended this task log.
- Rollback before staging: run `git restore -- lib/services/storage_service.dart lib/pages/detail/detail_page.dart docs/reader-ui.md`; remove this P4-1 section from `progress.md`. After commit, use that commit as the rollback point.

## 2026-06-28 - Task: P5 multi-source concurrent search
### What was done
- Changed the default searchable source selection from the first five sources to all enabled searchable sources.
- Added search provider state for total selected sources, completed sources, and active worker count.
- Updated the search page progress display to show source progress, bounded worker count, and current result count during search.
- Kept the existing bounded worker pool and stop-search behavior; no parser, bridge, source-engine, or network request implementation was changed.

### Testing
- `FLUTTER_ROOT=D:\Gemini反重力\flutter .\flutter.ps1 analyze lib/providers/search_provider.dart lib/pages/search/search_page.dart lib/services/storage_service.dart` passed.
- `git diff --check` passed.

### Notes
- `lib/providers/search_provider.dart`: enabled all searchable sources by default and exposed multi-source concurrent search progress state.
- `lib/pages/search/search_page.dart`: displayed multi-source progress while searches are running.
- `docs/reader-ui.md`: documented multi-source search behavior and unchanged B-line boundary.
- `progress.md`: appended this task log.
- Rollback before staging: run `git restore -- lib/providers/search_provider.dart lib/pages/search/search_page.dart docs/reader-ui.md`; remove this P5 section from `progress.md`. After commit, use that commit as the rollback point.

## 2026-06-28 - Task: P5-1 group search
### What was done
- Added provider helpers for source group names, selected group detection, all-source selection state, and per-group source counts.
- Added a horizontal source-group shortcut bar under the search bar.
- Made group shortcuts select only that source group and search the current keyword; the all-source shortcut restores the full source set.
- Reused the existing bounded worker pool and source selection behavior, with no parser, bridge, source-engine, or network request implementation changes.

### Testing
- `FLUTTER_ROOT=D:\Gemini反重力\flutter .\flutter.ps1 analyze lib/providers/search_provider.dart lib/pages/search/search_page.dart lib/services/storage_service.dart` passed.
- `git diff --check` passed.

### Notes
- `lib/providers/search_provider.dart`: exposed source-group state and unified group matching.
- `lib/pages/search/search_page.dart`: added group-search shortcuts and current-keyword search behavior.
- `docs/reader-ui.md`: documented group search behavior and unchanged B-line boundary.
- `progress.md`: appended this task log.
- Rollback before staging: run `git restore -- lib/providers/search_provider.dart lib/pages/search/search_page.dart docs/reader-ui.md`; remove this P5-1 section from `progress.md`. After commit, use that commit as the rollback point.

## 2026-06-28 - Task: P6 search interaction component polish
### What was done
- Polished the search source-scope bar into a compact horizontal UI component with divider boundaries and a scope icon.
- Added a clearer selected state for all-source and group chips, including a check icon and constrained labels for long group names.
- Kept the existing selection and current-keyword rerun behavior; no parser, bridge, source-engine, or network request implementation was changed.
- Documented the UI-only component behavior in `docs/reader-ui.md`.

### Testing
- `FLUTTER_ROOT=D:\Gemini反重力\flutter .\flutter.ps1 analyze lib/pages/search/search_page.dart lib/providers/search_provider.dart` passed.
- `git diff --check` passed.

### Notes
- `lib/pages/search/search_page.dart`: refined the group/source scope shortcut bar as a compact reusable search interaction component.
- `docs/reader-ui.md`: documented the search interaction component polish and unchanged B-line boundary.
- `progress.md`: appended this task log.
- Rollback before staging: run `git restore -- lib/pages/search/search_page.dart docs/reader-ui.md`; remove this P6 section from `progress.md`. After commit, use that commit as the rollback point.

## 2026-06-28 - Task: P6 search progress component polish
### What was done
- Replaced the separate search loading line and conditional result text with one compact search status bar.
- Made the status bar show source progress, active worker count, result count, and a determinate progress bar when the total selected source count is available.
- Kept the existing progress visibility toggle by falling back to the thin loading indicator when progress display is disabled.
- Removed duplicate progress text from the empty-results loading state, keeping that area focused on the spinner.

### Testing
- `FLUTTER_ROOT=D:\Gemini反重力\flutter .\flutter.ps1 analyze lib/pages/search/search_page.dart lib/providers/search_provider.dart` passed.
- `git diff --check` passed.

### Notes
- `lib/pages/search/search_page.dart`: refined the search loading/progress feedback as a compact status component.
- `docs/reader-ui.md`: documented the search progress status bar behavior.
- `progress.md`: appended this task log.
- Rollback before staging: run `git restore -- lib/pages/search/search_page.dart docs/reader-ui.md`; remove this P6 search progress section from `progress.md`. After commit, use that commit as the rollback point.

## 2026-06-28 - Task: P6 source pick dialog repositioning
### What was done
- Repositioned the existing search-scope dialog as an advanced source-pick entry instead of a general group-search entry.
- Renamed the menu item and dialog title to "书源精选" while keeping the manual source selection behavior unchanged.
- Documented that normal all-source and group searches belong to the compact scope bar, while the dialog remains for precise source combinations.

### Testing
- `FLUTTER_ROOT=D:\Gemini反重力\flutter .\flutter.ps1 analyze lib/pages/search/search_page.dart` passed.
- `git diff --check` passed.

### Notes
- `lib/pages/search/search_page.dart`: renamed the advanced source-selection entry and dialog title.
- `docs/reader-ui.md`: documented the dialog's advanced-source-pick role.
- `progress.md`: appended this task log.
- Rollback before staging: run `git restore -- lib/pages/search/search_page.dart docs/reader-ui.md`; remove this P6 source pick section from `progress.md`. After commit, use that commit as the rollback point.

## 2026-06-28 - Task: P6 source pick dialog polish
### What was done
- Changed the source-pick dialog's selected source count into a compact status pill.
- Made the dialog confirmation rerun search from the current search-field keyword when at least one source remains selected.
- Kept all existing manual source selection, group expansion, and group-only selection behavior unchanged.

### Testing
- `FLUTTER_ROOT=D:\Gemini反重力\flutter .\flutter.ps1 analyze lib/pages/search/search_page.dart` passed.
- `git diff --check` passed.

### Notes
- `lib/pages/search/search_page.dart`: polished the source-pick dialog count display and confirmation behavior.
- `docs/reader-ui.md`: documented the source-pick dialog selected-count and confirmation behavior.
- `progress.md`: appended this task log.
- Rollback before staging: run `git restore -- lib/pages/search/search_page.dart docs/reader-ui.md`; remove this P6 source pick polish section from `progress.md`. After commit, use that commit as the rollback point.

## 2026-06-28 - Task: P6 source pick group row polish
### What was done
- Reworked source-pick group rows into compact headers with expand/collapse, selected count, group-only search, and whole-group selection in one line.
- Shortened the group-only action text from "仅搜此组" to "仅搜" to reduce row crowding.
- Preserved the existing manual source selection, group expansion, group-only selection, and whole-group toggle behavior.

### Testing
- `FLUTTER_ROOT=D:\Gemini反重力\flutter .\flutter.ps1 analyze lib/pages/search/search_page.dart` passed.
- `git diff --check` passed.

### Notes
- `lib/pages/search/search_page.dart`: refined the source-pick dialog group row layout without changing selection behavior.
- `docs/reader-ui.md`: documented the compact source-pick group row behavior.
- `progress.md`: appended this task log.
- Rollback before staging: run `git restore -- lib/pages/search/search_page.dart docs/reader-ui.md`; remove this P6 source pick group row section from `progress.md`. After commit, use that commit as the rollback point.

## 2026-06-28 - Task: P6 source pick source row polish
### What was done
- Replaced expanded source rows in the source-pick dialog with compact single-line rows.
- Kept the source type icon, source name, and selected state visible while reducing indentation and row height.
- Preserved the existing tap-to-toggle source selection behavior.

### Testing
- `FLUTTER_ROOT=D:\Gemini反重力\flutter .\flutter.ps1 analyze lib/pages/search/search_page.dart` passed.
- `git diff --check` passed.

### Notes
- `lib/pages/search/search_page.dart`: refined expanded source rows in the source-pick dialog without changing selection behavior.
- `docs/reader-ui.md`: documented the compact source-pick source row behavior.
- `progress.md`: appended this task log.
- Rollback before staging: run `git restore -- lib/pages/search/search_page.dart docs/reader-ui.md`; remove this P6 source pick source row section from `progress.md`. After commit, use that commit as the rollback point.

## 2026-06-28 - Task: P6 search result list row polish
### What was done
- Reordered list-mode search result metadata so title, author, latest chapter, intro, source, and tags read in a clearer hierarchy.
- Promoted the source name into a bounded pill and limited tag pills to avoid long labels breaking narrow layouts.
- Preserved the existing cover rendering and tap-to-detail behavior.

### Testing
- `FLUTTER_ROOT=D:\Gemini反重力\flutter .\flutter.ps1 analyze lib/pages/search/search_page.dart` passed.
- `git diff --check` passed.

### Notes
- `lib/pages/search/search_page.dart`: refined list-mode search result row typography and metadata layout without changing navigation or search behavior.
- `docs/reader-ui.md`: documented the list row hierarchy and bounded label behavior.
- `progress.md`: appended this task log.
- Rollback before staging: run `git restore -- lib/pages/search/search_page.dart docs/reader-ui.md`; remove this P6 search result list row section from `progress.md`. After commit, use that commit as the rollback point.

## 2026-06-28 - Task: P6 search result grid card polish
### What was done
- Refined grid-mode search result card typography so title and latest chapter have clearer hierarchy.
- Promoted source name into a bounded pill to keep long source labels from crowding the card.
- Preserved the existing cover rendering, grid structure, and tap-to-detail behavior.

### Testing
- `FLUTTER_ROOT=D:\Gemini反重力\flutter .\flutter.ps1 analyze lib/pages/search/search_page.dart` passed.
- `git diff --check` passed.

### Notes
- `lib/pages/search/search_page.dart`: refined grid-mode search result card text hierarchy and source label without changing navigation or search behavior.
- `docs/reader-ui.md`: documented the grid card hierarchy and bounded source pill behavior.
- `progress.md`: appended this task log.
- Rollback before staging: run `git restore -- lib/pages/search/search_page.dart docs/reader-ui.md`; remove this P6 search result grid card section from `progress.md`. After commit, use that commit as the rollback point.

## 2026-06-28 - Task: P6 chapter cache summary polish
### What was done
- Refined the chapter-list cache-management summary into a compact status bar with a clearer title, cloud-marker hint, cached/total count pill, and progress indicator.
- Clamped the visual progress value to the valid 0-1 range.
- Preserved existing chapter cache counting, chapter rows, and cache-management routing behavior.

### Testing
- `FLUTTER_ROOT=D:\Gemini反重力\flutter .\flutter.ps1 analyze lib/pages/detail/chapter_list_page.dart` passed.
- `git diff --check` passed.

### Notes
- `lib/pages/detail/chapter_list_page.dart`: refined the cache-management summary bar UI without changing cache service or chapter loading behavior.
- `docs/reader-ui.md`: documented the chapter-list cache summary behavior.
- `progress.md`: appended this task log.
- Rollback before staging: run `git restore -- lib/pages/detail/chapter_list_page.dart docs/reader-ui.md`; remove this P6 chapter cache summary section from `progress.md`. After commit, use that commit as the rollback point.

## 2026-06-28 - Task: Profile reader settings text color compile fix
### What was done
- Added the reader body text color value and callback to the profile-page reader settings sheet invocation.
- Fixed the Chrome build error caused by the shared reader settings sheet requiring the text color parameter.
- Kept the existing profile-page reader settings behavior otherwise unchanged.

### Testing
- `FLUTTER_ROOT=D:\Gemini反重力\flutter .\flutter.ps1 analyze --no-fatal-infos lib/pages/profile/profile_page.dart lib/widgets/reader/reader_settings_sheet.dart lib/providers/reader_provider.dart` completed with only existing deprecated API info.
- `FLUTTER_ROOT=D:\Gemini反重力\flutter .\flutter.ps1 run -d chrome --web-hostname 127.0.0.1 --web-port 0` compiled and launched after this fix; runtime then exposed an existing BookshelfProvider build-phase notification issue unrelated to this compile fix.

### Notes
- `lib/pages/profile/profile_page.dart`: passed `provider.textColor` and `provider.setTextColor` into the shared reader settings sheet.
- `docs/reader-ui.md`: documented profile reader settings text color consistency.
- `progress.md`: appended this task log.
- Rollback before staging: run `git restore -- lib/pages/profile/profile_page.dart docs/reader-ui.md`; remove this profile reader settings section from `progress.md`. After commit, use that commit as the rollback point.
