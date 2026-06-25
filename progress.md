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
