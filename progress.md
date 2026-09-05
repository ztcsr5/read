## 2026-09-04 - Stage 7: Legado response and Java regex compatibility hardening

### Implemented

- Extended the JavaScriptCore response bridge with byte-oriented bodies (`bytes`, `byteArray`, `length`), case-insensitive header map operations (`get`, `has`, `keys`, `values`, `entries`, `toJSON`) and parsed cookie access (`cookies().get/containsKey`).
- Hardened Set-Cookie parsing so commas inside `Expires=...` do not split the cookie pair list.
- Expanded Java regex `Pattern` compatibility with standard flag constants, `reset`, `region`, `lookingAt`, static group counting and capture offsets backed by `RegExp` indices when available.
- Scoped matcher `find()` to the active region and added repeated-capture offset regression coverage.
- Added Jsoup document metadata, absolute resource URL, response header/cookie facade and UTF-8 byte-length fixtures.

### Verification

- Extracted the Swift multiline prelude with Swift escape decoding and passed `node --check`.
- Ran deterministic Node harnesses for Pattern matching, repeated capture offsets, response headers/cookies and body bytes.
- `git diff --check` passes with only the repository's existing Windows LF-to-CRLF normalization warnings.
- Windows cannot run Swift/Xcode/UIKit/XCTest; GitHub Actions remains the authoritative compile/test and unsigned-IPA gate.

### Next

- Commit and push this Stage 7 pass once, wait for both Actions workflows, inspect annotations and the unsigned IPA artifact, then continue with higher-risk Legado fixtures (dynamic cookie/token chains, mixed JSON/HTML responses and paginated source rules).

### CI closure

- Initial Stage 7 run `33873914088` caught a malformed nested-quote Jsoup fixture; the bridge itself built and the unsigned IPA run `33873914093` passed.
- Fixture correction commit: `db23917`.
- iOS build/XCTest: [run 33874608533](https://github.com/ztcsr5/read/actions/runs/33874608533) — success.
- Unsigned IPA: [run 33874608530](https://github.com/ztcsr5/read/actions/runs/33874608530) — success; artifact `SourceReadSwift-unsigned-ipa` (6,190,173 bytes, artifact id `9937425550`). The artifact download endpoint requires GitHub authentication from this Windows session, so no SHA-256 is reported.

### Rollback

- Revert the single Stage 7 bridge/test commit and this progress entry to restore the prior response facade and matcher behavior.

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
## 2026-09-03 - Task: Legado JS bridge namespace parse correction (CI rerun pending)

### What was done
- Replaced the remaining `var namespace = namespace || {}` declarations in the JavaScriptCore prelude with `typeof`-guarded assignments.
- This avoids JavaScriptCore's declaration/hoisting interaction on a fresh `JSContext`, which was still surfacing as `SyntaxError: Unexpected EOF` in the bridge XCTest suite despite Node syntax validation passing.

### Testing
- `git diff --check` passed locally (Windows reports only existing LF-to-CRLF normalization warnings).
- GitHub Actions has been triggered by commit `cbafada`; iOS XCTest must reach success before Stage 2A is accepted. Unsigned IPA remains a separate gate.
- Windows cannot run Swift/Xcode or prove JavaScriptCore runtime behavior; sustained 120 Hz still requires ProMotion device/Instruments evidence.

### Rollback
- Revert commit `cbafada` to restore the previous prelude namespace declarations.
## 2026-09-03 - Task: Legado JSCore prelude EOF root-cause and bridge follow-up (CI pending)

### What was done
- Found the JavaScriptCore-only `Unexpected EOF` root cause: a Swift multiline string contained `join('\n')`, which Swift materialized as a literal newline inside a JavaScript string. Escaped it as `join('\\n')`.
- The next Actions run no longer reports the prelude EOF; remaining failures were real bridge-contract gaps.
- Added native `BookChapter` getter aliases (`getName`, `getTitle`, `getUrl`, `getChapterUrl`, `getIndex`, `getChapterIndex`) and normalized the injected chapter object path.
- Stabilized the post-form test by collecting request envelopes outside the response callback, then asserting body/header behavior after evaluation.

### Testing
- `git diff --check` passes locally.
- Prior CI run `33692282545` confirms the EOF failure is gone; it now reaches two focused bridge assertions instead.
- Commit `c206f9e` is pushed and has fresh iOS/unsigned-IPA Actions running. Do not claim Stage 2A complete until iOS XCTest is green.

### Rollback
- Revert `c206f9e` and the preceding `ff96716`/`cbafada` correction commits to restore the prior bridge behavior.

## 2026-09-03 - Task: Stage 2A closure and Stage 2B source pipeline kickoff

### Stage 2A CI closure

- Commit `cd5ba53` is the current branch head and is synchronized to `origin/codex/swift-v2-lifetime-reader`.
- iOS build/XCTest run `33694888232`: success.
- Unsigned IPA run `33694888231`: success; artifact `SourceReadSwift-unsigned-ipa`, 5,764,868 bytes.
- This closes Stage 2A. The JavaScriptCore prelude, Legado namespace initialization, chapter aliases and POST form bridge now have a green CI gate.

### Stage 2B implementation started

- Added deterministic end-to-end fixture coverage for HTML, JSON, JS, POST, paginated TOC/content, JXNode, headers/cookie/status and failure diagnostics in `SourceReadSwiftTests/SourceEngineFixturePipelineTests.swift`.
- Added four-stage rule editor JSON round-trip, preview coverage and malformed JSON/JavaScript validation tests in `SourceReadSwiftTests/RuleEditorRoundTripTests.swift`.
- Extended `RuleEditorValidator` to validate structured rule JSON and JavaScript syntax before save.
- Extended `JSONRuleExtractor.list` to decode `JSON.stringify(...)` results returned by JavaScriptCore, a common Legado JS `bookList` pattern.

### Testing

- `git diff --check` passes locally; Windows reports only existing LF-to-CRLF normalization warnings.
- Swift/Xcode compilation and XCTest for Stage 2B are pending the unified phase commit and GitHub Actions.
- No real external source is contacted by the new tests. Sustained ProMotion 120 Hz remains a device/Instruments evidence item.

### Rollback

- Revert the Stage 2B phase commit to remove the new fixture pipeline, rule-editor test coverage, validator syntax checks and JSON-stringified JS list compatibility while preserving the green Stage 2A bridge.

## 2026-09-03 - Stage 2B closure and Stage 2C kickoff

### Stage 2B CI closure

- Commit `687761a` is synchronized to `origin/codex/swift-v2-lifetime-reader`.
- iOS/XCTest run `33702800984`: success.
- Unsigned IPA run `33702801020`: success; artifact `SourceReadSwift-unsigned-ipa` produced.
- Stage 2B is closed: deterministic source pipeline fixtures and rule-editor round-trip/syntax validation now have a dual CI gate.

### Stage 2C kickoff

- Next major phase targets broader Legado/开源阅读 source compatibility rather than isolated fixtures.
- Work will expand JSONPath/template semantics, HTML selector operators and JS bridge parity while keeping all verification on local fixtures.
- Real-world source URLs remain outside automated tests; compatibility is proven with sanitized/local fixtures and GitHub Actions.

### Rollback

- Revert `99684f6..687761a` to remove Stage 2B fixture/editor additions while preserving Stage 2A JavaScriptCore bridge closure.

## 2026-09-03 - Stage 2C reader polish and portable data backup

### Implemented

- Added a versioned `AppDataBackupSnapshot` covering bookshelf/groups, book/RSS/catalog sources, purification rules, RSS read/favorite state and typed reader preferences.
- Added backward-compatible import for legacy bookshelf-only JSON and XCTest coverage for typed preference encoding, full snapshot round-trip, source-library restore and RSS state restore.
- Removed duplicate local JSON button from the source status card; local file import remains in the unified import sheet.
- Added explicit Web 写源 health URLs (`/health`), copy action and LAN troubleshooting text; enabled local endpoint reuse and peer-to-peer networking on the listener.
- Added a visible “批量管理” entry beside the bookshelf section header and unified Discover's top shell with the large-title treatment from the reference UI.
- Fixed JSONPath normalization regression for `$.data.book@name` while retaining recursive descent/filter predicates.

### CI

- Commit `377dc5f` exposed a compile gate because `SourceLibrarySnapshot` was not hashable; fixed in `8f050ca`.
- iOS and unsigned-IPA workflows for `8f050ca` are running. Do not mark this phase green until both complete.

### Remaining Stage 2C work

- Productize smart web-novel mode or remove it from the primary search flow.
- Finish source visual test/detail UX and batch operations for RSS/catalogs.
- Continue reader rendering profiling and validate actual 120 Hz on a ProMotion device; CI cannot prove sustained frame cadence.
- Add UI-test coverage for settings dismissal, chapter navigation chrome, LAN web import and bottom safe-area behavior.

## 2026-09-03 - Stage 2C reader/UI closure checkpoint

### Completed in this checkpoint

- Commit `07d641d`: reader settings dismissal, chapter-selection reader chrome persistence, native large-title shells for Home/Discover, and auto-scroll animation tuning.
- Commit `553cc38`: fixed Swift argument ordering and split `BookDetailView` reader construction to satisfy the iOS compiler. Both iOS and unsigned IPA workflows passed.
- Commit `cd13c29`: added batch enable/disable/delete/test management for book sources, source catalogs and RSS sources.
- Commit `aca9418`: added a compact source health card and visual source-detail sheet with Search -> Detail -> TOC -> Content stage indicators and direct test/rule/JSON actions.

### CI evidence

- iOS: https://github.com/ztcsr5/read/actions/runs/33733422198 (success)
- Unsigned IPA: https://github.com/ztcsr5/read/actions/runs/33733422113 (success)

### Current phase status

- Stage 2A (JS bridge): closed.
- Stage 2B (source pipeline): closed.
- Stage 2C (reader/data/source-management polish): active, with the reader and source-management closure now green in CI.
- Stage 2D (EPUB/RSS reader depth, rule-editor UX, search productization and performance profiling): next major phase, not yet started as a full phase.

### Verification note

Windows cannot run Xcode or a real ProMotion device. CI proves compilation/tests and unsigned IPA packaging; sustained 120 Hz still requires a ProMotion device + Instruments trace.

## 2026-09-03 - Stage 2D kickoff: search and source UX

### Implemented

- Added `SearchBookMatcher` for normalized exact matching (full-width compatibility, title marks and whitespace normalization), fuzzy filtering and deterministic ranking.
- Search now removes duplicate source/book IDs while keeping cross-source alternatives visible for source switching.
- Added XCTest coverage for exact normalization, fuzzy noise filtering/ranking and duplicate suppression.
- Source management now supports batch enable/disable/delete for book sources, catalogs and RSS, plus a visual source-detail sheet that exposes Search -> Detail -> TOC -> Content readiness and actions.

### Next in Stage 2D

- Add UI-testable reader settings/chapter/朗读/auto-scroll flows.
- Deepen EPUB/RSS reader navigation and article caching interactions.
- Expand rule editor with field-level help and stage preview diagnostics.
- Keep CI green before each large-phase handoff.

## 2026-09-03 - Stage 2D reader depth and UX consolidation (in progress)

### Implemented in this large pass

- EPUB parser now retains `dc:language`/`dc:publisher`, skips `linear="no"` spine entries, and preserves navigation fragments/source paths for chapter handoff.
- Added EPUB regression coverage for non-linear spine, package metadata and fragment-aware EPUB3 navigation.
- RSS article reader now shares reader font/background/spacing preferences, starts speech from the visible paragraph, supports automatic scrolling, offline cache fallback, refresh/favorite/open-in-Safari actions, and previous/next article navigation.
- RSS article content uses the system font instead of a forced serif design and reserves bottom safe-area space for controls.
- Removed the obsolete Discover “智能网页小说模式”、订阅、写源 and duplicate source-management cards; source management remains centralized under Settings/Source Manager.
- Settings appearance changes now use a short native transition rather than an abrupt theme swap.

### Still requiring CI/device evidence

- GitHub Actions must compile/test the consolidated pass; Windows cannot run Xcode.
- Sustained 120 Hz still requires a ProMotion device + Instruments; `CADisableMinimumFrameDurationOnPhone` and the display-link ceiling request are already enabled.
- LAN Web 写源 needs a real phone/PC same-network check; the app exposes `/health` for that verification.

## 2026-09-03 - Stage 2D performance and LAN writer acceleration

### Implemented

- Web 写源页面 now uses the JSON API (`/api/sources/import`) and exposes live status refresh plus one-click source export for PC workflows.
- Added LAN API guidance directly in the page: `/api/status`, `/api/sources`, and `/api/sources/export`.
- HTTP routing now ignores query strings and supports `HEAD /health`, so browser cache probes and health monitors do not produce false failures.
- Reader pagination cache now includes viewport dimensions, preventing stale page breaks after rotation, split-view or Stage Manager resize.
- RSS article visible-paragraph bookkeeping is throttled with the same 80 ms policy as the native reader, reducing PreferenceKey/state churn during high-refresh scrolling.
- High-refresh display-link request is adaptive (`minimum = 1`) instead of forcing an 80 Hz floor on idle screens; ProMotion devices can still use the requested 120 Hz ceiling while iOS adapts for power/thermal state.

### Testing

- `git diff --check` passed locally (Windows reports only existing LF-to-CRLF normalization warnings).
- Web page JavaScript extracted and passed Node syntax validation; endpoint strings and status/export flows are present in the generated HTML.
- Unsigned IPA run `33746250790` for the preceding Web API commit `6828d18` passed; iOS build/XCTest run `33746250746` also passed.
- This performance/LAN follow-up is pending its own iOS build/XCTest and unsigned IPA runs.

### Unverified

- Windows cannot run Xcode or exercise a real phone/PC LAN session.
- Sustained 120 Hz remains a ProMotion device/Instruments measurement, not a CI claim.

### Rollback

- Revert the performance/LAN follow-up commit and this entry to restore the previous display-link floor, reader cache key, RSS bookkeeping cadence and web writer page/API routing.

## 2026-09-03 - Stage 2D bounded source diagnostics acceleration

### Implemented

- Batch book-source diagnostics now use bounded fan-out (four sources per batch) instead of strict serial execution.
- Each source keeps the full Search -> Detail -> TOC -> Content deep-check chain, with results restored to the original source order.
- Login, health and diagnostic-history records remain written on the main actor after each completed outcome.
- Deep checks now run inside the source task, so slow detail/TOC/content requests no longer serialize all other sources in the same batch.
- Dismissing the sheet or leaving Source Manager cancels the active diagnostic task; cancellation is checked between batches and outcomes.
- CI workflow concurrency now cancels superseded pushes on the same branch, and checkout uses `actions/checkout@v5` to reduce queue waste.

### Testing

- `git diff --check` passed locally (Windows reports only existing LF-to-CRLF normalization warnings).
- The preceding `e46c79a` workflow badges report passing for both iOS and unsigned IPA; the newest commit is `f2a8991` and its Actions runs are the active authoritative gate.
- Windows cannot run Xcode/XCTest or prove sustained 120 Hz; ProMotion + Instruments evidence remains required for frame cadence.

### Rollback

- Revert `f2a8991`, `e46c79a`, `6004aad`, `11f30a5` and `4547111` together to restore serial diagnostics and the previous CI workflow behavior.

## 2026-09-03 - Stage 2D consolidated reader/source experience pass

### Implemented

- Source switching now searches enabled alternatives in bounded six-source fan-out batches instead of strict serial execution; each request keeps its 10-second timeout, cancellation checks and deterministic source-name ordering.
- Reader content revisions are passed into the native TextKit surface so refreshed middle paragraphs rebuild correctly without hashing the full chapter on every body evaluation.
- Reader and RSS auto-scroll delays are clamped to safe persisted values (0.25–30 seconds), preventing malformed preferences from creating a busy loop or an effectively frozen animation.
- Native reader highlighting reacts to theme/highlight-color changes even when the spoken paragraph index is unchanged; paged reading reserves footer space so the last lines remain reachable.
- Discover exact/fuzzy mode can be changed after results arrive by reusing the raw result set rather than issuing another network search.
- Rule editor validation is grouped by field, explains empty local-preview matches, clears stale errors when drafts change, and exposes the issue count directly in the save action.

### Verification

- `git diff --check` passes; Windows only reports the repository's existing LF-to-CRLF normalization warnings.
- CI remains the authoritative Swift compile/XCTest and unsigned IPA gate; Windows cannot run Xcode/UIKit or measure sustained ProMotion cadence.

### Next

- Push this consolidated pass once, wait for both GitHub Actions workflows, then review the unsigned IPA artifact and CI diagnostics before starting the next EPUB/RSS depth phase.
## 2026-09-03 - Task: Native TextKit reader performance and 120 Hz interaction pass

### What was done
- Replaced the scroll-mode `LazyVStack + GeometryReader + PreferenceKey` hot path with `NativeReaderTextView`, a UIKit/TextKit surface that lays out the chapter once and keeps paragraph ranges for O(1) speech highlighting and jumps.
- Added native range scrolling with interruptible linear animation for automatic scroll, current-paragraph speech follow, restore-position, and chapter jumps.
- Added throttled visible-paragraph callbacks from `UITextView` so reading progress persistence is debounced without rebuilding the SwiftUI reader tree on every display callback.
- Kept system fonts, line spacing, paragraph spacing/indent, letter spacing, text selection, footer safe inset, and existing reader tap/chrome behavior.
- Added regression coverage for native layout paragraph ranges, empty paragraphs, and system font attributes.

### Testing
- Ran `git diff --check` locally; only the existing Windows LF-to-CRLF warnings remain.
- Windows has no Xcode/UIKit runtime, so Swift compilation, XCTest, and ProMotion Instruments verification are delegated to GitHub Actions and a real iPhone. Do not interpret the display-link configuration alone as proof of sustained 120 FPS.

### Rollback
- Revert this entry and the native reader commit; the previous SwiftUI scroll implementation remains intact in `ReaderView.swift` history.
## 2026-09-03 - Stage 2E EPUB/RSS/diagnostic hardening

### Implemented

- EPUB3/NCX fragment navigation is now retained as portable `LocalTextNavigationEntry` data, persisted in bookshelf records, shown as a page-level TOC, and restored to the mapped paragraph when selected.
- EPUB parsing now caches chapter XHTML while building navigation mappings and emits `epub.parse`/`epub.parse.summary` signposts for import profiling.
- RSS/Atom entries are deduplicated by stable article identity; stale feed and article caches remain readable offline while a background refresh is attempted.
- RSS list/reader surfaces expose stale-cache state and share the native reader's system-font/spacing preferences.
- Rule editor previews now return structured stage/value/count diagnostics while preserving the existing string API; changing stages clears stale preview output.
- Added regression coverage for EPUB fragment jumps, RSS deduplication/stale cache behavior, structured rule previews, and bookshelf Codable round trips including legacy JSON without navigation fields.

### Testing

- `git diff --check` passed locally; Windows only reports the repository's existing LF-to-CRLF normalization warnings.
- JavaScript/Swift sources were statically reviewed for changed initializer call sites and `ForEach` identifiers.
- Windows cannot run Swift/Xcode/UIKit/XCTest; GitHub Actions remains the authoritative compile/test and unsigned IPA gate.
- Sustained 120 Hz still requires a ProMotion device plus Instruments; no CI claim is made from configuration alone.

### CI closure

- iOS build/XCTest run `33767173262`: success.
- Unsigned IPA run `33767173222`: success; artifact `SourceReadSwift-unsigned-ipa` (5,293,022 bytes, artifact id `9898178515`).
- The first attempt (`33766530753`/`33766530756`) exposed Swift type-inference/guard syntax errors; those were fixed before this green run.

### Rollback

- Revert the single Stage 2E commit to restore the prior EPUB navigation, RSS cache freshness, rule-preview diagnostics, and bookshelf schema behavior; legacy bookshelf JSON remains readable because the new field is optional.
## 2026-09-04 - Stage 2E restore, lifecycle and diagnostics closure pass

### Implemented

- Made full-data backup import transactional across bookshelf, source library, purification rules, RSS read/favorite state and reader preferences; malformed/empty/unsupported files are rejected before mutation and a failed later write restores the previous snapshot.
- Added elapsed-time and deterministic severity ordering to batch source diagnostics, with session guards so a dismissed/reopened sheet cannot receive stale async results.
- Normalized visual source-detail history into the structured Search -> Detail -> TOC -> Content diagnostic model.
- Hardened Reader and RSS speech/auto-scroll lifecycle handling for scene transitions, chapter/article changes and late completion callbacks; speech completion now persists the last finished paragraph before chapter handoff.
- Fixed CI shell summary closure and retained iOS XCTest/unsigned IPA evidence summaries.

### Verification

- `git diff --check` passes (only the repository's existing Windows LF-to-CRLF warnings remain).
- Windows has no Xcode/UIKit runtime; GitHub Actions is the authoritative compile, XCTest and unsigned-IPA gate.
- Sustained 120 Hz still requires a ProMotion device plus Instruments; this pass only hardens the high-refresh rendering path and lifecycle behavior.

### Next

- Push the consolidated Stage 2E pass once, wait for both Actions workflows, inspect compiler/test diagnostics and record the new IPA artifact hash before starting the next large feature phase.
## 2026-09-04 - Stage 3: reader performance and product parity hardening

### What was done
- Removed the persistent no-op `CADisplayLink` from `FrameRateCoordinator`. The app keeps `CADisableMinimumFrameDurationOnPhone = true` and records the adaptive 120-ceiling policy without scheduling idle main-run-loop callbacks.
- Replaced `UIScreen.main` pagination and nine-zone tap geometry with the reader's measured container viewport, so rotation, split view and Stage Manager use the actual layout size.
- Extracted deterministic viewport/page metrics into `ReaderPerformancePolicy` and added regression tests for adaptive frame-rate plans, cache keys, orientation-sensitive pagination metrics and visible-range resolution.
- Changed long-chapter visible paragraph lookup from a linear range scan to an O(log n) binary-search resolver in the TextKit reader.
- Added a shared `CachedRemoteImage` memory cache and migrated bookshelf, Discover search and RSS article rows away from repeated `AsyncImage` decoding.
- Restored the single Settings entry points for `书源管理` and `Web 写源`, keeping Discover focused on search and avoiding duplicate source routes.

### Testing
- `git diff --check` passed locally (Windows reports the repository's existing LF-to-CRLF warnings only).
- GitHub Actions iOS build/XCTest run `33855859960` passed.
- GitHub Actions unsigned IPA run `33855859886` passed and uploaded artifact `SourceReadSwift-unsigned-ipa` (artifact id `99302539`).
- Windows cannot run Swift/Xcode/UIKit tests; sustained 120 Hz and LAN Web 写源 behavior remain real-device checks.
- Sustained 120 Hz and LAN Web 写源 behavior remain real-device checks; no device evidence is claimed here.

### Rollback
- Revert the Stage 3 commit and this progress entry together. The previous reader path remains available in the parent commit.
## 2026-09-04 - Stage 4: product regression and parity closure pass

### Implemented

- Kept the SDK-compatible high-refresh path: active scenes record a device-capped 120 Hz ceiling while `CADisableMinimumFrameDurationOnPhone` removes the app-imposed 60 Hz floor. The iOS 16 CI SDK does not expose a compile-safe scene/window/layer frame-range property, so no unsupported `CAFrameRateRange` call is used.
- Hardened the reader settings panel with an explicit close path, high z-order, and downward drag-to-dismiss. Chapter/content revisions now clear stale playback, pagination, sheet and overlay state before rebuilding the page cache.
- Kept speech start anchored to the latest visible paragraph so tapping朗读 after scrolling does not replay the chapter from the beginning.
- Added a visible `详情` action to book-source cards while retaining the full menu for testing, rule editing, JSON editing and history. Removed the redundant import hint from the source status card.
- Added Discover search clear/cancel actions and a model-level reset path that cancels in-flight work and clears stale results, failures and filters without issuing a second request.
- Let the root tab bar participate in keyboard safe-area changes so it lifts with the keyboard instead of staying underneath it; Settings now explicitly uses the bounded large-title style like Home and Discover.
- Added `DiscoverViewModelTests` covering clear/reset behavior and the empty-state transition.

### Verification

- `git diff --check` passed locally (Windows reports only the repository's existing LF-to-CRLF normalization warnings).
- Windows cannot run Xcode/UIKit/XCTest. The next iOS build/XCTest and unsigned-IPA Actions runs are the authoritative compile/package gate.
- Sustained 120 Hz, keyboard feel, reader drag dismissal and LAN Web 写源 access still require a ProMotion iPhone / same-network device check.

### Rollback

- Revert the single Stage 4 commit and this entry to restore the prior scene frame-rate policy, reader lifecycle, source-card layout, Discover search controls, root keyboard behavior and Settings title mode.

### CI evidence

- Corrected Stage 4 commit: `5592aac`.
- iOS build/XCTest: [run 33859400392](https://github.com/ztcsr5/read/actions/runs/33859400392) — success.
- Unsigned IPA: [run 33859400414](https://github.com/ztcsr5/read/actions/runs/33859400414) — success.
- Artifact: `SourceReadSwift-unsigned-ipa`, 5.84 MB, SHA-256 `89ed9f19284eb3b2cb8a87355de55e629b5ace9122f28db712ad69b762fae120`.
- Device-only items remain open: sustained ProMotion frame pacing, reader gesture feel, keyboard/layer behavior and same-network Web 写源 access.
## 2026-09-04 - Stage 5: Legado JS source compatibility expansion (complete)
### CI closure

- Initial bridge commit: `5e532bd`.
- Corrected Swift regex escaping: `fecb16c`.
- Corrected raw attribute semantics and Fetch request metadata: `cf5a41e`.
- Corrected Fetch body fixture envelope: `f7ffafc`.
- iOS build/XCTest: [run 33866066483](https://github.com/ztcsr5/read/actions/runs/33866066483) — success.
- Unsigned IPA: [run 33866066490](https://github.com/ztcsr5/read/actions/runs/33866066490) — success.
- Artifact: `SourceReadSwift-unsigned-ipa`, 6,174,111 bytes, SHA-256 `06963cb903fd92096c6209d5568788e06215d63eb5dd6cfdd1dff1e308be091b`.
- CI now proves the bridge compiles and deterministic compatibility tests pass. Real-world source coverage, network quirks and sustained 120 Hz remain device/source fixture checks.

### Implemented

- Expanded the JavaScriptCore Legado bridge with response/body compatibility (body().string/json, response.json, code/status/ok, final URL, headers/cookies and common string methods).
- Added global Legado/MR aliases for DOM extraction, storage, network, script import, user-agent and digest helpers.
- Reworked java.htmlFormat/clean to remove script/style noise, preserve readable block breaks and decode common HTML entities.
- Added java.regex helpers and a Java-style Packages.java.util.regex.Pattern matcher with find, matches, groups, offsets and Java flag mapping.
- Replaced the limited JSON rule resolver with JSONPath support for nested paths, wildcards, array indexes, recursive descent and filter/comparison predicates.
- Added deterministic XCTest coverage for helper aliases, regex, Pattern, JSONPath, response metadata, POST/connect/cookie/importScript and content mutation.

### Verification

- Extracted the Swift multiline prelude with Swift escape decoding and passed node --check.
- Ran deterministic Node harnesses for JSONPath, HTML formatting, response aliases and Pattern matching.
- git diff --check passes with only the repository's existing Windows LF-to-CRLF warnings.
- Windows cannot run Swift/Xcode/UIKit/XCTest; GitHub Actions remains the compile/test and unsigned-IPA gate.

### Next

- Commit and push this Stage 5 pass once, wait for iOS build/XCTest and unsigned IPA workflows, inspect annotations/artifact, then record CI closure and IPA hash.

### Rollback

- Revert the single Stage 5 bridge/test commit and this entry to restore the prior JSON resolver and JS compatibility surface.

## 2026-09-04 - Stage 6: unified Legado source pipeline closure

### Implemented

- Unified Search -> Detail -> TOC -> Content execution into the production `SourcePipeline` and exposed structured execution/report results for UI diagnostics and regression tests.
- Added directive-aware request handling for charset/encoding/body/JSON options, bounded timeout variants, and preserved response metadata needed by Legado JavaScript sources.
- Connected source diagnostics and rule-editor previews to the same pipeline-oriented evidence model so successful prefixes remain available when a later stage fails.

### Verification

- Commit: `d39507c` (pipeline implementation and optional-timeout test correction).
- GitHub Actions iOS build/XCTest: [run 33870395138](https://github.com/ztcsr5/read/actions/runs/33870395138) — success.
- GitHub Actions unsigned IPA: [run 33870395014](https://github.com/ztcsr5/read/actions/runs/33870395014) — success.
- Artifact: `SourceReadSwift-unsigned-ipa`, artifact id `9935754059`, 6,188,595 bytes. IPA SHA-256 was not retrieved for this run and is intentionally not reported.
- `git diff --check` passes locally; Windows has no Xcode/UIKit runtime, so Actions remains the Swift compile/XCTest/IPA gate.

### Open device checks

- Real Legado source diversity, Web 写源 LAN access, reader gesture feel and sustained 120 Hz cadence still require a ProMotion iPhone plus Instruments/device verification.

### Rollback

- Revert `408a8c4..d39507c` together to restore the pre-pipeline source execution path and request-directive behavior.
## 2026-09-04 - Stage 8: Legado mixed-response and cross-stage JS state hardening

### Implemented

- Added a shared `ResponseFormatDetector` for UTF-8 BOM, XSSI guards, `<pre>` JSON, embedded balanced JSON and incorrect content-type responses; Search, Detail, TOC and Content parsers now use the same decision path.
- Added a balanced JSON scanner that respects nested objects/arrays, quoted strings and escaped quotes instead of truncating on the last closing bracket.
- Added source-scoped `RulePersistentState` shared across Search -> Detail -> TOC -> Content and login JS contexts, so `java.put/get`, source variables and dynamic nonce values survive stage boundaries.
- Extended `bodyJs` execution to source-level and rule-level transforms, including Search/Detail/TOC/Content and paginated follow-up pages; removed the duplicate legacy source-test path in Source Manager.
- Added response-aware JS callbacks to search URL evaluation and propagated the current cookie header into synchronous JS requests.
- Hardened WebView fallback cancellation, navigation-delay handling, cookie sync and the bounded 30-second timeout so cancelled diagnostics cannot leave a continuation hanging.

### Tests added

- `ResponseFormatDetectorTests`: BOM, wrong content type, XSSI, `<pre>`, embedded balanced JSON and malformed/ordinary HTML behavior.
- `SourceEngineBodyJSTests`: source/rule `bodyJs` ordering and `java.put/get` state surviving Search into Detail.

### Verification

- Node bridge harnesses still pass (`advanced-bridge-harness.js`, `response-harness.js`, `prelude-check.js`).
- `git diff --check` passes with only the repository's existing Windows LF-to-CRLF normalization warnings.
- Windows has no Swift/Xcode/UIKit runtime; GitHub Actions remains the authoritative compile/XCTest and unsigned-IPA gate.

### Next

- Commit and push this Stage 8 pass once, wait for both Actions workflows, inspect compiler/test annotations and record the unsigned IPA size/hash before moving to the next large source-compatibility phase.

### Rollback

- Revert the single Stage 8 commit to restore the prior parser format detection, per-stage JS state, body transforms, WebView fallback lifecycle and Source Manager test path.

## 2026-09-05 - Stage 9: dynamic request body and cookie compatibility closure

### Implemented

- Preserved Legado placeholders until the request component boundary so dynamic
  `@Body` and text `requestBody` values are URL-encoded exactly once. JSON bodies
  remain type-safe and unescaped, while form values now handle spaces, CJK and
  ampersands without corrupting separators.
- Fixed `cookie.setCookie` request-header parsing for multiple pairs such as
  `sid=ok; theme=dark`, filtering response-only attributes before merging them
  into source-scoped state and `HTTPCookieStorage`.
- Updated paginated bodyJs fixtures to keep branch markers out of chapter text
  and to assert response `Set-Cookie` precedence explicitly.

### Verification

- Commits: `e51b50c`, `e546298`, `ab15846`.
- iOS build/XCTest: [run 33919054887](https://github.com/ztcsr5/read/actions/runs/33919054887) — success.
- Unsigned IPA: [run 33919054978](https://github.com/ztcsr5/read/actions/runs/33919054978) — success.
- Added regression coverage for directive and text-form dynamic bodies,
  multi-cookie JS state and paginated bodyJs output.
- `git diff --check` passes locally; Windows has no Xcode/UIKit runtime, so the
  Actions build/test and package workflows remain the authoritative iOS gate.

### Open device/source checks

- Broad real-world Legado source coverage, Web 写源 same-network behavior,
  sustained ProMotion frame pacing and reader gesture feel still require a
  ProMotion iPhone/device run.

### Rollback

- Revert `e51b50c..ab15846` together to restore the previous dynamic request,
  cookie and fixture behavior.

## 2026-09-05 - Stage 10: Java/Flutter Legado compatibility surface

### Implemented

- Extended the JavaScriptCore prelude with URL/URI normalization, dual
  constructor ordering, `URLConnection` request properties/timeouts/streams,
  response metadata and fixture-routed status handling.
- Expanded `StringBuilder`, `HashMap`, `ArrayList` and `Pattern/Matcher` to the
  high-frequency Android Legado method surface, including mutable map entries,
  indexed list operations and matcher replacement/region helpers.
- Fixed CryptoJS binary `WordArray` stringify/truncation semantics and added a
  dependency-free RIPEMD-160 implementation. Added Security.framework RSA
  bridge aliases with deterministic empty failure behavior.
- Added offline Stage 10 XCTest coverage for the new Java facade, source/window
  metadata, cache/field helpers, Flutter utility aliases and binary WordArray.

### Verification

- `node ci-log/extract-prelude.js` and `node --check ci-log/js-prelude-check.js`
  pass on Windows after decoding Swift's escaped JavaScript layer.
- `git diff --check` passes; Windows has no Xcode/UIKit toolchain.
- iOS build/XCTest: [run 33924320643](https://github.com/ztcsr5/read/actions/runs/33924320643) — success.
- Unsigned IPA: [run 33924320745](https://github.com/ztcsr5/read/actions/runs/33924320745) — success.
- Both workflows passed on the Stage 10 head; the unsigned IPA artifact was
  produced successfully (artifact hash/size were not retained in the CI
  summary and are intentionally not guessed).

### Next

- Stage 10 is closed. Continue with the Stage 11 offline Legado fixture corpus,
  parity probes and batch diagnostic export on the same branch.

### Rollback

- Revert the Stage 10 commit to restore the Stage 9 dynamic body/cookie bridge.

## 2026-09-05 - Stage 11: Legado fixture corpus and diagnostic export (in progress)

### Implemented

- Added four offline Legado source fixtures covering mixed BOM/XSSI/`<pre>`/embedded JSON responses, cookie + dynamic nonce state, JavaImporter/ArrayList/MessageDigest, and CryptoJS Base64 body transforms.
- Added end-to-end `SourceEngineLegadoCorpusTests` using an injected `CorpusNetworkClient`; Search → Detail → TOC → Content runs without contacting public source hosts.
- Extended `SourceDiagnosticStep` with request/response metadata, status code, headers, cookie summary, final URL and retry count while keeping old diagnostic JSON decodable.
- Added `SourceDiagnosticBatchReport` JSON/text export, failure prioritization and credential-like metadata redaction for Authorization/Cookie/token/password fields.
- Added Source Manager batch-test export actions and result counts for support/debug reports.

### Verification

- `node ci-log/extract-prelude.js` and `node --check ci-log/js-prelude-check.js` pass locally.
- `git diff --check` passes; Windows reports only the repository's existing LF-to-CRLF normalization warnings.
- Windows has no Swift/Xcode/UIKit runtime. GitHub Actions remains the authoritative iOS compile/XCTest and unsigned-IPA gate for this stage.
- Real public-source compatibility, Web 写源 LAN access and sustained ProMotion frame pacing remain device/source checks; these fixtures are deterministic regression coverage, not proof of every public source.

### Next

- Push this Stage 11 commit, wait for iOS XCTest and unsigned-IPA Actions, inspect compiler/test annotations and record the actual artifact size/hash before closing the stage.

### Rollback

- Revert the Stage 11 commit to restore the prior diagnostic model, Source Manager export surface and fixture test set.

## 2026-09-05 - Stage 11: Legado fixture corpus and diagnostic export (complete)

### CI closure

- iOS build/XCTest: [run 33927521894](https://github.com/ztcsr5/read/actions/runs/33927521894) — success (Run 256).
- Unsigned IPA: [run 33927521929](https://github.com/ztcsr5/read/actions/runs/33927521929) — success (Run 253).
- Artifact: `SourceReadSwift-unsigned-ipa`, artifact id `9957418426`, displayed size 6.02 MB.
- GitHub artifact package digest: `d0d3d45b0cc7d486105900aee1d0c4696e60989e73a8b506f2ad3054d7f30496` (this is the artifact package digest, not an internal IPA SHA-256).

### Closure

- Stage 11 is complete. The offline fixture corpus, Search → Detail → TOC → Content regression chain, structured diagnostic metadata, redacted JSON/text batch export and Source Manager export actions are now covered by the green CI build/test/package gates.
- Real public-source diversity, same-network Web 写源 behavior and sustained ProMotion frame pacing remain device/source checks and are not overstated as CI-proven.

### Rollback

- Revert the Stage 11 implementation commits and this closure entry together to restore the prior diagnostic model, Source Manager export surface and fixture test set.

## 2026-09-05 - Stage 12: full batch pipeline diagnostics (complete)

### Implemented

- Replaced the Source Manager deep-check path that previously compressed Detail → TOC → Content into one free-form row with `SourceBatchDiagnosticRunner`.
- Deep batch checks now execute the production `SourcePipeline` once per source and retain every structured Search, Detail, TOC and Content step, including the successful prefix when a later stage fails.
- Shallow checks still run Search only for fast health scans; both modes export through the same redacted `SourceDiagnosticBatchReport` JSON/text model.
- Added bounded concurrent source execution with progress callbacks and source-scoped report retention in the UI state.
- Added regression coverage for full four-stage export, failed-content prefix retention and bounded multi-source progress accounting.

### Verification

- `node ci-log/extract-prelude.js`, `node --check ci-log/js-prelude-check.js` and `git diff --check` pass locally.
- iOS build/XCTest: [run 33929236140](https://github.com/ztcsr5/read/actions/runs/33929236140) — success.
- Unsigned IPA: [run 33929236280](https://github.com/ztcsr5/read/actions/runs/33929236280) — success.
- Artifact: `SourceReadSwift-unsigned-ipa`, artifact id `9958015274`, 6,324,630 bytes; package digest `sha256:2e95adf3cae14eb1a1e91d9333dd5a48ccbeb52047d024b0f2891528c36c3958`.
- Windows has no Xcode/UIKit runtime; real public-source diversity, LAN Web 写源 and sustained ProMotion frame pacing remain device/source checks.

### Rollback

- Revert the Stage 12 implementation commit and this entry together to restore the previous compact deep-check behavior.

## 2026-09-05 - Stage 13: request/response evidence in source diagnostics (complete)

### Implemented

- Added `SourceDiagnosticEvidence` and an optional `SourceDiagnosticEvidenceProvider` capability so engines can expose structured request/response evidence without coupling the diagnostic model to networking internals.
- `LegadoSourceEngine` now records per-stage HTTP method, request body/headers, response status/headers, Cookie/Set-Cookie summary and final URL for Search, Detail, TOC and Content, including WebView fallback responses.
- Batch diagnostics enrich every retained stage with this evidence while preserving the existing redaction boundary in `SourceDiagnosticStep`; legacy reports remain decodable.
- Added regression coverage for four-stage evidence capture and verification that exported JSON never contains the fixture secret cookie value.

### Verification

- iOS build/XCTest: [run 33930495421](https://github.com/ztcsr5/read/actions/runs/33930495421) — success.
- Unsigned IPA: [run 33930495381](https://github.com/ztcsr5/read/actions/runs/33930495381) — success.
- Artifact: `SourceReadSwift-unsigned-ipa`, artifact id `9958420577`, 6,333,230 bytes. GitHub API rate limiting prevented retrieving the artifact digest; it is intentionally not guessed.
- `node ci-log/extract-prelude.js`, `node --check ci-log/js-prelude-check.js` and `git diff --check` pass locally. Windows has no Xcode/UIKit runtime, so Actions remains the authoritative Swift compile/XCTest/IPA gate.

### Open device/source checks

- Real public-source diversity, same-network Web 写源 behavior and sustained ProMotion frame pacing still require a ProMotion iPhone/device run. Captured evidence is deterministic fixture/engine coverage, not proof of every public source.

### Rollback

- Revert commit `a25323b` and this closure entry together to restore the prior batch diagnostics without structured request/response evidence.

### Next

- Expand the offline Android Legado corpus and failure taxonomy, then add compatibility probes for less-common response transforms before the next CI-gated handoff.

## 2026-09-05 - Stage 14: response variants and diagnostic failure taxonomy (complete)

### Implemented

- Hardened `ResponseFormatDetector` for JSONP callbacks, JavaScript assignments, HTML entities (named and numeric), URL-encoded JSON and form/query envelopes while retaining BOM, XSSI, `<pre>` and balanced JSON handling.
- Added stable machine-readable `SourceDiagnosticFailureKind` values with retry policy, backward-compatible decoding and redacted export visibility.
- Propagated failure codes through the production Search → Detail → TOC → Content pipeline and batch diagnostics, including empty-result, timeout and network/parser/script/authentication/blocked classifications.
- Added regression coverage for wrapped/escaped/encoded responses, failure kinds, retry behavior and legacy diagnostic JSON.

### Verification

- `node ci-log/extract-prelude.js`, `node --check ci-log/js-prelude-check.js` and `git diff --check` pass locally.
- iOS build/XCTest: [run 33933538847](https://github.com/ztcsr5/read/actions/runs/33933538847) — success.
- Unsigned IPA: [run 33933538801](https://github.com/ztcsr5/read/actions/runs/33933538801) — success.
- Artifact: `SourceReadSwift-unsigned-ipa`, artifact id `9959455684`, 6,337,437 bytes; package digest `sha256:755fca48ffdbc1ff2cdbefacf620bcea0976c9dd8f740abc91f15197d37f8ae3`.
- Windows has no Xcode/UIKit runtime; public-source diversity, Web 写源 LAN behavior and sustained ProMotion frame pacing remain device/source checks.

### Rollback

- Revert commit `a5f4d44` and this closure entry together to restore the prior response detector and diagnostic model.

### Next

- Stage 15: broaden the offline Android Legado corpus with paginated/dynamic/encoded/compressed fixtures and compatibility probes, then feed the resulting evidence into source diagnostics and rule-editor previews.

## 2026-09-05 - Stage 15: compressed Legado transport normalization (complete)

### Implemented

- Added conservative HTTP body decoding for `gzip`, `x-gzip`, zlib-wrapped
  `deflate`, raw DEFLATE and `identity`, including reverse-order decoding for
  stacked `Content-Encoding` values.
- Applied the same response normalization at URLSession, synchronous JS/Java
  callbacks, injected network adapters and the production engine boundary, so
  Search -> Detail -> TOC -> Content parsers receive decoded bytes regardless
  of which transport path supplied the response.
- Preserved the original bytes for unsupported or malformed encodings instead
  of exposing a partial transform to source rules.
- Added deterministic gzip/deflate unit coverage plus a four-stage offline
  compressed fixture whose injected client returns binary data with an empty
  text body.

### Verification

- Commits: `a23f1db`, `cd041b0`.
- iOS build/XCTest: [run 33936755360](https://github.com/ztcsr5/read/actions/runs/33936755360) - success.
- Unsigned IPA: [run 33936755392](https://github.com/ztcsr5/read/actions/runs/33936755392) - success.
- Artifact: `SourceReadSwift-unsigned-ipa`, artifact id `9960484340`,
  6,342,255 bytes; package digest
  `sha256:3a62c53f0f64eb038fc05d31ba8f955506f546c034a16bfc1f56f8c4e7ba8151`.
- Python independently verified every fixed compressed fixture byte array;
  `node ci-log/extract-prelude.js`, `node --check ci-log/js-prelude-check.js`
  and `git diff --check` pass locally.
- Windows has no Xcode/UIKit runtime. Public-source diversity, Web source LAN
  access and sustained ProMotion frame pacing remain device/source checks.

### Rollback

- Revert `a23f1db` and `cd041b0` together to restore the Stage 14 transport
  behavior.

### Next

- Stage 16: connect dynamic/paginated/encoded/encrypted response fixtures to
  rule-editor preview evidence, then expose each preview stage's normalized
  request, transformed response and parsed output in one reusable diagnostic
  pipeline.

## 2026-09-05 - Stage 16: normalized transport and rule-preview evidence (complete)

### Implemented

- Exposed `ResponseBodyDecoder.DecodeResult` with normalized Content-Encoding tokens and a decoded/raw flag, while preserving transactional fallback for malformed or unsupported payloads.
- Extended `SourceResponse` and structured diagnostic evidence with encoded byte count, decoded byte count, coding list and decode status; the batch text export now reports transport evidence per stage.
- Preserved transport metadata through Search, Detail, TOC and Content parser normalization so downstream rule evaluation cannot silently discard response provenance.
- Added rule-editor preview evidence: local request URL, detected HTML/JSON/text format, normalized response, selected rule, parsed output count and byte counts. Evidence is shown in a collapsible preview panel and retained in preview history.
- Added regression tests for compressed metadata, unsupported codings, legacy diagnostic JSON, transport export text, four-stage fixture evidence and BOM/JSON rule preview normalization.

### Verification

- `node ci-log/extract-prelude.js`, `node --check ci-log/js-prelude-check.js` and `git diff --check` pass locally.
- iOS build/XCTest: [run 33941958449](https://github.com/ztcsr5/read/actions/runs/33941958449) - success.
- Unsigned IPA: [run 33941958466](https://github.com/ztcsr5/read/actions/runs/33941958466) - success.
- Artifact: `SourceReadSwift-unsigned-ipa`, artifact id `9962159177`, 6,365,007 bytes; package digest `sha256:05eaed505997194faa8b0bb5929e054c81c3de6b94e7cec5875661779befe156`.
- Windows has no Xcode/UIKit runtime; real public-source diversity, LAN Web 写源 and sustained ProMotion frame pacing remain device/source checks.

### Commits

- `27e40a2 feat: expose normalized transport evidence`
- `f02e03d fix: order transport evidence test arguments`
- `90d31ec fix: assert compressed fixture decoded size`
- `f51d6c0 feat: expose rule preview evidence`

### Rollback

- Revert commits `27e40a2`, `f02e03d`, `90d31ec` and `f51d6c0` together to restore the Stage 15 transport behavior and compact rule-editor preview.

### Next

- Stage 17: expand JavaScript compatibility beyond the current QuickJS/JavaScriptCore subset (Legado host shims, async/promise bridges and parity fixtures), then feed pass/fail reasons into the same evidence model.

## 2026-09-05 - Stage 17: Legado JavaScript async/Promise compatibility (complete)

### Implemented

- Added a lexical-safe `LegadoJavaScriptCompatibility` normalizer for `@js:` and
  `<js>` wrappers, `await`, async functions/arrows, Promise chains and common
  async host APIs. String, comment and regular-expression literals are kept
  byte-for-byte intact.
- Extended the JavaScriptCore prelude with a synchronous Promise facade,
  `Promise.resolve/reject/all/race`, thenable responses, `globalThis`,
  `URLSearchParams`, `Headers`, `Response`, `queueMicrotask` and timer aliases.
- Kept Search URL, bodyJs and Search → Detail → TOC → Content execution on the
  same `RuleExecutionContext`, so async/Promise feature evidence survives
  paginated follow-up requests and enters the existing diagnostic report.
- Added redacted raw/normalized JS evidence and deterministic XCTest coverage
  for normalization, ajax/ajaxAll/fetch, Promise chains, rejection handling,
  wrappers and literal-safety behavior.

### Verification

- Local: `node ci-log/extract-prelude.js`, `node --check ci-log/js-prelude-check.js`
  and `git diff --check` pass. Windows has no Swift/Xcode/UIKit runtime.
- iOS build/XCTest: [run 33948719788](https://github.com/ztcsr5/read/actions/runs/33948719788) — success (Run 278).
- Unsigned IPA: [run 33948719798](https://github.com/ztcsr5/read/actions/runs/33948719798) — success (Run 275).
- Artifact: `SourceReadSwift-unsigned-ipa`, artifact id `9964170560`,
  6,392,287 bytes. GitHub artifact package digest was not exposed by the
  unauthenticated API and is intentionally not guessed.
- The green CI gate proves compilation, XCTest execution and packaging for the
  deterministic fixtures; broad public-source compatibility and sustained
  ProMotion 120 Hz still require a physical iPhone/source corpus.

### Commits

- `c8ac5b7 feat: expand Legado async JavaScript compatibility`
- `a26b22e fix: compile JavaScript compatibility bridge`
- `d1e2aa4 test: fix multiline Legado fixture literal`
- `c42a109 test: use valid multiline Swift fixture`
- `fa54113 test: make fixture response capture explicit`

### Rollback

- Revert commits `c8ac5b7` through `fa54113` together to restore the Stage 16
  JavaScript bridge and compact rule-preview evidence.

### Next

- Stage 18: source-rule parity expansion beyond async syntax—Legado Java/HTTP
  host surface, import-script behavior, pagination state and representative
  offline fixtures—then connect the outcomes to visual source-detail testing.

## 2026-09-05 - Stage 18: Legado Java/HTTP host surface and pagination (complete)

### Implemented

- Extended the source request model with PUT, PATCH, DELETE and OPTIONS and
  preserved explicit method/body/header evidence through URL directives and the
  synchronous JavaScript bridge.
- Added `java.connect()` verb aliases, request-body/output-stream shims,
  `java.fetch` options, response status/final-URL/header/raw-byte metadata and
  chapter-variable injection for Legado-compatible scripts.
- Added loop-safe TOC (30 pages) and Content (8 pages) pagination with repeated
  URL detection, diagnostic stop events and successful-prefix preservation.
- Added deterministic offline fixture coverage for HTTP verbs, binary bodies,
  importScript, source/book/chapter variables and pagination termination.

### Verification

- Local: `node ci-log/extract-prelude.js`, `node --check ci-log/js-prelude-check.js`
  and `git diff --check` pass. Windows has no Swift/Xcode/UIKit runtime.
- iOS build/XCTest: [run 33966640698](https://github.com/ztcsr5/read/actions/runs/33966640698) — success.
- Unsigned IPA: [run 33966641149](https://github.com/ztcsr5/read/actions/runs/33966641149) — success.
- Artifact: `SourceReadSwift-unsigned-ipa`, artifact id `9969700683`,
  6,397,798 bytes. Package digest is not exposed by the unauthenticated API
  and is intentionally not guessed.
- The green CI gate proves compilation, XCTest execution and packaging for the
  deterministic fixtures; broad public-source compatibility, LAN Web 写源 and
  sustained ProMotion frame pacing still require a physical iPhone/source corpus.

### Commits

- `fffd901 feat: expand Legado HTTP and pagination compatibility`
- `a8213f2 fix: preserve connect aliases and chapter state`
- `308473e fix: route HEAD through request bridge`

### Rollback

- Revert `fffd901`, `a8213f2` and `308473e` together to restore the Stage 17
  JavaScript/transport behavior.

### Next

- Stage 19: reader/UI quality pass—EPUB/RSS reading surfaces, speech/auto-page
  state, 120 Hz rendering hygiene, source-detail/rule-editor validation and
  the remaining bookshelf/source-management workflows.

## 2026-09-06 - Stage 19B: reader and LAN source quality pass (complete)

### Implemented in this batch

- Added a shared numeric editor for reader sliders. Decimal comma input is
  normalized, incomplete drafts are tolerated while typing, committed values
  are clamped to their documented ranges, and invalid values restore the last
  valid setting. The same control is now used by the chapter reader and RSS
  article reader.
- Added a dedicated RSS reading-settings sheet covering background, typography,
  spacing, speech rate and automatic-scroll delay. RSS articles now use the
  native TextKit reader surface and the same high-refresh anchor as chapters.
- Unified the RSS overflow menu with speech-from-visible-paragraph,
  auto-scroll, refresh, settings, favorite and browser actions. Loading,
  cached/offline and failure states are visible without covering the bottom
  reader controls.
- Replaced the LAN source editor's UTF-8 string-offset HTTP handling with a
  byte-oriented HTTP/1.1 parser. It handles packet splits, UTF-8 JSON bodies,
  HEAD/OPTIONS/favicon probes, normalized headers, bounded body/header sizes,
  CORS preflight caching and deterministic 501 responses for chunked requests.
- Search results now collapse URL slash/case duplicates within one source while
  preserving equivalent books from different sources. The source-manager
  import sheet no longer exposes a duplicate top-level Import action.

### Verification before CI

- `node ci-log/extract-prelude.js` pass (164531 bytes extracted).
- `node --check ci-log/js-prelude-check.js` pass.
- `git diff --check` pass.
- Added deterministic XCTest coverage for reader value normalization, HTTP
  framing/body limits/HEAD handling and search URL de-duplication.
- Windows has no Xcode/UIKit runtime, so Swift validation ran in GitHub Actions.

### Verification after push

- iOS build/XCTest: [run 33977725581](https://github.com/ztcsr5/read/actions/runs/33977725581) — success.
- Unsigned IPA: [run 33977725431](https://github.com/ztcsr5/read/actions/runs/33977725431) — success.
- Artifact: `SourceReadSwift-unsigned-ipa`, artifact id `9972893180`,
  6,445,872 bytes; the artifact is retained on GitHub Actions for self-signing.
- Commit: `33c47f7 feat: complete Stage 19B reader and LAN source quality pass`.
- The green CI gate proves the new Swift sources compile, XCTest executes and
  the unsigned device archive packages. Sustained 120 Hz pacing, public-source
  diversity and LAN access from a particular PC/router still require physical
  device/source-corpus checks.

### Rollback

- Revert `33c47f7` to restore the Stage 19A reader/source behavior.

### Next

- Push the Stage 19B batch to `codex/swift-v2-lifetime-reader`, wait for both
  iOS XCTest and unsigned-IPA workflows, then fix any compiler/test failures
  before starting the next large stage.

## 2026-09-06 - Stage 20A: search UX and smart web reading surface (complete)

### Implemented in this batch

- Added an explicit `智能网页阅读` entry to the Discover navigation bar instead of leaving the existing concept implicit.
- Added a native `WKWebView` page preview with a one-tap `提取正文并阅读` action.
- Added `SmartWebArticleExtractor`, which removes navigation/scripts/boilerplate and projects article blocks into the native text reader surface.
- Added deterministic extractor tests for boilerplate removal, title selection and malformed HTML fallback.

### Verification

- `git diff --check` passed before commit; source-level inspection completed.
- Windows has no Xcode/UIKit runtime; iOS compilation/XCTest and unsigned IPA remain GitHub Actions gates.
- Sustained ProMotion frame pacing and extraction quality across arbitrary public pages still require physical-device and corpus checks.

### Next

- Stage 20B: root-page visual polish, source-manager batch UX review and remaining 23-item issue closure.

## 2026-09-06 - Stage 20B: root navigation and source-manager polish (in CI)

### Implemented in this batch

- Added bottom tail spacing to the bookshelf, discovery and source-manager
  root scroll surfaces so the final card/row remains readable above the
  floating tab bar and inline batch actions.
- Reduced the source-manager status card footprint and hierarchy: compact
  count badge, tighter metrics, smaller explanatory copy and a shorter action
  row suitable for compact iPhone screens.
- Consolidated source import into the status card (`导入书源`) instead of a
  duplicate navigation-bar `+` entry; Web 写源 is now reachable from the same
  source-management surface.
- Removed the duplicate Web 写源 entry from 设置; source management is now the
  single canonical entry point.
- Removed the permanent no-op CADisplayLink driver. The app keeps
  `CADisableMinimumFrameDurationOnPhone` and scene-level high-refresh anchors,
  while avoiding an idle main-run-loop callback that competes with SwiftUI
  layout. This is an adaptive ProMotion request, not a claim of sustained
  120 FPS without device/Instruments evidence.

### Verification before CI

- `git diff --check` passed.
- `node ci-log/extract-prelude.js` passed (`164531` bytes extracted).
- `node --check ci-log/js-prelude-check.js` passed.
- Commit: `a9d1cb7 feat: polish root navigation and high-refresh rendering`.
- Pushed to `origin/codex/swift-v2-lifetime-reader`.

### Verification after push

- iOS build/XCTest: [run 33982823986](https://github.com/ztcsr5/read/actions/runs/33982823986) — success.
- Unsigned IPA: [run 33982823896](https://github.com/ztcsr5/read/actions/runs/33982823896) — success; unsigned artifact available from the run.

### Rollback

- Revert `a9d1cb7` to restore the Stage 20A navigation, source-card and
  display-link behavior.

### Stage 20B follow-up: high-refresh capability hook

- The attempted scene-level frame-rate setter (`e66e4d1`) was rejected by the
  iOS 16 SDK and was superseded before release. The supported implementation
  remains `CADisableMinimumFrameDurationOnPhone=true` plus the native
  TextKit/SwiftUI reader surface and diagnostic ceiling calculation.
- No always-running display link was reintroduced; this avoids idle main-run-
  loop work competing with SwiftUI layout.

### Verification

- `git diff --check` passed.
- `node ci-log/extract-prelude.js` passed (`164531` bytes extracted).
- `node --check ci-log/js-prelude-check.js` passed.
- GitHub Actions for `e66e4d1`: failed at compile time because
  `UIWindowScene.preferredFrameRateRange` is not available in the target SDK;
  the commit was superseded by the current fix.

### Rollback

- Revert `e66e4d1` if historical comparison is needed; use the current
  diagnostic-only hook for the supported iOS 16 build.

### Stage 20B final CI evidence

- Current release head: `1d9e0cc` (`fix: restore iOS 16 compatible refresh hook`).
- iOS build/XCTest: [run 33984405010](https://github.com/ztcsr5/read/actions/runs/33984405010) — success.
- Unsigned IPA: [run 33984405092](https://github.com/ztcsr5/read/actions/runs/33984405092) — success.
- The failed experimental commits `e66e4d1`, `cbfb348` and `2b974cb` are
  superseded; they are retained only in git history for auditability.

## 2026-09-06 - Stage 20C: reader/source/search correctness pass (in CI)

### Implemented in this batch

- Reader auto-scroll now starts from the current visible paragraph and can hand
  off to the next chapter without losing playback state.
- Native TextKit updates its visibility callback on every SwiftUI update;
  paragraph indentation now affects only the first line.
- Empty正文 results are classified as pipeline failures instead of false
  success, with regression coverage.
- Source detail actions are serialized through sheet dismissal before opening
  test/rule/JSON editors; batch source tests use the complete selection rather
  than only the current filter projection.
- Search progress reports enabled-source count, avoids duplicate submissions,
  keeps same-name sources separate, and preserves case-sensitive URL paths.

### Verification

- `git diff --check` passed before push.
- Commit: `089ed25 fix: make reader autoplay and source modal flows stateful`.
- GitHub Actions iOS/XCTest and unsigned IPA are running for this commit.

### Device/corpus items still open

- Sustained 120 Hz and touch smoothness require iPhone + Instruments.
- EPUB/RSS parity and broad Legado corpus compatibility remain later-stage work.

### CI correction log

- First Stage 20A Actions run exposed a SwiftUI `toolbar(content:)` overload ambiguity in `SmartWebReaderView`; replaced it with the compatible `navigationBarItems` API and pushed commit `0946340`.

### Stage 20A CI evidence

- iOS build/XCTest: [run 33981351831](https://github.com/ztcsr5/read/actions/runs/33981351831) — success.
- Unsigned IPA: [run 33981351869](https://github.com/ztcsr5/read/actions/runs/33981351869) — success; download artifact from the run for self-signing.
- Final Stage 20A commit: `4a80fa5` (plus the preceding grouped-search and CI-fix commits on the same branch).
