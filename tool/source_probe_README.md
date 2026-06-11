# Source Probe

`tool/source_probe.dart` is a reusable batch probe for Legado/Read book-source
JSON files. It is intended for parser regression work: run the same source set
before and after parser changes, then compare failure stages and feature tags.

## Static scan

Static scan does not make network requests. It only loads JSON, keeps novel
sources by default (`bookSourceType == 0`), and reports high-risk rule features.

```powershell
D:\Gemini反重力\flutter\bin\dart.bat run tool/source_probe.dart `
  --dry-run `
  --out build/source_probe_static `
  C:\Users\Edc21\Desktop\11780_51b655a48db62802c20dcb56a8802d4d.json `
  C:\Users\Edc21\Desktop\13841_7d92963fb43a80951a97add38acf5dbc.json
```

## Live probe

Live probe calls the app's real `LegadoParser.testSource`. The CLI starts a
Flutter test runner internally because the parser depends on Flutter/WebView and
QuickJS bindings that do not compile reliably in a plain Dart runner.

```powershell
D:\Gemini反重力\flutter\bin\dart.bat run tool/source_probe.dart `
  --keyword 斗破苍穹 `
  --concurrency 2 `
  --timeout 45 `
  --limit 100 `
  --out build/source_probe_live `
  C:\Users\Edc21\Desktop\11780_51b655a48db62802c20dcb56a8802d4d.json
```

## Outputs

The output directory contains:

- `source_probe_report.json`: full machine-readable report.
- `source_probe_report.csv`: spreadsheet-friendly summary.
- `source_probe_summary.md`: aggregate counts by status, failure step, feature.
- `source_probe_failures.md`: first 200 failing sources with failure logs.

Important columns:

- `status`: `ok`, `fail`, `timeout`, `error`, or `static`.
- `failStep`: failing `testSource` stage, e.g. search URL, search result, toc,
  content.
- `compatHint`: coarse bucket for likely next parser work.
- `features`: static feature tags such as `@js`, `java.ajax`, `webView`,
  `nextContentUrl`, `jsonPath`, `@textNodes`.

## Notes

- Keep `--concurrency` low for live probing. Many sources rate-limit quickly.
- If Windows reports missing `quickjs_c_bridge_plugin.dll`, JS-heavy sources
  will cluster under `searchUrl-js` or related JS failure buckets. That is still
  useful for prioritizing QuickJS packaging/runtime work.
- Reports under `build/` are generated artifacts and are not intended to be
  committed.
