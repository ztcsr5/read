## 2026-06-27 - Task: Restart Swift against Flutter product baseline

### What was done
- Locked the Swift direction back to the Flutter product baseline: `D:\Gemini反重力\read` is the only UI, navigation, page-inventory, and user-facing behavior baseline.
- Clarified that the old Flutter source engine should not be copied into Swift; it is only a field-map, fixture, diagnostic, and compatibility-reference corpus.
- Added a dedicated Flutter-to-Swift parity ledger covering app shell, home/bookshelf, discover/search, reader, settings, and source-compatibility boundaries.
- Replaced the Swift root paged `TabView` shell with a persistent indexed `ZStack` shell to better match Flutter's indexed branch behavior and reduce tab/keyboard/scroll gesture competition.
- Fixed a bookshelf compile/logic regression where the shelf header tried to mark updates seen with an out-of-scope `book.id`.
- Added press feedback and haptics to bookshelf rows and collection rows, and made update rows clear update state when opened.
- Split reader cover mode away from the horizontal paged `TabView` so page-turn and cover modes no longer feel identical.
- Added reader-mode haptic feedback and made theme page backgrounds react to settings changes.
- Changed source local-file import from a fixed modal-delay race to a state-driven picker launch after the import sheet dismisses.
- Separated Discover search result browsing from the add-to-bookshelf button so tapping plus does not ride inside the row navigation link.

### Testing
- Ran `git diff --check`; it passed with only existing Windows LF-to-CRLF warnings.
- Confirmed the app shell no longer uses a paged root `TabView`; remaining `TabView.page` usage is inside reader page mode.
- Windows cannot compile or launch the iOS app locally; device-level smoothness and keyboard behavior still require Xcode/GitHub Actions and iPhone testing.

### Notes
- Changed files:
  - `docs/superpowers/specs/2026-06-24-swift-v2-lifetime-reader-design.md`: added the locked baseline and source-engine boundary decisions.
  - `docs/superpowers/specs/2026-06-27-flutter-to-swift-parity-ledger.md`: new parity ledger for future implementation.
  - `SourceReadSwift/App/RootTabView.swift`: changed root tab shell from paged `TabView` to persistent indexed content.
  - `progress.md`: recorded this restart checkpoint.
- Rollback: revert this progress entry, delete the new parity ledger, and revert the `RootTabView.swift` shell change.

## 2026-06-24 - Task: Swift v2 lifetime reader restart specification

### What was done
- Established the Swift v2 direction as a long-term personal iOS reader, not a temporary prototype.
- Defined Swift as the native experience layer, Rust as the preferred future deterministic core, and WKWebView/JavaScriptCore as the source JS host.
- Limited the first source compatibility route to Legado JSON, iOS-compatible JSON, and Qingyue Shiguang-style functional JS sources; Xiangse Guige XBS is deferred as a separate format.
- Documented non-negotiable acceptance gates before any implementation work.

### Testing
- Documentation-only change. No source code was modified and no build/test command was required.
- Verified repository context before writing: current branch was `codex/swift-v2-lifetime-reader`, with only an unrelated untracked `ci-log/run-27952116519/` directory present.

### Notes
- Changed files:
  - `docs/superpowers/specs/2026-06-24-swift-v2-lifetime-reader-design.md`: new Swift v2 lifetime-reader design contract and phased execution plan.
  - `progress.md`: new project progress log entry for this documentation task.
- Rollback: delete the two files above, or revert the commit that contains this documentation milestone.

## 2026-06-25 - Task: Phase 1 reader native visual shell

### What was done
- Upgraded the native Swift reader screen from a flat reading surface to a softer iOS-style reading shell.
- Added a background gradient and accent glow that adapt to dark and light reading backgrounds.
- Reworked the reading chrome into floating glass panels for the top toolbar, bottom controls, settings sheet, and status banner.
- Added light haptic feedback to reader toolbar actions and smoother spring transitions for overlay/settings chrome.

### Testing
- Ran `git diff --check`; it passed with only the existing Windows LF-to-CRLF warning.
- Confirmed `project.yml` targets iOS 16.0, so the navigation toolbar hiding API used by this change is within the supported deployment target.
- Windows cannot compile or launch the iOS app locally; final UI/runtime verification still requires Xcode or GitHub Actions at the next coherent milestone.

### Notes
- Changed files:
  - `SourceReadSwift/Features/Reader/ReaderView.swift`: refined the reader visual shell, floating glass controls, adaptive chrome colors, haptics, and overlay transitions.
  - `progress.md`: recorded this Phase 1 reader-shell milestone and verification limits.
- Rollback: revert this progress entry and the corresponding changes in `SourceReadSwift/Features/Reader/ReaderView.swift`, or revert the commit that contains this milestone.

## 2026-06-25 - Task: Phase 1 bookshelf native home shell

### What was done
- Moved the Swift bookshelf home closer to the Flutter baseline home structure: native large title, import action, horizontal immersive reading cards, update list, and shelf section.
- Removed the home page personal/profile shortcut so the top-right area only keeps the requested import entry.
- Added a subtle Podcasts-style background layer and glass import button instead of a flat grouped background.
- Reworked the currently-reading hero card into a horizontal immersive card with cover, reading progress, title, author, continue-reading action, press feedback, and light haptics.

### Testing
- Ran `git diff --check`; it passed with only the existing Windows LF-to-CRLF warning.
- Confirmed there are no remaining `ReaderProfileView` references after removing the home profile entry.
- Windows cannot compile or launch the iOS app locally; final runtime verification still requires Xcode or GitHub Actions when this visual-shell milestone is ready to package.

### Notes
- Changed files:
  - `SourceReadSwift/Features/Bookshelf/BookshelfView.swift`: refined home page visual shell, removed profile entry, added press feedback, and adjusted currently-reading card layout.
  - `progress.md`: recorded this Phase 1 bookshelf-home milestone and verification limits.
- Rollback: revert this progress entry and the corresponding changes in `SourceReadSwift/Features/Bookshelf/BookshelfView.swift`, or revert the commit that contains this milestone.

## 2026-06-25 - Task: Phase 1 root tab chrome cleanup

### What was done
- Removed the bottom continue-reading mini player from the global tab chrome so the home page no longer shows an unwanted playback strip.
- Simplified the bottom navigation into a single floating Podcasts-style glass tab bar.
- Added selected-tab capsule emphasis and press-scale feedback to improve perceived responsiveness.
- Removed the now-unused mini-player state and cover helpers created by the old tab chrome.

### Testing
- Ran `git diff --check`; it passed with only the existing Windows LF-to-CRLF warning.
- Confirmed `RootTabView.swift` has no remaining `presentedBook`, `miniCover`, `play.fill`, or `继续阅读` mini-player references.
- Windows cannot compile or launch the iOS app locally; final runtime verification still requires Xcode or GitHub Actions when this visual-shell milestone is ready to package.

### Notes
- Changed files:
  - `SourceReadSwift/App/RootTabView.swift`: removed the mini-player strip and refined the floating glass tab bar interaction.
  - `progress.md`: recorded this Phase 1 root-tab chrome milestone and verification limits.
- Rollback: revert this progress entry and the corresponding changes in `SourceReadSwift/App/RootTabView.swift`, or revert the commit that contains this milestone.

## 2026-06-25 - Task: Phase 1 settings interaction polish

### What was done
- Improved Settings page interaction feedback for appearance switching and cache clearing with native haptics.
- Aligned Settings page surface treatment with the app background instead of the default plain system list backdrop.
- Kept the change limited to Settings interaction polish; no settings data model or navigation behavior was changed.

### Testing
- Ran `git diff --check`; it passed with only the existing Windows LF-to-CRLF warning.
- Reviewed the diff to confirm the change only affects haptic feedback and list/background presentation.
- Windows cannot compile or launch the iOS app locally; final runtime verification still requires Xcode or GitHub Actions when this visual-shell milestone is ready to package.

### Notes
- Changed files:
  - `SourceReadSwift/Features/Settings/SettingsView.swift`: added haptic feedback and aligned the list background with the app visual shell.
  - `progress.md`: recorded this Phase 1 settings interaction polish milestone and verification limits.
- Rollback: revert this progress entry and the corresponding changes in `SourceReadSwift/Features/Settings/SettingsView.swift`, or revert the commit that contains this milestone.

## 2026-06-25 - Task: Import entry interaction reliability polish

### What was done
- Added immediate haptic feedback to bookshelf local-book import entry and source-manager import entry so taps no longer feel dead.
- Added a visible "opening file picker" status before transitioning from the source import sheet to the system document picker.
- Increased the source import sheet-to-picker delay slightly to reduce SwiftUI modal transition races.

### Testing
- Ran `git diff --check`; it passed with only the existing Windows LF-to-CRLF warning.
- Reviewed the diff to confirm the change only affects import-entry feedback and picker presentation timing, not source parsing or storage behavior.
- Windows cannot compile or launch the iOS app locally; final file-picker behavior still requires device or Xcode/GitHub Actions verification.

### Notes
- Changed files:
  - `SourceReadSwift/Features/Bookshelf/BookshelfView.swift`: added haptic feedback to the empty bookshelf import card.
  - `SourceReadSwift/Features/SourceManager/SourceManagerView.swift`: added haptic feedback and safer sheet-to-picker transition timing for local source import.
  - `progress.md`: recorded this import interaction polish milestone and verification limits.
- Rollback: revert this progress entry and the corresponding changes in `SourceReadSwift/Features/Bookshelf/BookshelfView.swift` and `SourceReadSwift/Features/SourceManager/SourceManagerView.swift`, or revert the commit that contains this milestone.

## 2026-06-25 - Task: Reader appearance settings live preview

### What was done
- Added a live reading preview inside the reader appearance panel so font size, line spacing, and background changes are immediately visible.
- Added haptic feedback to background color selection.
- Kept the change limited to reader appearance usability; no reader persistence, chapter loading, or source behavior was changed.

### Testing
- Ran `git diff --check`; it passed with only the existing Windows LF-to-CRLF warning.
- Reviewed the diff to confirm the reader settings preview uses existing reader appearance state and does not introduce new storage keys.
- Windows cannot compile or launch the iOS app locally; final runtime verification still requires Xcode or GitHub Actions when this visual-shell milestone is ready to package.

### Notes
- Changed files:
  - `SourceReadSwift/Features/Reader/ReaderView.swift`: added live appearance preview and background-selection haptics.
  - `progress.md`: recorded this reader appearance usability milestone and verification limits.
- Rollback: revert this progress entry and the corresponding changes in `SourceReadSwift/Features/Reader/ReaderView.swift`, or revert the commit that contains this milestone.

## 2026-06-25 - Task: Search detail should not auto-add to bookshelf

### What was done
- Changed search book detail loading so viewing a search result no longer automatically adds the book to the bookshelf.
- Kept explicit add behavior on the plus button and preserved detail metadata updates when the book is already in the bookshelf.
- Made chapter reading from an unadded search detail use a temporary reader identity, so browsing a result does not write reading progress into the bookshelf.
- Added haptic feedback to the search-row plus button.

### Testing
- Ran `git diff --check`; it passed with only the existing Windows LF-to-CRLF warning.
- Verified by code search that `BookDetailView` now calls `addOrUpdate(book)` only from the explicit add path, not from automatic detail loading.
- Windows cannot compile or launch the iOS app locally; final navigation/runtime verification still requires Xcode or GitHub Actions when this milestone is ready to package.

### Notes
- Changed files:
  - `SourceReadSwift/Features/Discover/BookDetailView.swift`: removed automatic bookshelf insertion from detail loading and kept explicit add behavior.
  - `SourceReadSwift/Features/Discover/SearchBookRow.swift`: added haptic feedback to the plus button.
  - `progress.md`: recorded this search-to-bookshelf product-logic fix and verification limits.
- Rollback: revert this progress entry and the corresponding changes in `SourceReadSwift/Features/Discover/BookDetailView.swift` and `SourceReadSwift/Features/Discover/SearchBookRow.swift`, or revert the commit that contains this milestone.

## 2026-06-25 - Task: Latest-updates state should clear after viewing

### What was done
- Changed bookshelf update detection from "book is not fully read" to "source refresh found more chapters than the user has seen".
- Added local update-seen state so tapping an updated book clears it from the Latest Updates section without changing reading progress.
- Preserved first-time detail sync behavior so newly added books do not immediately appear as updated.

### Testing
- Ran `git diff --check`; it passed with only the existing Windows LF-to-CRLF warning.
- Reviewed update-state paths: first detail sync initializes seen count, later refreshes can mark updates, and tapping an update row marks updates seen.
- Windows cannot compile or launch the iOS app locally; final runtime verification still requires Xcode or GitHub Actions when this milestone is ready to package.

### Notes
- Changed files:
  - `SourceReadSwift/Core/Models/BookshelfModels.swift`: added optional update-seen chapter count and changed update detection semantics.
  - `SourceReadSwift/Core/Storage/BookshelfStore.swift`: initialized, updated, and cleared update-seen state.
  - `SourceReadSwift/Features/Bookshelf/BookshelfView.swift`: marks update rows as seen when opened.
  - `progress.md`: recorded this Latest Updates product-logic fix and verification limits.
- Rollback: revert this progress entry and the corresponding changes in `SourceReadSwift/Core/Models/BookshelfModels.swift`, `SourceReadSwift/Core/Storage/BookshelfStore.swift`, and `SourceReadSwift/Features/Bookshelf/BookshelfView.swift`, or revert the commit that contains this milestone.

## 2026-06-25 - Task: Show full chapter list in search detail

### What was done
- Removed the fixed 80-chapter cap from search book detail pages.
- Kept the existing lazy chapter list so long novels can expose the full directory without eagerly rendering all rows at once.

### Testing
- Ran `git diff --check`; it passed with only the existing Windows LF-to-CRLF warning.
- Verified the detail page now iterates over `chapters` directly instead of `chapters.prefix(80)`.
- Windows cannot compile or launch the iOS app locally; final runtime verification still requires Xcode or GitHub Actions when this milestone is ready to package.

### Notes
- Changed files:
  - `SourceReadSwift/Features/Discover/BookDetailView.swift`: removed the artificial chapter-list cap.
  - `progress.md`: recorded this directory completeness fix and verification limits.
- Rollback: revert this progress entry and the corresponding change in `SourceReadSwift/Features/Discover/BookDetailView.swift`, or revert the commit that contains this milestone.

## 2026-06-25 - Task: Bookshelf latest-update regression tests

### What was done
- Added a unit test covering the new Latest Updates semantics: first detail sync is not an update, later chapter-count growth is an update, and marking updates seen clears it.
- Extended the source-switch test to assert update-seen state resets to the switched source chapter count.

### Testing
- Ran `git diff --check`; it passed with only the existing Windows LF-to-CRLF warning.
- XCTest was not executed locally because this Windows environment cannot run Xcode/iOS XCTest.

### Notes
- Changed files:
  - `SourceReadSwiftTests/BookshelfStoreTests.swift`: added regression coverage for latest-update seen-state behavior.
  - `progress.md`: recorded this test coverage milestone and verification limits.
- Rollback: revert this progress entry and the corresponding changes in `SourceReadSwiftTests/BookshelfStoreTests.swift`, or revert the commit that contains this milestone.

## 2026-06-25 - Task: Search result list stability

### What was done
- Filtered empty-title search results before rendering.
- Deduplicated search results by stable `SearchBook.id` while preserving first-seen ordering.
- Kept matching behavior unchanged except that exact mode now runs after the same cleanup as fuzzy mode.

### Testing
- Ran `git diff --check`; it passed with only the existing Windows LF-to-CRLF warning.
- Reviewed the search aggregation path to confirm cleanup happens before assigning data to the SwiftUI result list.
- Windows cannot compile or launch the iOS app locally; final runtime verification still requires Xcode or GitHub Actions when this milestone is ready to package.

### Notes
- Changed files:
  - `SourceReadSwift/Features/Discover/DiscoverView.swift`: stabilized result filtering by removing empty and duplicate items before rendering.
  - `progress.md`: recorded this search-result stability milestone and verification limits.
- Rollback: revert this progress entry and the corresponding change in `SourceReadSwift/Features/Discover/DiscoverView.swift`, or revert the commit that contains this milestone.

## 2026-06-25 - Task: Reader source switch and source-check feedback

### What was done
- Connected the reader source-switch callback through `ChapterLoadingView` so the in-reader source switch action opens the bookshelf source switcher instead of remaining a dead branch.
- Added haptic feedback to source-switch and batch source-check entry points.
- Added a visible PASS/WARN/FAIL summary row to the batch source-check sheet so users can quickly see whether enabled sources are usable.

### Testing
- Ran `git diff --check`; it passed with only the existing Windows LF-to-CRLF warnings.
- Reviewed the reader path to confirm `BookshelfReaderGatewayView` now passes `onRequestSourceSwitch` into `ChapterLoadingView`, which forwards it to `ReaderView`.
- Reviewed the batch-check path to confirm summary counts derive from the existing persisted result list and do not change network/check execution behavior.
- Windows cannot compile or launch the iOS app locally; final runtime verification still requires Xcode or GitHub Actions when this milestone is ready to package.

### Notes
- Changed files:
  - `SourceReadSwift/Features/Discover/BookDetailView.swift`: added the missing source-switch callback parameter to `ChapterLoadingView`.
  - `SourceReadSwift/Features/Bookshelf/BookshelfReaderGatewayView.swift`: wired the reader source-switch action to the existing bookshelf source switcher.
  - `SourceReadSwift/Features/SourceManager/SourceManagerView.swift`: improved batch-check feedback with haptics and PASS/WARN/FAIL summary counts.
  - `progress.md`: recorded this reader/source-check usability fix and verification limits.
- Rollback: revert this progress entry and the corresponding changes in `SourceReadSwift/Features/Discover/BookDetailView.swift`, `SourceReadSwift/Features/Bookshelf/BookshelfReaderGatewayView.swift`, and `SourceReadSwift/Features/SourceManager/SourceManagerView.swift`, or revert the commit that contains this milestone.

## 2026-06-25 - Task: Chapter loading feedback and recovery

### What was done
- Replaced the bare chapter-loading spinner with a loading state that shows the current chapter title.
- Added recovery actions when正文 loading fails: retry the current chapter and, when available, switch source from the reader path.
- Kept the engine and network behavior unchanged; this only improves visible feedback and recovery from the reading flow.

### Testing
- Ran `git diff --check`; it passed with only the existing Windows LF-to-CRLF warnings.
- Reviewed the loading path to confirm retry clears the previous error via `load(force: true)` before requesting content again.
- Reviewed the source-switch path to confirm it reuses the source switch callback connected in the previous milestone.
- Windows cannot compile or launch the iOS app locally; final runtime verification still requires Xcode or GitHub Actions when this milestone is ready to package.

### Notes
- Changed files:
  - `SourceReadSwift/Features/Discover/BookDetailView.swift`: added a richer chapter loading state and failure recovery actions.
  - `progress.md`: recorded this chapter-loading UX fix and verification limits.
- Rollback: revert this progress entry and the corresponding changes in `SourceReadSwift/Features/Discover/BookDetailView.swift`, or revert the commit that contains this milestone.

## 2026-06-25 - Task: Search and chapter entry tap feedback

### What was done
- Added light haptic feedback when opening a search result detail page.
- Added light haptic feedback when opening a chapter from the book detail directory.
- Kept navigation behavior unchanged; this only improves the perceived response of existing entry points.

### Testing
- Ran `git diff --check`; it passed with only the existing Windows LF-to-CRLF warnings.
- Reviewed both `NavigationLink` entry points to confirm the haptic runs alongside the existing navigation instead of replacing it.
- Windows cannot compile or launch the iOS app locally; final runtime verification still requires Xcode or GitHub Actions when this milestone is ready to package.

### Notes
- Changed files:
  - `SourceReadSwift/Features/Discover/DiscoverView.swift`: added tap feedback to search-result navigation.
  - `SourceReadSwift/Features/Discover/BookDetailView.swift`: added tap feedback to chapter navigation.
  - `progress.md`: recorded this interaction polish and verification limits.
- Rollback: revert this progress entry and the corresponding changes in `SourceReadSwift/Features/Discover/DiscoverView.swift` and `SourceReadSwift/Features/Discover/BookDetailView.swift`, or revert the commit that contains this milestone.

## 2026-06-25 - Task: Local import picker reliability

### What was done
- Changed the shared document picker to pass both explicit file types and broad fallback types when opening all files, instead of relying only on `.item`.
- Added visible empty-selection errors for local book import and source JSON import so picker failures do not silently disappear.
- Kept parsing behavior unchanged; this only improves system file-picker compatibility and user feedback.

### Testing
- Ran `git diff --check`; it passed with only the existing Windows LF-to-CRLF warnings.
- Reviewed both import callers to confirm the shared picker change applies to bookshelf imports and source imports.
- Windows cannot compile or launch the iOS app locally; final runtime verification still requires Xcode or GitHub Actions when this milestone is ready to package.

### Notes
- Changed files:
  - `SourceReadSwift/Shared/Import/UniversalDocumentPicker.swift`: uses explicit requested file types plus broad fallback types for all-file picking.
  - `SourceReadSwift/Features/Bookshelf/BookshelfView.swift`: reports an empty local-book selection instead of returning silently.
  - `SourceReadSwift/Features/SourceManager/SourceManagerView.swift`: reports an empty source-file selection instead of returning silently.
  - `progress.md`: recorded this import-picker reliability fix and verification limits.
- Rollback: revert this progress entry and the corresponding changes in `SourceReadSwift/Shared/Import/UniversalDocumentPicker.swift`, `SourceReadSwift/Features/Bookshelf/BookshelfView.swift`, and `SourceReadSwift/Features/SourceManager/SourceManagerView.swift`, or revert the commit that contains this milestone.

## 2026-06-25 - Task: Root tab switching performance

### What was done
- Replaced the hand-written root tab ZStack/drag implementation with the native paged `TabView` container.
- Kept the custom Podcasts-style glass bottom tab bar and keyboard bottom-ignore behavior.
- Confirmed the app already has `CADisableMinimumFrameDurationOnPhone` enabled, so this change targets layout/rendering overhead instead of plist configuration.

### Testing
- Ran `git diff --check`; it passed with only the existing Windows LF-to-CRLF warning.
- Reviewed the root tab structure to confirm the old manual drag state and page offset calculations were removed.
- Windows cannot compile or launch the iOS app locally; final runtime verification still requires Xcode or GitHub Actions when this milestone is ready to package.

### Notes
- Changed files:
  - `SourceReadSwift/App/RootTabView.swift`: switched the root host to native paged `TabView` while preserving the custom tab chrome.
  - `progress.md`: recorded this root-tab performance fix and verification limits.
- Rollback: revert this progress entry and the corresponding change in `SourceReadSwift/App/RootTabView.swift`, or revert the commit that contains this milestone.

## 2026-06-25 - Task: Reader appearance live effect reliability

### What was done
- Added line-spacing control directly to the appearance panel so the most visible reading layout changes are available in one place.
- Clamped the active reader page/paragraph target after appearance/layout changes so paged and cover modes do not keep an invalid page selection after recalculating layout.
- Kept the existing reader settings keys and rendering pipeline unchanged.

### Testing
- Ran `git diff --check`; it passed with only the existing Windows LF-to-CRLF warning.
- Reviewed the reader appearance path to confirm font size, line spacing, background, and reader mode all participate in `readerLayoutKey`.
- Windows cannot compile or launch the iOS app locally; final runtime verification still requires Xcode or GitHub Actions when this milestone is ready to package.

### Notes
- Changed files:
  - `SourceReadSwift/Features/Reader/ReaderView.swift`: added line spacing to appearance and clamps active reading target after layout changes.
  - `progress.md`: recorded this reader appearance reliability fix and verification limits.
- Rollback: revert this progress entry and the corresponding change in `SourceReadSwift/Features/Reader/ReaderView.swift`, or revert the commit that contains this milestone.
## 2026-06-27 - Task: Swift v2 product hardening pass

### What was done
- Kept the native Swift rebuild on branch `codex/swift-v2-lifetime-reader` and continued from the Flutter parity baseline instead of restarting.
- Changed root tab hosting to a persistent indexed shell with lightweight end-of-drag tab swiping. This keeps the three main pages alive, avoids keyboard/page-TabView conflicts, and preserves the custom Podcasts-style glass tab bar.
- Added confirmation before adding search results to the bookshelf. Opening a search result now previews details/reading first; after returning from a chapter preview, the detail page prompts whether to add the book.
- Cleared update badges when a bookshelf book is opened, and changed the hero action icon away from a playback-style symbol.
- Made reader chrome prefer a matching light/dark system scheme from the selected reader background so status/system chrome follows the reading background.
- Added batch source deep-check mode: after search succeeds, batch diagnostics can verify the first result through detail, table of contents, and content parsing.
- Reduced default source request timeout from 20 seconds to 12 seconds to reduce stuck refresh/search behavior on bad sources.
- Made Settings use the shared theme-aware page background modifier so global appearance changes redraw consistently.
- Added legacy Legado JSON field normalization in `BookSource`: old `ruleSearchUrl`, `ruleSearchList`, `ruleBookName`, `ruleChapterList`, `ruleContentUrl`, `ruleBookContent`, `ruleBookContentReplace`, `ruleFind*`, JSON-string rule objects, `name/url/group`, `serialNumber/customOrder`, and `y/n/enable/disable` booleans now map into the Swift engine's modern model fields.
- Added `httpUserAgent` as a User-Agent alias in request building.
- Added unit-test coverage for legacy Legado field decoding, JSON-string rule decoding, and structured `ruleBookContent` preservation.

### Testing
- Ran `git diff --check`; it passed with only Windows LF-to-CRLF warnings.
- Parsed `SourceReadSwift/App/Info.plist` with Python `plistlib` and confirmed `CADisableMinimumFrameDurationOnPhone` is enabled and local-network permission text is valid UTF-8.
- Windows cannot compile or run iOS locally; final verification still requires GitHub Actions/Xcode/iPhone when this milestone is ready to package.

### Notes
- Do not commit unrelated `ci-log/run-27952116519/`.
- This is still an in-progress hardening milestone; no push has been made for this pass yet.

## 2026-06-27 - Task: Swift v2 morning IPA test node hardening

### What was done
- Fixed a core source-chain gap where legacy sources can expose a separate table-of-contents URL. `BookDetail` now carries `tocUrl`, detail parsing reads `tocUrl/chapterUrl/catalogUrl/chapterListUrl`, and chapter-list loading uses that URL before falling back to the detail URL.
- Added parser support for Legado-style `init` rules across search, detail, chapter list, and content parsing. This lets rules crop to the intended container before extracting list/detail/content fields instead of scraping the whole response.
- Made URL directive charset options effective. Converted legacy URLs such as `|charset=gbk` now feed `expectedCharset`, improving GBK source search/detail decoding.
- Changed the root tab swipe gesture and reader tap/cover gestures to simultaneous gestures so they no longer monopolize ScrollView and button interaction.
- Added a reader page-block cache keyed by content and layout settings, reducing repeated long-chapter pagination work during overlay/settings/progress redraws.
- Changed bookshelf refresh from fully serial source checks to four-wide concurrent batches, reducing the "pull to refresh never returns" feeling when one source is slow or broken.
- Broadened explicit local import UTTypes for TXT/TEXT/EPUB and JSON/TXT/TEXT to improve iOS document picker behavior for files received from QQ/WeChat or other share providers.
- Updated Web 写源 local-network display to list all available IPv4 addresses plus loopback, instead of guessing a single interface. This makes the page easier to find when Wi-Fi, hotspot, or virtual adapters are involved.
- Added regression tests for detail `tocUrl`, chapter-list URL selection, `init` parsing, URL directive charset, and legacy source-field normalization.

### Testing
- Ran `git diff --check`; it passed with only Windows LF-to-CRLF warnings.
- Confirmed `SourceReadSwift/App/Info.plist` still enables `CADisableMinimumFrameDurationOnPhone`, keeps local-network permission text, and declares document types.
- Confirmed this Windows host still has no local `swift`, `xcodebuild`, or `xcodegen`, so compile/runtime validation must be performed by GitHub Actions/Xcode/iPhone.

### Notes
- Changed files include source engine/model/rule/network layers, bookshelf/discover/reader/source-manager UI, tests, and parity docs.
- Do not commit unrelated `ci-log/run-27952116519/`.
- Rollback: revert this progress entry and the commit that contains the Swift v2 morning IPA test-node hardening changes.

## 2026-06-27 - Task: Legacy Legado POST search placeholder fix

### What was done
- Fixed legacy `ruleSearchUrl` conversion for POST-style search bodies such as `|charset=gbk@q=searchKey&page=searchPage`.
- The converted body now keeps template placeholders as `q={{key}}&page={{page}}`, allowing `SourceRequestBuilder` to inject the actual keyword and page at request time.
- This directly addresses the failing iOS unit test and avoids real legacy sources sending literal `searchKey/searchPage` strings to search endpoints.

### Testing
- Ran `git diff --check`; it passed with only Windows LF-to-CRLF warnings.
- Used GitHub check-run annotations from run `28275717110` to confirm the failure was the literal POST body `q=searchKey&page=searchPage` instead of `q=abc&page=2`.
- Windows still has no local `swift`, `xcodebuild`, or `xcodegen`, so final compile/test verification must run through GitHub Actions.

### Notes
- Changed files:
  - `SourceReadSwift/Core/Models/BookSource.swift`: normalizes legacy POST body placeholders during old-rule URL conversion.
  - `progress.md`: records the CI red-point fix and verification limits.
- Do not commit unrelated `ci-log/run-27952116519/`.
- Rollback: revert this progress entry and the corresponding change in `SourceReadSwift/Core/Models/BookSource.swift`.

## 2026-06-27 - Task: Paged TOC and content compatibility

### What was done
- Added automatic multi-page chapter-list loading through `nextTocUrl` / `nextChapterUrl` / `nextUrl` rules. Sources with paginated catalogs no longer stop at the first catalog page.
- Added automatic multi-page chapter-content loading through `nextContentUrl`. A chapter split across multiple web pages is now fetched and merged into one `ChapterContent` result before entering the reader.
- Added loop guards and page caps to avoid infinite source loops: up to 30 TOC pages and 8 content pages per chapter request.
- Added regression coverage for both paged TOC and paged chapter content using the injected recording network client.

### Testing
- Ran `git diff --check`; it passed with only Windows LF-to-CRLF warnings.
- Confirmed the previous pushed commit `fa41e6d` passed both GitHub Actions workflows:
  - iOS run `28277189439`: success.
  - Unsigned IPA run `28277189460`: success.
- Windows still has no local `swift`, `xcodebuild`, or `xcodegen`, so this new pagination change still needs GitHub Actions after push.

### Notes
- Changed files:
  - `SourceReadSwift/Core/Engine/SourceEngine.swift`: follows and merges paged TOC/content URLs.
  - `SourceReadSwift/Core/Rules/ChapterListParser.swift`: exposes one parsed TOC page plus `nextTocUrl`.
  - `SourceReadSwiftTests/SourceEngineBodyJSTests.swift`: adds paged TOC/content regression tests.
  - `progress.md`: records this compatibility milestone.
- Do not commit unrelated `ci-log/run-27952116519/`.
- Rollback: revert this progress entry and the corresponding changes in the three Swift files above.

## 2026-06-27 - Task: Copyable source diagnostics

### What was done
- Added a copy action to the single-source diagnostic sheet so failed search/detail/TOC/content output can be copied from the device.
- Added a copy action to the batch source-check sheet, exporting keyword, checked counts, PASS/WARN/FAIL summary, source URL, and failure messages.
- Added a copy-all action to the Settings diagnostics section so recent engine/import diagnostics can be copied for debugging.

### Testing
- Ran `git diff --check`; it passed with only Windows LF-to-CRLF warnings.
- Local Windows still has no `swift`, `xcodebuild`, or `xcodegen`, so toolbar placement and pasteboard behavior need GitHub Actions plus device verification after push.

### Notes
- Changed files:
  - `SourceReadSwift/Features/SourceManager/SourceManagerView.swift`: adds copy buttons for single-source and batch source diagnostics.
  - `SourceReadSwift/Features/Settings/SettingsView.swift`: adds copy-all export for recent diagnostics.
  - `progress.md`: records this diagnostic usability fix.
- Do not commit unrelated `ci-log/run-27952116519/`.
- Rollback: revert this progress entry and the two Swift view changes above.
