# Reader UI Notes

## Scope

Reader UI work is limited to interaction and presentation behavior. It does not change book sources, parser rules, bridge code, source-engine services, or network request behavior.

## Text Layout

- Novel reader body text uses the reader's own font-size setting and is isolated from the app-wide text scaler.
- Chapter titles are rendered as full-width centered titles in scroll and paged reading modes.
- HTML chapter content follows the same font-family fallback as plain text content when no custom font is selected.

## Theme Presets

- Reader theme presets apply background color and body text color together.
- Custom background images remain available from the add-style entry.
- Reader settings opened from profile use the same body text color setting as the reader page.

## Detail Cache Entry

- The detail-page cache action opens the chapter list in cache-management mode.
- Cache-management mode is UI-only: it shows the existing cached chapter count and keeps the chapter-row cloud marker for uncached online chapters.
- This behavior does not start batch downloads and does not change book-source, parser, bridge, source-engine, or network request logic.

## Chapter List Cache

- Detail and chapter-list pages save the refreshed chapter list into the existing app cache store after a successful directory load.
- When a later directory refresh fails, the pages keep showing the cached chapter list instead of dropping to an empty directory.
- The cache stores chapter metadata only; it does not cache body content and does not change parser, book-source, bridge, or network behavior.

## Search Results Cache

- The search page reuses cached results for the same keyword and selected source set while a fresh search is running.
- Fresh search results replace the cached display after the first successful source returns data, then overwrite the cache after the search finishes.
- The cache stores search-result metadata only and does not change source selection, parser rules, bridge code, or network request behavior.
- Detail pages can use cached search-result metadata as a fallback book record when no bookshelf record or route-provided book data is available.

## Multi-Source Search

- Search loads all enabled searchable sources as the default selected source set.
- Searches continue to use the existing bounded worker pool and show selected source progress, worker count, and result count while running.
- This changes search UI state and selection behavior only; it does not change source parsing, bridge code, or network request implementation.

## Group Search

- The search page shows source-group shortcuts under the search bar.
- Tapping a group selects only that group and searches the current keyword; tapping all sources restores the full selected source set.
- Group search reuses the existing source selection and bounded worker pool, without changing parser, bridge, source-engine, or network behavior.

## Search Interaction Components

- The search source-scope bar is presented as a compact horizontal control with clear selected state, bounded label width, and tooltips for long group names.
- The source-scope control keeps the existing behavior: selecting all sources or a group only changes the selected source set and reruns the current keyword when one exists.
- The search progress indicator is shown as a compact status bar while searching, with source progress, active worker count, result count, and a determinate bar when total source count is known.
- The source-selection dialog is kept as an advanced "source pick" entry for manual source combinations; normal all-source and group searches are handled by the compact scope bar.
- The source-pick dialog highlights the selected/total source count and applies the current search-field keyword after confirmation when sources remain selected.
- Source-pick group rows use a compact header layout for expand/collapse, selected count, group-only search, and whole-group selection.
- Source-pick source rows use compact single-line rows with source type, source name, and selected state indicators.
- Search result list rows present title, author, latest chapter, intro, source, and tags with clearer hierarchy and bounded source/tag labels.
- Search result grid cards use stronger title/chapter hierarchy and a bounded source pill while keeping the existing cover and tap behavior.
- Chapter-list cache management uses a compact summary bar with cached/total count, a progress indicator, and a cloud-marker hint for uncached chapters.
- This is UI polish only and does not change search parsing, bridge code, source-engine services, or network request behavior.
