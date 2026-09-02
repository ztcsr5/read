# Native iOS Performance and Reader Features Design

## Goal

Advance SourceReadSwift from the current SwiftUI MVP to a smooth native iOS reader while preserving Legado compatibility and Flutter product parity. The first priority is frame pacing: ProMotion devices should be allowed to run at up to 120 Hz, while 60 Hz devices continue to use their native ceiling without unnecessary work.

## Scope

1. Global native frame-rate coordination and performance instrumentation.
2. EPUB parsing, chapter navigation, caching, and reading progress.
3. RSS/Atom list and article reading flow.
4. Book-source detail fixtures, diagnostics, and rule-editor preview.
5. Reader text-to-speech and automatic page/scroll advance.
6. Remaining high-value Flutter behavior parity.

## Architecture

- Keep SwiftUI as the UI layer and `SourceEngine` as the source boundary.
- Add a small UIKit-backed `FrameRateCoordinator` attached at the app/window level. It requests the highest supported preferred frame rate without assuming every device is ProMotion-capable.
- Keep expensive parsing, pagination, EPUB extraction, and fixture execution off the main actor. Publish only small immutable view models to SwiftUI.
- Replace broad reader invalidation with scoped state updates. Cache pagination by content/layout key and avoid rebuilding unchanged chapter surfaces.
- Reuse the existing reader container for EPUB and RSS article content after normalization into `ChapterContent`-like models.
- Use `AVSpeechSynthesizer` behind a testable `ReaderSpeechController` and keep speech state independent from page layout state.

## Performance acceptance criteria

- ProMotion-capable devices request up to 120 Hz through the native window/presentation path.
- Non-ProMotion devices do not receive unsupported frame-rate assumptions.
- Reader page turns, bookshelf scrolling, tab switching, and rule-editor typing avoid avoidable full-tree rebuilds.
- No synchronous network, EPUB decompression, HTML parsing, or JavaScript evaluation occurs on the main actor.
- Add signposts/metrics for reader layout, source request, parser, image decode, and chapter transition paths.
- CI remains green on every coherent milestone; device-level FPS remains explicitly marked for iPhone verification.

## Delivery order

1. Frame-rate coordinator, performance metrics, and reader hot-path reductions.
2. EPUB model/parser/cache and progress persistence.
3. Legado fixture corpus and book-source detail test harness.
4. Rule editor with local sample execution and export.
5. RSS/Atom reader flow.
6. Reader speech and automatic advance.
7. Flutter parity cleanup and release packaging.

## Testing

- Add unit fixtures for EPUB variants, RSS/Atom variants, source rules, JavaScript/DOM bridges, and pagination.
- Add deterministic tests for progress, cache invalidation, speech command state, and automatic advance scheduling.
- Use GitHub Actions for iOS build/test and unsigned IPA packaging because development is on Windows.
- Do not claim 120 FPS until an actual ProMotion device measurement is available; CI proves build correctness, not physical refresh rate.

## Rollback

Each delivery slice is isolated in its own commit. Performance coordination can be disabled with a feature flag while retaining metrics and functional behavior. EPUB, RSS, rule editor, and speech additions remain independently revertible.
