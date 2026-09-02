## 2026-09-03 - Task: Legado JS bridge compatibility phase CI correction

### What was done
- Expanded the JavaScriptCore Legado bridge with `java.ajaxBytes`, `java.head`, `java.getStrResponse`, `java.getResponseCode`, `java.cacheFile`, `java.deleteFile`, `java.importScript`, digest and HMAC helpers.
- Added persistent sandbox-scoped file cache operations and preserved HEAD directives through request parsing/building.
- Added regression coverage for cache/delete, HEAD metadata, byte responses, SHA/HMAC, data-URL script imports, and HEAD request construction.
- Corrected the HMAC-SHA1 fixture expectation after CI showed CryptoKit's standard `HMAC<SHA1>` output.

### Testing
- `git diff --check` passed locally with only existing Windows LF-to-CRLF warnings.
- JavaScript prelude extracted from `JSCoreRuntime.swift` and passed `node --check`.
- GitHub Actions unsigned IPA run `33651545077` passed.
- GitHub Actions iOS build passed, but XCTest run `33651543584` failed only because the test expected a non-standard HMAC-SHA1 value; the fixture is corrected and will be rerun.
- Windows cannot run Swift/Xcode locally; Actions remains the authoritative compile/test gate.

### Rollback
- Revert the bridge commit and this progress entry together if the phase needs to be backed out.
## 2026-09-02 - Task: CI failure correction pass

### What was done
- Retrieved GitHub Actions annotations for the failed iOS run and fixed three concrete regressions: strict HTTP(S) validation for malformed search URLs, EPUB body text after a heading/`br`, and fixture resource lookup when XcodeGen flattens the resource bundle.
- Pushed the correction as `e17b7df`; unsigned IPA had already passed on the preceding build, while iOS XCTest is rerunning on the corrected head.

### Testing
- Ran `git diff --check` locally.
- Awaiting Actions verification for `e17b7df`.
## 2026-09-02 - Task: RSS cache management and settings parity phase

### What was done
- Added a visible Settings action for clearing RSS feed cache alongside chapter cache.
- Added source/article count summary for RSS cache so users can see retained offline data before clearing it.
- Kept RSS cache source-scoped and best-effort; clearing it does not affect read/favorite state.

### Testing
- Ran `git diff --check` locally.
- GitHub Actions remains the compile/test and unsigned IPA gate.
## 2026-09-02 - Task: RSS offline cache phase

### What was done
- Added `RSSFeedCacheStore` with Application Support persistence, source-scoped replacement/removal, bounded retention, and best-effort disk writes.
- RSS article lists now restore cached articles immediately, refresh in the background, save successful responses, and keep cached content visible on network failure.
- Added Codable article previews and regression coverage for reload and source-scoped deletion.

### Testing
- Ran `git diff --check` locally.
- GitHub Actions is the Swift compile/XCTest and unsigned IPA gate.
## 2026-09-02 - Task: EPUB cover and local-book metadata phase

### What was done
- Extended `LocalTextBook` with optional cover metadata and propagated it into bookshelf records.
- EPUB parser now resolves OPF cover metadata (`meta name="cover"`) and `cover-image` manifest properties, extracts the image from the ZIP, and stores a stable local cover asset under Application Support.
- Added regression coverage for cover extraction and file existence.

### Testing
- Ran `git diff --check` locally.
- EPUB JSON/XML and source changes remain gated by GitHub Actions for Swift compilation and XCTest.
## 2026-09-02 - Task: Reader automation boundary and speech queue phase

### What was done
- Added a deterministic `ReaderAutomationPolicy` so automatic scroll advances to the next chapter at the current chapter boundary when one exists, and only stops at the final chapter.
- Added a testable `ReaderSpeechQueue` used by `ReaderSpeechController`; empty paragraphs are filtered consistently and `currentParagraphIndex` now reports the segment currently spoken.
- Added CI unit coverage for in-chapter advancement, next-chapter transition, final-chapter stop, and speech queue indexing.

### Testing
- Ran `git diff --check` locally.
- Windows cannot run Swift/Xcode; GitHub Actions remains the compile/test gate.
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

## 2026-06-27 - Task: Native glass shell and MR function absorption notes

### What was done
- Promoted the frosted-glass / material visual language into the shared design system so cards, floating chrome, and future sheets can reuse one SwiftUI glass style.
- Replaced the root tab shell's opacity-based pseudo-switching with a real page-style `TabView`, improving horizontal tab swipe behavior and reducing hard visual jumps.
- Moved the bookshelf homepage further toward the Podcasts-style card carousel direction by enlarging the hero cards and applying shared glass styling to main cards and rows.
- Unified the reader top bar, bottom controls, and settings panel onto the shared glass style while preserving the existing reader actions.
- Added an MR function absorption note under `docs/`, identifying the practical features to absorb next: source debug trace, AnalyzeUrl compatibility, source locating by pattern/weight, metadata merge, and reader refresh/cache actions.

### Testing
- Ran `git diff --check`; it passed with only Windows LF-to-CRLF warnings.
- Searched for stale `readerGlassPanel`, `rootTabSwipeGesture`, and `tabContent` references; no stale references remained.
- Local Windows still has no `swift`, `xcodebuild`, or `xcodegen`, so the native UI changes need GitHub Actions and device verification after push.

### Notes
- Changed files:
  - `SourceReadSwift/Shared/DesignSystem/AppTheme.swift`: adds shared `glassPanel` and `glassCircle` styles and makes `podcastCard` use the shared material look.
  - `SourceReadSwift/App/RootTabView.swift`: uses page-style tab switching and shared glass tab chrome.
  - `SourceReadSwift/Features/Bookshelf/BookshelfView.swift`: applies shared glass styling to homepage controls, empty states, rows, and larger hero cards.
  - `SourceReadSwift/Features/Reader/ReaderView.swift`: replaces the reader-local glass helper with the shared glass style.
  - `docs/2026-06-27-mr-function-absorption.md`: records the MR features worth absorbing without copying MR UI.
  - `progress.md`: records this UI/function absorption milestone.
- Push is currently blocked by the local GitHub credential prompt being unavailable/cancelled in this Windows terminal. The local commit can still be created and pushed once credentials are available.
- Do not commit unrelated `ci-log/run-27952116519/`.
- Rollback: revert this progress entry and the Swift/doc changes listed above.

## 2026-06-27 - Task: Preserve search metadata when detail JSON is blank

### What was done
- Absorbed MR's metadata-merge behavior for the Swift JSON detail parser: blank detail fields no longer replace useful search-result metadata.
- JSON detail parsing now falls back to the search result for blank `name`, `author`, `coverUrl`, and `intro`, and ignores blank `latestChapter` / `tocUrl`.
- Added regression coverage for a detail API returning empty strings.

### Testing
- Ran `git diff --check`; it passed with only Windows LF-to-CRLF warnings.
- This change still needs GitHub Actions because local Windows has no `swift`, `xcodebuild`, or `xcodegen`.

### Notes
- Changed files:
  - `SourceReadSwift/Core/Rules/BookDetailParser.swift`: treats blank JSON detail values as missing and preserves search metadata.
  - `SourceReadSwiftTests/JSONPipelineParserTests.swift`: covers blank detail JSON fallback behavior.
  - `progress.md`: records this MR function absorption fix.
- Do not commit unrelated `ci-log/run-27952116519/`.
- Rollback: revert this progress entry and the two Swift/test changes above.

## 2026-06-27 - Task: Local product-node reader and source workflow hardening

### What was done
- Continued local-only development after the previous push. No new push or Actions run was triggered for this batch.
- Added reader callbacks for refreshing the current chapter from network and manually caching upcoming chapters.
- Added copyable chapter-load diagnostics so failed source/chapter/book URLs can be copied from the error screen.
- Added Web source-writing copy actions for the LAN server address and server logs.
- Improved Discover search keyboard handling with background tap dismissal and a keyboard Done action.
- Added source-switch candidate ordering based on `bookUrlPattern` plus `weight`, then falling back to weighted searchable sources.
- Added a concrete URL copy tool to the Web helper page so the previous explanatory-only page now has a usable source-writing handoff step.

### Testing
- Ran `git diff --check`; it passed with only Windows LF-to-CRLF warnings.
- Added unit coverage for source-switch candidate ordering by `bookUrlPattern` and `weight`.
- Local Windows still has no `swift`, `xcodebuild`, or `xcodegen`; this batch remains local and unpushed until a larger product-node pass is ready.

### Notes
- Changed files:
  - `SourceReadSwift/Features/Reader/ReaderView.swift`: exposes refresh/cache callbacks in the glass reader controls.
  - `SourceReadSwift/Features/Discover/BookDetailView.swift`: wires refresh/cache callbacks, stale-cache bypass retry, and copyable chapter diagnostics.
  - `SourceReadSwift/Features/Discover/SourceWritingView.swift`: adds copy actions for server URLs and logs.
  - `SourceReadSwift/Features/Discover/DiscoverView.swift`: adds keyboard dismissal affordances.
  - `SourceReadSwift/Core/Storage/SourceStore.swift`: adds source-switch candidate ordering by pattern and weight.
  - `SourceReadSwift/Features/Bookshelf/BookshelfReaderGatewayView.swift`: uses the ordered source-switch candidates.
  - `SourceReadSwiftTests/SourceStoreTests.swift`: covers pattern/weight source-switch ordering.
  - `progress.md`: records this local product-node hardening batch.
- Do not commit unrelated `ci-log/run-27952116519/`.
- Rollback: revert this progress entry and the files listed above.

## 2026-06-27 - Task: Local-only product-node interaction, import, reader, and source-check hardening

### What was done
- Stopped treating push/Actions as progress for this batch; this round remains local-only and is not ready to push.
- Removed stale legacy Web source-writing HTML and the unreachable duplicate return path, leaving one stable LAN import page.
- Reduced tap-feedback latency for the root tab bar and bookshelf cards to better match the existing Flutter `PressableScale` feel.
- Made bookshelf section headers consistently navigable, removed a zero-distance drag gesture that could steal `NavigationLink` taps, and added empty collection states.
- Added a direct local JSON import button in source management and increased the sheet-dismiss delay for the fallback file-picker path.
- Added shared-document content sniffing so JSON sources received as `.txt`, `.text`, no-extension, or generic data can be imported as sources instead of being misclassified as local books.
- Hardened reader smoothness by hiding the status bar during reading and defaulting paragraph text selection off, with an advanced setting to re-enable text selection when needed.
- Clarified batch source-check semantics and added timeout protection to single-source and batch deep checks for details, table of contents, and content.

### Testing
- Ran `git diff --check`; it passed with only Windows LF-to-CRLF warnings.
- Loaded `SourceReadSwift/App/Info.plist` as XML; it passed with `Info.plist XML OK`.
- Local Windows still has no `swift`, `xcodebuild`, or `xcodegen`, so compile/device behavior remains unverified until a later product-node push/Actions pass.

### Notes
- Changed files:
  - `SourceReadSwift/App/AppState.swift`: sniffs shared JSON-like files before falling back to local book import.
  - `SourceReadSwift/App/RootTabView.swift`: shortens tab press feedback animation.
  - `SourceReadSwift/Features/Bookshelf/BookshelfView.swift`: fixes section navigation consistency, removes tap-stealing drag handling, improves collection empty state, and shortens press feedback.
  - `SourceReadSwift/Features/Discover/SourceWritingView.swift`: removes stale legacy Web HTML and keeps the stable LAN source writer page.
  - `SourceReadSwift/Features/Reader/ReaderView.swift`: hides status bar during reading and adds a text-selection performance toggle.
  - `SourceReadSwift/Features/SourceManager/SourceManagerView.swift`: adds direct local JSON import, improves import-picker timing, updates batch-check copy, and adds deep-check timeouts.
  - `progress.md`: records this local-only hardening batch.
- Do not push this batch yet; it is still a local product-node hardening pass, not a release/test handoff.
- Do not commit unrelated `ci-log/run-27952116519/`.
- Rollback: revert this progress entry and the files listed above, or reset only these local hunks before the eventual product-node commit.
## 2026-09-02 - Task: Native iOS high-refresh performance foundation

### What was done
- Locked the next product phase around native iOS performance, EPUB, RSS reading, source diagnostics/rule editing, reader speech/auto-advance, and Flutter parity.
- Added `FrameRateCoordinator` to request up to 120 Hz on ProMotion windows and automatically use the device's native ceiling elsewhere.
- Re-applied frame-rate coordination when the app becomes active, so scene/window transitions do not lose the preference.
- Added `PerformanceSignpost` and instrumented reader pagination/layout work with an `os_signpost` interval for Instruments diagnosis.
- Added the phase design specification at `docs/superpowers/specs/2026-09-02-native-ios-performance-and-reader-features-design.md`.

### Testing
- Ran static diff validation locally.
- iOS compilation and runtime FPS measurement still require GitHub Actions/Xcode and a physical ProMotion device.

### Notes
- This is the first performance foundation slice; it does not claim a measured 120 FPS result yet.
- The coordinator is intentionally conservative on non-ProMotion devices and does not force unsupported refresh rates.

### CI correction
- The first CI run caught an API mismatch: `preferredFrameRateRange` belongs on `UIWindow` for this deployment/toolchain, not `UIWindowScene`.
- The coordinator now applies the `CAFrameRateRange` to every active window in the scene; this keeps the native route and restores Xcode compatibility before the next phase batch.

## 2026-09-02 - Task: Phase 1 large-batch content and performance slice

### What was done
- Kept delivery at the requested large-phase granularity instead of shipping isolated micro-fixes.
- Added an RSS article reader page: article rows now navigate into native reading, fetch the linked article, extract readable HTML paragraphs, and retain feed description fallback when the original page is unavailable.
- Added `RSSArticleContentParser` with SwiftSoup extraction for article/main/content containers and readable headings, paragraphs, lists, and blockquotes.
- Added RSS article-body regression coverage.
- Corrected the high-refresh implementation to the Xcode-supported `UIWindow.preferredFrameRateRange` API after CI caught the scene-level mismatch.

### Testing
- Ran `git diff --check` locally.
- The complete phase batch requires GitHub Actions for compile/test and unsigned IPA validation; Windows cannot run Xcode locally.

### Large-batch follow-up
- Corrected frame-rate coordination again to use the SDK-supported `CALayer.preferredFrameRateRange` path after the runner showed that neither `UIWindowScene` nor `UIWindow` exposes the property in this toolchain.
- Pushed the corrected batch as commit `91cfc1e`; new iOS and unsigned IPA runs are queued/in progress.

## 2026-09-02 - Task: RSS persistence and EPUB/content phase completion pass

### What was done
- Added persistent RSS article read/favorite state through `RSSArticleStateStore` and exposed it through `AppState`.
- RSS article rows now show read/favorite state; opening an article marks it read, and the article reader exposes a favorite toggle.
- Added regression coverage proving RSS state survives store reload from `UserDefaults`.
- Continued EPUB path compatibility coverage and retained the native reader as the shared article/content presentation route.

### Testing
- Ran `git diff --check` locally.
- Pushed the large batch as commit `192c7bc`; Actions iOS and unsigned IPA validation are running for this phase.

## 2026-09-02 - Task: Source diagnostics, rule editor, RSS media and reader lifecycle phase

### What was done
- Added a native grouped rule editor for search, detail, TOC and content rules. It keeps the original source fields, validates URL/JS/XPath input, and persists edits through the existing source JSON import path.
- Added a Legado fixture bank covering HTML, JSON, JavaScript, pagination, POST and JXNode-shaped sources, with bundle-backed decoding tests.
- RSS articles now retain their feed URL in their stable identity and extract common enclosure/media/img cover URLs for native `AsyncImage` thumbnails.
- Corrected RSS source-scoped state clearing to use the actual source identity prefix.
- Reader speech now supports pause/resume with `AVAudioSession` playback configuration; leaving the foreground pauses automatic scrolling to avoid runaway work while preserving speech state.
- EPUB parsing now tolerates books without a spine by using HTML/XHTML manifest order and recognizes headings, lists, quotes and preformatted blocks as readable paragraphs.

### Testing
- All six fixture JSON files parse successfully with PowerShell JSON validation.
- Ran `git diff --check` locally.
- Windows host has no Swift/Xcode/XcodeGen; iOS compile, unit tests and unsigned IPA remain Actions gates.

### Notes
- `FrameRateCoordinator` intentionally only records the device ceiling and relies on `CADisableMinimumFrameDurationOnPhone`; the current SDK does not expose a compile-safe frame-rate range property. Documentation must not claim a forced 120 FPS result until ProMotion hardware measurement exists.
## 2026-09-02 - Task: Lock autonomous major-phase execution plan

### What was done
- Locked the native Swift/SwiftUI route and large-phase delivery cadence in `docs/superpowers/plans/2026-09-02-next-major-phase-plan.md`.
- Added explicit phase gates: iOS build/test, unsigned IPA artifact, `git diff --check`, progress evidence, and no false completion claims while Actions are only queued.
- Fixed execution order: close current CI first, then RSS/source diagnostics, reader automation, and Flutter parity/product wrap-up.

### Testing
- Ran `git diff --check` locally.
- GitHub Actions was triggered for this documentation checkpoint; build/test and IPA conclusions remain pending until the runs finish.

### Next
- Continue autonomous work from the high-refresh/readability phase without requiring another approval checkpoint.
## 2026-09-02 - Task: RSS Atom link resolution hardening

### What was done
- Added Atom `<link>` selection that skips `self`/`enclosure` links and prefers `rel="alternate"` HTML article URLs.
- Added relative URL resolution against the feed URL for RSS and Atom entries.
- Added regression tests for alternate-link priority and relative RSS links.

### Testing
- Ran `git diff --check` locally.
- Xcode/XCTest remain delegated to GitHub Actions on the Windows host.

### Next
- Continue the RSS/source diagnostic large phase after the new Actions run reports.
## 2026-09-02 - Task: RSS cache and failure-recovery hardening

### What was done
- Added persistent RSS article-body cache with bounded entries and seven-day freshness policy.
- RSS article reader now renders fresh cached paragraphs immediately, refreshes from network, and keeps cached content on transient failures.
- Added retry action for feeds that fail before producing any articles; valid empty feeds remain distinct from network errors.
- RSS feed cache decoding now honors ISO-8601 dates consistently.
- Settings RSS cleanup now clears both feed metadata and article-body caches.
- Added persistence/removal regression tests for article-body cache.

### Testing
- Ran `git diff --check` locally.
- GitHub Actions remains the compile/XCTest/unsigned-IPA gate for this Windows-only workspace.

### Rollback
- Revert the RSS cache/retry commit and this progress entry together.
## 2026-09-02 - Task: Source diagnostic timing visibility

### What was done
- Extended the single-source diagnostic chain to report per-stage elapsed time for search, detail, table of contents, and content.
- Kept the existing full chain and timeout boundaries intact; timing is appended to PASS lines without changing source execution semantics.

### Testing
- Ran `git diff --check` locally.
- iOS compile/XCTest and unsigned IPA remain GitHub Actions gates.
## 2026-09-02 - Task: Legado JS bridge diagnostics visibility

### What was done
- Wired `RuleExecutionContext` JS log callbacks into the app diagnostic sink for search, detail, TOC and content stages.
- JS/runtime failures and bridge messages now appear in the existing diagnostics stream with stage labels, while response observations remain sanitized (status, bytes, content type, cookie presence only).

### Testing
- Ran `git diff --check` locally.
- GitHub Actions remains the authoritative Swift compile/XCTest/unsigned-IPA gate.
## 2026-09-02 - Task: RSS HTTP status handling

### What was done
- RSS feed and article requests now treat non-2xx/3xx HTTP responses as failures instead of parsing error pages as valid content.
- Existing cache fallback and retry UI therefore activate for server errors while successful empty feeds remain distinguishable.

### Testing
- Ran `git diff --check` locally.
- Swift compile/XCTest and unsigned IPA remain pending GitHub Actions verification.

## 2026-09-02 - Task: ProMotion frame-rate and root-tree performance phase

### What was done
- Applied a scene-level `CAFrameRateRange` of 60...120 Hz on iOS 15+ and re-applied it on scene activation, while retaining `CADisableMinimumFrameDurationOnPhone` for ProMotion eligibility.
- Replaced the opacity-based root tab stack with an active-tab-only view tree. The prior implementation kept three complete `NavigationStack` hierarchies alive and rendered them every update, a direct source of dropped frames on long shelves and discovery lists.
- Kept the range adaptive: 60 Hz devices are not asked for an unsupported rate, and iOS can still downshift under thermal/idle conditions.

### Testing
- `git diff --check` passes locally.
- Windows host has no Swift/Xcode; compile, XCTest and unsigned IPA remain GitHub Actions gates.
- A real 120 Hz claim still requires ProMotion hardware/Instruments evidence; this change only establishes the native request and removes avoidable SwiftUI work.

### Rollback
- Revert this phase commit to restore the previous root tab stack and scene frame-rate behavior.

## 2026-09-02 - Task: Reader speech lifecycle and cross-chapter handoff phase

### What was done
- Completed the pending reader speech handoff slice for both remote source books and local multi-chapter books: when the current chapter finishes, the owner advances to the next chapter and persists the new reading position.
- Added foreground/background lifecycle handling so speech pauses only when the scene caused the pause, then resumes on return; automatic scrolling is stopped while inactive to prevent runaway work.
- Routed speech completion back through the main actor and reset lifecycle state when switching reader modes or starting automatic scroll, avoiding stale callbacks and mixed playback modes.
- Applied the SDK-compatible `CALayer.preferredFrameRateRange` ProMotion request from the recovered CI correction commit; the earlier `UIWindowScene` API is no longer present.

### Testing
- Ran `git diff --check` locally.
- Windows host has no Swift/Xcode; compile, XCTest, and unsigned IPA remain GitHub Actions gates.
- The latest unsigned-IPA run for `8d7fbc5` exposed the obsolete `UIWindowScene.preferredFrameRateRange` API; this phase includes the layer-based correction and must be re-run in Actions before claiming build success.

### Rollback
- Revert the phase commit to restore the prior speech lifecycle behavior and frame-rate coordinator implementation.

## 2026-09-03 - Task: Reader automation state machine and high-refresh hot-path phase

### What was done

- Added a generation-based `ReaderPlaybackStateMachine`/coordinator shared by auto-scroll and speech. Stale timers and speech completion callbacks are now rejected after a mode switch, stop, scene transition, or chapter handoff.
- Made speech chapter handoff actually continue playback: source-backed and local multi-chapter readers now request one-shot speech autoplay after the next chapter content appears.
- Kept speech, auto-scroll, scene lifecycle, and reader-mode transitions mutually exclusive; stopping speech clears queued completion callbacks and stale queue state.
- Debounced reading-position persistence from page/scroll target changes so bookshelf JSON serialization is removed from the immediate paging/auto-scroll hot path.
- Prevented duplicate chapter preload workers and cancel them when the chapter reader disappears, reducing competing network/cache work during navigation.

### Testing

- `git diff --check` passes locally.
- Added deterministic XCTest coverage for playback generation invalidation and speech pause/resume transitions.
- Windows host has no Swift/Xcode; iOS compile, XCTest, and unsigned IPA remain GitHub Actions gates.
- Actual ProMotion frame pacing still requires iPhone Pro/Instruments evidence; CI cannot prove sustained 120 FPS.

### Follow-up stability fix

- Reader content views now receive a chapter URL identity, guaranteeing SwiftUI tears down the prior speech/scroll session before rendering a handed-off chapter. This prevents stale `ReaderView` state from surviving a remote chapter transition.

### Verification update

- Commit `0b0c5b1` pushed to `codex/swift-v2-lifetime-reader`.
- iOS Actions run `33654845722`: completed `success` (XCTest/build).
- Unsigned IPA Actions run `33654845696`: completed `success`; artifact `SourceReadSwift-unsigned-ipa` is present and not expired (5,383,325 bytes).

### Rollback

- Revert this phase commit to restore the previous reader automation, persistence timing, and preload behavior.

## 2026-09-03 - Task: Flutter parity bookshelf groups and search filtering phase

### What was done
- Added native search-result filtering parity: all/title/author/source scopes, local filtering without re-running network search, and accessible placeholder text.
- Added persistent bookshelf groups with create/delete, group chips, per-book move actions, and safe ungrouping when a group is deleted.
- Added XCTest coverage for case/diacritic-insensitive result filtering and group persistence/move/delete behavior.

### Testing
- `git diff --check` passed locally (Windows only reports existing LF-to-CRLF normalization warnings).
- Swift/Xcode compilation and XCTest remain delegated to GitHub Actions; this Windows host has no `swift`, `xcodebuild`, or `xcodegen`.
- ProMotion frame pacing still requires a real iPhone Pro/Instruments run; this phase does not claim sustained 120 FPS.

### Rollback
- Revert the phase commit and remove `BookshelfGroupPersistence.swift` / `SearchResultFilter.swift` plus their tests.

### CI verification update
- Commit `4a5ad8a` pushed to `codex/swift-v2-lifetime-reader`.
- iOS build/XCTest Actions run `33657844603`: `Success`.
- Unsigned IPA Actions run `33657844854`: `Success`; artifact `SourceReadSwift-unsigned-ipa`, 5.2 MB, SHA-256 `a79c6c7b252e25f071d752bc9bc07b663189615f61f41e8158a355c15b5b0a9f`.
## 2026-09-03 - Task: Source diagnosis classification and native login phase

### What was done
- Expanded persisted source health states beyond pass/warn/fail: `requiresLogin`, `verificationRequired`, and `blocked`.
- Added deterministic `SourceDiagnosticClassifier` so batch checks distinguish authentication, challenge/CAPTCHA, access-block/rate-limit, timeout, empty-result, and generic failures.
- Batch source diagnostics now show/export the additional categories and persist the classified status for each source.
- Exposed one shared `SourceCookieStore` from `AppState` and injected it into the Legado engine, preventing login cookies from being isolated from subsequent URLSession requests.
- Added a native `SourceLoginView` with `WKWebView` login/verification flow; cookies are synchronized into the shared source engine cookie store after page navigation.
- Added XCTest coverage for deterministic login/verification/block classification.

### Testing
- `git diff --check` passed locally (Windows reports only existing LF-to-CRLF normalization warnings).
- Windows host has no Swift/Xcode/XcodeGen; iOS compile, XCTest, and unsigned IPA remain GitHub Actions gates.
- This phase does not claim login success against any external source; the app-side WebView-to-cookie handoff is covered by code path and the classifier by unit tests.

### Rollback
- Revert this phase commit to restore the previous three-state source health model, isolated engine cookie store, and source manager behavior.
## 2026-09-03 - Task: Source login verification, diagnostic history and RSS editor phase (in progress)

### Scope
- Added persistent, source-scoped diagnostic history with stage, status, timing, result count and bounded retention.
- Added a native diagnostic-history sheet with copy/clear actions.
- Added `SourceEngine.verifyLogin` and Legado `loginCheckJs` execution using the shared Cookie store; login/verification/block results now participate in source tests and batch checks.
- Added RSS source editor parity for feed URL, list/content rules, pagination, media fields, CSS and enable/Cookie settings.

### Testing
- `git diff --check` passed locally; Windows reports only existing LF-to-CRLF normalization warnings.
- Swift/Xcode compilation, XCTest and unsigned IPA are pending GitHub Actions after this phase commit.
- Windows cannot prove iOS runtime behavior or sustained 120 Hz; ProMotion validation remains a real-device/Instruments task.

### Rollback
- Revert this phase commit to remove login verification, diagnostic history and RSS editor changes while preserving the prior source health model and login WebView.

### CI verification update

- Commit `c54d8ef` pushed to `codex/swift-v2-lifetime-reader`.
- iOS build/XCTest Actions run `33662965147`: `success`.
- Unsigned IPA Actions run `33662965213`: `success`; the workflow page reports the `SourceReadSwift-unsigned-ipa` artifact. Artifact bytes/hash were not available from the Windows host because the GitHub API was rate-limited, so no size or SHA-256 is claimed here.
- This closes the compile/test gate for the phase; external-source login behavior and sustained ProMotion 120 Hz still require device/network evidence.
## 2026-09-03 - Task: Flutter parity offline recovery and reader data management phase

### Scope
- Added a native all-books bookmark page with chapter/paragraph locations, snippets, swipe-to-delete, and direct jump into the existing reader gateway.
- Added an offline chapter cache browser with source/book grouping, byte/count summaries and single-entry deletion; this exposes the stale-cache recovery path instead of hiding it inside the reader.
- Expanded book detail parity with mark-as-read, refresh catalog, ascending/descending order, full-catalog sheet, and cancellable whole-book chapter caching with progress state.
- Added portable bookshelf backup/restore through the iOS document picker. The JSON contains bookshelf books, progress, bookmarks and groups only; cookies, login sessions and credentials remain excluded.
- Added deterministic store/cache regression coverage for backup round-trip, unknown-group normalization, single-entry cache deletion and book filtering.

### Testing
- `git diff --check` passed locally; Windows only reports the repository's existing LF-to-CRLF normalization warnings.
- Swift/Xcode compilation, XCTest and unsigned IPA are pending the GitHub Actions gate for the phase commit.
- Windows cannot validate document-picker presentation, reader jump animation, external source downloads or sustained ProMotion frame pacing; those remain device/Actions evidence items.

### Rollback
- Revert the phase commit to remove the bookmark/offline-management views, backup/restore APIs, cache-management APIs and book-detail download controls while preserving the previous source/reader engine.

## 2026-09-03 - Task: iOS 16 CI compatibility closure

### Scope
- Replaced the iOS 17-only `ContentUnavailableView` in source diagnostic history with an iOS 16-compatible empty state.
- Corrected `SettingsView` to use the Xcode/iOS 16-compatible non-optional `fileExporter` overload.
- Removed the CI-incompatible `CALayer.preferredFrameRateRange` call; high-refresh remains enabled through `CADisableMinimumFrameDurationOnPhone` while UIKit/SwiftUI selects the device-supported cadence.

### CI verification
- Commit `3cdac84` pushed to `codex/swift-v2-lifetime-reader`.
- iOS build/XCTest Actions run `33667244188`: success.
- Unsigned IPA Actions run `33667244128`: success; artifact `SourceReadSwift-unsigned-ipa` produced.

### Unverified
- Windows host cannot run Xcode or XCTest locally.
- Sustained 120 Hz still requires ProMotion hardware/Instruments; this phase only proves the app no longer imposes a 60 Hz floor.

### Rollback
- Revert commits `3cdac84` and `36cee2a` to restore the previous exporter, empty-state and frame-rate implementation.

## 2026-09-03 - Task: RSS embedded content and EPUB navigation hardening phase

### Scope
- Added `RSSArticlePreview.contentHTML` with backward-compatible Codable decoding for older feed caches.
- RSS parser now preserves `content:encoded`/`content` HTML separately from the plain-text summary and recognizes Atom/Dublin Core `dc:date`.
- RSS article cache stores embedded HTML when available; the reader renders cached/feed-provided HTML-derived paragraphs before remote-page fallback and still keeps the existing description fallback.
- EPUB parser now accepts single-quoted or case-variant `container.xml` paths and reads EPUB3 navigation/NCX labels to provide stable chapter titles even when XHTML headings differ.
- Added RSS and EPUB regression fixtures for embedded HTML, legacy Codable data, `dc:date`, and EPUB3 navigation labels.

### Testing
- `git diff --check` passed locally (Windows reports only existing LF-to-CRLF normalization warnings).
- Windows host cannot run Swift/Xcode; iOS build/XCTest and unsigned IPA remain GitHub Actions gates.
- Sustained 120 Hz still requires ProMotion hardware/Instruments evidence; this phase does not claim a measured frame rate.

### Rollback
- Revert the phase commit and this entry to restore the prior RSS preview/cache schema and EPUB chapter-title behavior; old cache files remain readable because new fields are optional.

### CI verification update

- Commit `298021d` pushed to `codex/swift-v2-lifetime-reader`.
- iOS Build/XCTest run `33668904541`: completed successfully.
- Unsigned IPA run `33668904593`: completed successfully; artifact `SourceReadSwift-unsigned-ipa`, 5.46 MB, SHA-256 `a785861066f95383b10b4d38e2130efd4bfa2239322d5ef88797aa2fd15f360b`.
- Sustained 120 Hz and external RSS/EPUB source behavior remain device/network validation items.

## 2026-09-03 - Task: Legado JS compatibility surface expansion phase

### Scope
- Expanded the native JavaScriptCore bridge with Flutter/Legado utility aliases: `getStr`, `getJson`, `putJson`, `postForm`, byte/Base64/Hex conversion and charset-aware Java String bytes.
- Added native byte-oriented digest/HMAC bridges so non-ASCII UTF-8 source rules do not pass through lossy `String.fromCharCode` conversion.
- Added Java/Android facade coverage for URL resolution, `MessageDigest`, `Mac/SecretKeySpec`, `ByteArrayInputStream`, collections, regex and source/book/chapter getter aliases.
- Added `docs/legado-js-compatibility-matrix.md` and XCTest coverage for relative URLs, non-ASCII crypto, charset-aware strings and form requests.

### Testing
- `git diff --check` passed locally; JavaScript prelude passed `node --check`.
- Initial Actions runs for `ee03ec6` and follow-up fixes exposed Swift multiline-string escape errors in the JSONPath/URL regex literals (`33671765317`, `33671765324`, `33672567894`, `33673404489`). Those literals were replaced with escape-free parsing logic; commit `fc1c596` is the current CI candidate.
- Swift/Xcode compilation, XCTest and unsigned IPA for `fc1c596` are pending GitHub Actions; GitHub REST polling is rate-limited on the Windows host, so the workflow page is the evidence source.
- Windows cannot validate JavaScriptCore runtime ABI on iOS or sustained ProMotion pacing; those remain Actions/device evidence items.

### Rollback
- Revert commits `ee03ec6` through `fc1c596` to restore the prior JS bridge while preserving the previously shipped RSS/EPUB phase.

### CI correction update

- Commit `a3e6bc4` pushed after iOS JavaScriptCore annotations showed `ReferenceError: Can't find variable: java` during bridge tests.
- Root cause was unsafe fresh-context namespace initialization (`var java = java || {}` and the same pattern for `cookie`, `CryptoJS`, and `Packages`); JavaScriptCore evaluates the undeclared right-hand identifier differently from a browser/Node environment.
- Replaced those initializers with `typeof`-guarded conditional initialization so a clean JSContext creates the Legado namespaces before installing helper methods.
- iOS build/XCTest run `33679123051`: success. Unsigned IPA run `33679122964`: still pending at the time of this update.
