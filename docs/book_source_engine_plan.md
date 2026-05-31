# Book Source Engine Plan

## Goal

Make the app compatible with common Legado / open-source 阅读 book sources:

- Import single book source JSON.
- Import book source collections.
- Import source repository subscription JSON.
- Keep RSS feeds separate from book source repositories.
- Search books, open detail, load chapters, and read chapter content from enabled sources.

## Phase 1: Source Type Separation

- Add a dedicated `SourceCatalog` model for book source repositories.
- Split management UI into Book Sources, Source Catalogs, and RSS.
- Detect import content automatically:
  - `bookSourceName` means book source.
  - RSS rule fields or feed-like URL means RSS.
  - source repository metadata means source catalog.
- Show Cloudflare/HTML/blocked responses as clear import failures.

## Phase 2: Rule Parser Core

- Extract request building from parsing:
  - URL variable replacement.
  - page/key/source variables.
  - GET/POST/body/header/cookie.
  - charset decoding.
- Extract rule evaluation:
  - JSONPath.
  - CSS selector.
  - XPath.
  - regex and replacement.
  - alternative rules and fallbacks.

## Phase 3: Legado JS Runtime

- Add a JS runtime boundary for `@js:` and `<js>`.
- Provide common 阅读 host APIs:
  - `java.get`
  - `java.post`
  - `java.ajax`
  - `java.log`
  - JSON helpers
  - hash/base64 helpers
- Mark unsupported APIs explicitly instead of failing silently.

## Phase 4: Source Repository Experience

- Tap a catalog to fetch and preview available book sources.
- Support search/filter/group inside a catalog.
- Support import selected, import all, overwrite, and skip duplicates.
- Show per-source test status.

## Phase 5: Compatibility Testing

- Maintain a fixture set for:
  - plain JSON API sources.
  - HTML/CSS/XPath sources.
  - JS-heavy Legado sources.
- Test the four core steps:
  - search.
  - book detail.
  - chapter list.
  - chapter content.

## Non-goals

- Do not bypass Cloudflare, captcha, login walls, or paid access controls.
- Do not bundle third-party book sources in the app package.
