# MR function absorption notes

## Business conclusion

MR should be used as a function-completeness reference, not as the UI baseline. The Swift line should keep the current iOS/Podcasts visual direction and absorb MR's source debugging, source locating, rule parsing, and reader action coverage where they directly improve daily reading.

## Useful MR capabilities

1. Source debug trace
   - MR records search/detail/TOC/content stages with status codes and cached source HTML.
   - Swift already has diagnostic events and source-chain tests; next step is to add per-stage raw response snippets/export when a source fails.

2. AnalyzeUrl compatibility
   - MR parses Legado page placeholders, variables, POST options, relative URLs, headers, and body payloads.
   - Swift already fixed legacy POST body interpolation and now follows paged TOC/content. Remaining gap: broader option parsing and JS/java bridge helpers.

3. Source locating
   - MR can locate candidate sources by `bookUrlPattern` and order them by weight.
   - Swift source switching should absorb this so books can find replacement sources without brute-force scanning every source first.

4. Metadata merge
   - MR preserves useful search-result fields when detail pages return partial metadata.
   - Swift detail loading should avoid replacing cover/author/intro/latest chapter with empty detail fields.

5. Reader action coverage
   - MR reader overlay exposes change source, refresh, cache/download, bookmark, catalog, TTS, interface, settings, chapter URL/detail actions.
   - Swift reader already has catalog/TTS/auto/settings/bookmark/source switch in part; refresh/cache/detail/source-edit are still missing.

## Immediate Swift priority

1. Keep the UI native and glass-based.
2. Improve source testing export and raw diagnostics before adding more engine branches.
3. Add source locating by `bookUrlPattern` and weight.
4. Add safe metadata merge in detail flow.
5. Add reader refresh/cache actions after the current UI shell is stable.

## Risks

- Copying MR's whole Flutter engine into Swift would duplicate complexity and fight the chosen Swift-native direction.
- Adding JS/java bridge compatibility without diagnostics will make failures harder to explain.
- Mixing large engine changes with UI shell changes increases CI red-point risk.

