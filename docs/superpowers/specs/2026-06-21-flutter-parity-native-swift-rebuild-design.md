# SourceReadSwift Flutter Parity Native Rebuild Design

Date: 2026-06-21

## Decision

The Swift rewrite is not complete until it matches the existing Flutter app's product shape, layout, and daily-use flows. CI success, an unsigned IPA artifact, or a smooth prototype is not enough.

The Flutter app is the source of truth for:

- Page structure
- iOS Podcasts-style visual layout
- Reader behavior
- Reader settings
- Book source management
- Import, search, add-to-bookshelf, and reading flows

The Swift app may improve native smoothness, animation, haptics, and platform polish, but it must not invent a different product. Native polish is an enhancement layer on top of the Flutter product, not a replacement.

## Current Failure Assessment

The current Swift branch is useful as scaffolding only. It fails product acceptance because:

- Home, Discover, Source Manager, Settings, and Reader do not yet reach Flutter parity.
- Some Chinese UI strings are visibly mojibake in source and must be rewritten as valid UTF-8.
- Source import is not proven on-device with realistic Legado/Yuedu source sets.
- Search is not proven with real imported enabled sources.
- Reader parity is incomplete: overlays, settings panel, gestures, source switching, TTS, auto-scroll, chapter navigation, and progress behavior must match the Flutter app.
- The interface has native smoothness, but several screens diverge from the Flutter screenshots and original layout.

## Product Baseline

### Visual source of truth

Screenshots provided by the user define the initial visible baseline:

- Home screen:
  - Large title: `主页`
  - Top trailing controls: folder-plus import icon and circular profile icon
  - Sections in order: `正在阅读`, `最新更新`, `书架`
  - Empty states:
    - `暂无阅读记录`
    - `暂无更新书籍`
  - Bottom tabs: `主页`, `发现`, `设置`
  - Purple selected tab tint
  - Light iOS Podcasts-like background and spacing
- Discover screen:
  - Large title: `发现`
  - Segmented control: `找书`, `订阅`, `写源`
  - Search field placeholder: `搜索书名或作者`
  - Blue button: `智能网页小说模式`
  - Purple card: `书源管理` with subtitle `导入、测试、验证和管理网络书源`
  - Segmented control: `模糊`, `精准`
  - Section title: `搜索结果`
  - Empty state: `输入书名后，会从启用的小说书源里搜索`

### Flutter files used as baseline

- `origin/main:lib/features/home/views/home_page.dart`
- `origin/main:lib/features/bookshelf/views/bookshelf_page.dart`
- `origin/main:lib/features/explore/views/explore_page.dart`
- `origin/main:lib/features/reader/views/reader_page.dart`
- `origin/main:lib/features/reader/widgets/reader_settings_panel.dart`
- `origin/main:lib/features/settings/views/settings_page.dart`
- `origin/main:lib/features/settings/views/source_management_page.dart`

### Swift files to replace or heavily refactor

- `D:\Gemini反重力\SourceReadSwift\SourceReadSwift\App\RootTabView.swift`
- `D:\Gemini反重力\SourceReadSwift\SourceReadSwift\Features\Bookshelf\BookshelfView.swift`
- `D:\Gemini反重力\SourceReadSwift\SourceReadSwift\Features\Discover\DiscoverView.swift`
- `D:\Gemini反重力\SourceReadSwift\SourceReadSwift\Features\SourceManager\SourceManagerView.swift`
- `D:\Gemini反重力\SourceReadSwift\SourceReadSwift\Features\Settings\SettingsView.swift`
- `D:\Gemini反重力\SourceReadSwift\SourceReadSwift\Features\Reader\ReaderView.swift`
- `D:\Gemini反重力\SourceReadSwift\SourceReadSwift\Core\Storage\SourceStore.swift`
- `D:\Gemini反重力\SourceReadSwift\SourceReadSwift\Core\Engine\SourceEngine.swift`

## Design Approach

### Recommended approach: parity-first rebuild

Implement the Swift app page by page against Flutter parity checklists:

1. First restore the visible product shell and navigation.
2. Then restore the source/import/search flow.
3. Then restore reader behavior.
4. Then harden source compatibility and diagnostics.
5. After each stage, build with GitHub Actions and produce an unsigned IPA when meaningful.

This is the chosen approach because it directly addresses the user's rejection: the problem is not only missing code, but loss of product identity and daily-use flows.

### Rejected approach: continue patching the current Swift prototype

This was already tried and produced a buildable but unacceptable half-product. Continuing in this mode risks more drift from Flutter.

### Rejected approach: copy only core engine and invent a fresh Swift UI

This conflicts with the user's requirement. The app can look smoother, but the layout and flows must remain based on the Flutter iOS Podcasts-style app.

## UI and UX Rules

- Use SwiftUI with native iOS idioms.
- Preserve the iOS Podcasts-style hierarchy:
  - Large titles
  - Cupertino-like segmented controls
  - Bottom tab bar with three items
  - Large section headings with chevrons
  - Large whitespace, rounded cards, soft surfaces
- Use one consistent icon language: SF Symbols.
- Touch targets must be at least 44x44 pt.
- Respect safe areas and the home indicator.
- Support light and dark mode from the start.
- Use dynamic type where practical.
- Use animation only to improve continuity:
  - Section/card entrance may be subtle.
  - Reader overlays should fade/slide like the Flutter version.
  - Avoid decorative animations that change layout identity.

## Page Parity Checklist

### Root tabs

Required:

- Three tabs only:
  - `主页` with house icon
  - `发现` with grid icon
  - `设置` with gear icon
- Selected tint uses the same purple family as the Flutter app.
- Each tab preserves its own navigation stack.
- Chinese text must be valid UTF-8 in source and runtime.

Acceptance:

- Screenshot comparison shows the bottom tab layout matches the Flutter screenshots structurally.
- No mojibake appears anywhere.

### Home / Bookshelf

Required:

- Large title `主页`.
- Top-right local-book import button using folder-plus style.
- Top-right circular profile placeholder.
- Pull to refresh.
- Sections in order:
  1. `正在阅读`
  2. `最新更新`
  3. `书架`
- `正在阅读`:
  - Empty: centered `暂无阅读记录`.
  - Non-empty: horizontal large reading cards with cover, progress, title, author, `继续阅读`, delete action.
- `最新更新`:
  - Empty: centered `暂无更新书籍`.
  - Non-empty: vertical list with cover, title, author, update chapter indicator.
- `书架`:
  - Tapping navigates to complete library view.
- Local import:
  - Supports document picker.
  - Imports local TXT/EPUB where current core supports it.
  - Opens reader after successful import.
  - Shows recoverable error dialogs.

Acceptance:

- Empty Home matches `IMG_7890.PNG` layout.
- A local imported book appears in `正在阅读` or `书架`.
- Returning from reader preserves progress.

### Discover

Required:

- Large title `发现`.
- Segmented control:
  - `找书`
  - `订阅`
  - `写源`
- `找书` tab:
  - Search field placeholder `搜索书名或作者`.
  - Submitted search runs against enabled book sources.
  - Blue `智能网页小说模式` button.
  - Purple `书源管理` card.
  - Right-aligned `模糊 / 精准` segmented control.
  - Section title `搜索结果`.
  - Empty state `输入书名后，会从启用的小说书源里搜索`.
  - Searching state with progress and cancel.
  - Error state with useful failed-source details, not raw crashes.
  - Search result rows show cover, title, author, source, summary, plus/add action.
- `订阅` tab:
  - Lists RSS sources.
  - Empty state links to source manager.
- `写源` tab:
  - Entry card to Web source creation flow.

Acceptance:

- Empty Discover matches `IMG_7891.PNG` layout.
- With imported sources, searching a book returns real results or a clear per-source failure summary.
- Add button inserts a book into bookshelf and can open reader.

### Source Manager

Required:

- Title should match original: `源管理` or `书源管理` consistently.
- Top trailing:
  - `管理` / `完成` when items exist.
  - Add/import button.
- Web source editor service card:
  - Start/stop local editor service if supported in Swift.
  - Show URL/access token if available.
  - If not implemented yet, show a disabled state with clear reason and no broken controls.
- Segmented control:
  - `书源`
  - `仓库`
  - `RSS`
- Search field: `搜索名称、地址、分组`.
- Import sheet supports:
  - Paste JSON
  - Local JSON/TXT file
  - HTTP(S) URL
  - Yuedu/Legado share links where possible
  - Wrapped source arrays and common exported formats
- Book source rows:
  - Name
  - URL/group
  - Enabled/disabled state
  - Edit JSON
  - Diagnostic
  - Test source
  - Delete
- Manage mode:
  - Select all
  - Invert selection
  - Test selected sources
  - Enable
  - Disable
  - Delete with confirmation

Acceptance:

- User can import the same source JSON used by Flutter.
- Imported sources persist after app restart.
- Source list count is correct.
- At least enable/disable/delete/test work from UI.

### Settings

Required:

- Large title `设置`.
- Grouped iOS list sections:
  - `外观`
    - `跟随系统`
    - `浅色模式`
    - `深色模式`
    - `护眼模式`
  - `内容设置`
    - `书源管理`
    - `规则净化`
  - `通用`
    - `清理缓存`
    - `阅读历史`
    - `关于阅读`
- Checkmarks reflect current selection.
- Cache size is calculated and clearable.

Acceptance:

- Theme changes apply without restart.
- Source manager is reachable from Settings and Discover.

### Reader

Required:

- Immersive reading view.
- Supports scroll mode and page modes:
  - `滑动`
  - `平移`
  - `覆盖`
- Tap zones:
  - 3x3 configurable zones.
  - Default includes previous page, next page, menu.
  - At least one menu zone must remain.
- Reader overlay:
  - Top bar with back, title/chapter, detail/more actions.
  - Bottom bar with:
    - Previous chapter
    - Current chapter/page progress
    - Next chapter
    - `目录`
    - `换源`
    - `朗读`
    - `自动`
    - `设置`
- Settings panel:
  - Sheet height and rounded top like Flutter.
  - Tabs:
    - `外观`
    - `排版`
    - `高级`
  - Appearance:
    - Font size slider
    - Background colors
    - Custom wallpaper where feasible
  - Layout:
    - Font size
    - Letter spacing
    - Title spacing
    - Page padding
    - Top/bottom padding
    - Line height
    - Paragraph spacing
    - Indent
    - Footer height
    - Font weight
  - Advanced:
    - Page mode segmented control
    - Tap zone editor
    - Keep screen on
    - Volume-key page turn if platform implementation allows
    - Justified text
- TOC:
  - Open chapter list.
  - Jump to selected chapter.
- Source switching:
  - Search enabled sources for same book.
  - Show candidates.
  - Switch source and keep nearest chapter when possible.
- TTS:
  - At minimum expose the same UI.
  - If engine support is incomplete, feature must fail gracefully with a clear message.
- Auto-scroll:
  - Toggle auto-scroll.
  - Preserve smoothness and allow immediate cancellation.
- Progress:
  - Save on scroll/page change, background, and exit.
  - Restore on re-entry.
- Exit handling:
  - If opened from search and not favorited, ask whether to add to bookshelf.

Acceptance:

- A searched network book opens readable chapter content.
- Reader settings visibly change the current page immediately.
- Progress restores after closing and reopening.
- Overlay and tap zones work without blocking text selection.

## Core Source Compatibility

Swift source compatibility must target common Legado/Yuedu fields from the Flutter implementation:

- Search:
  - `ruleSearch`
  - name/author/bookUrl/cover/intro/kind/lastChapter rules
- Detail:
  - `ruleBookInfo`
- TOC:
  - `ruleToc`
- Content:
  - `ruleContent`
- Encoding:
  - UTF-8
  - GBK/GB18030 when response headers or content require it
- Imports:
  - Plain array of sources
  - Wrapped object with source list field
  - Repository catalog JSON
  - RSS/Atom where existing Flutter supports it

Acceptance:

- A realistic imported source set can search more than one source.
- Per-source failures are visible in diagnostics.
- A failed source cannot break all search.

## Diagnostics and Testability

Required diagnostics:

- Import result:
  - Added count
  - Updated count
  - Ignored count
  - Error summary
- Search diagnostics:
  - Sources checked
  - Sources hit
  - Results count
  - First N failures with source name and reason
- Source test:
  - Search test
  - Detail test
  - TOC test
  - Content test
- Reader diagnostics:
  - Current source
  - Chapter URL
  - Load error with recovery path

## Build and Delivery Workflow

Because the user only has Windows, local iOS building is not required. Build verification uses GitHub Actions on macOS.

Required after each meaningful implementation stage:

1. Commit changes.
2. Push branch.
3. Run iOS CI.
4. Run unsigned IPA workflow when the app is worth device testing.
5. Report:
   - Commit SHA
   - Workflow URL
   - Artifact name
   - What changed
   - What is still not done

## Implementation Stages

### Stage 0: UTF-8 and product shell recovery

- Rewrite visible Swift strings to valid UTF-8.
- Restore tab labels and titles.
- Build shared UI primitives:
  - Large title scaffold
  - Section title with chevron
  - Empty state
  - Rounded card
  - Purple action card
  - Search field wrapper
- Acceptance: no mojibake; root/Home/Discover match empty screenshots structurally.

### Stage 1: Home and Discover visual parity

- Rebuild Home against screenshot and Flutter baseline.
- Rebuild Discover against screenshot and Flutter baseline.
- Keep current native smoothness with subtle SwiftUI transitions.
- Acceptance: visual parity for empty states and tabs.

### Stage 2: Source import and management parity

- Replace provisional Source Manager with full segmented manager.
- Implement import sheet and file/URL/paste parsing.
- Add enable/disable/delete/test basics.
- Acceptance: real source JSON import works on device and persists.

### Stage 3: Search to bookshelf to detail/reader flow

- Harden concurrent search.
- Improve result rows.
- Add to bookshelf.
- Open detail/reader.
- Acceptance: real imported sources can produce search results and open a readable book.

### Stage 4: Reader parity

- Rebuild reader overlay, bottom toolbar, settings sheet, tap zones, TOC, progress.
- Implement immediate setting changes.
- Acceptance: daily reading of local and network books is usable.

### Stage 5: Diagnostics, polish, and AppStore-level cleanup

- Improve errors and diagnostics.
- Add accessibility labels.
- Verify dark mode and Dynamic Type.
- Remove dead controls.
- Confirm CI and unsigned IPA.

## Non-negotiable Acceptance Criteria

The project is not considered done until:

- No visible mojibake remains.
- Home empty state matches `IMG_7890.PNG` structurally.
- Discover empty state matches `IMG_7891.PNG` structurally.
- Source import works from file, paste, and URL for realistic source JSON.
- Imported sources persist after restart.
- Search works with real enabled imported sources.
- Search result can be added to bookshelf.
- A network book can open readable content.
- Reader overlay/settings/tap zones/progress match the Flutter app's behavior.
- CI passes on GitHub Actions.
- Unsigned IPA artifact is produced for user self-signing.

## Explicit Out of Scope Until Parity Is Restored

- Inventing a new UI direction.
- Adding new non-Flutter features just because Swift makes them easy.
- Treating CI green as a product milestone by itself.
- Shipping controls that look enabled but do nothing.
- Replacing broken behavior with placeholder success messages.

## Next Step After Approval

After this design is approved, create an implementation plan starting with Stage 0 and Stage 1. The first code milestone should only target:

- UTF-8 cleanup.
- Root tabs.
- Home empty-state parity.
- Discover empty-state parity.
- Shared native UI components that preserve the Flutter layout.

