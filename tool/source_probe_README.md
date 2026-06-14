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
- On Windows, the CLI preflights `quickjs_c_bridge_plugin.dll` before starting
  live probing. If it finds a built DLL, it automatically sets
  `LIBQUICKJSC_TEST_PATH` for the Flutter test runner. If it cannot find one,
  JS-heavy sources are marked `BLOCKED / JS 环境` instead of failed to avoid
  false negatives.
- To enable JS source probing on Windows, install CMake and Visual Studio Build
  Tools with the C++ workload, then build the QuickJS native library once:

```powershell
$pkg = Join-Path $env:LOCALAPPDATA 'Pub\Cache\hosted\pub.dev\quickjs_engine-0.1.1'
Set-Location $pkg
powershell.exe -ExecutionPolicy Bypass -File tool\build_native.ps1
```

  The next `tool/source_probe.dart` run should auto-detect
  `native\build\Release\quickjs_c_bridge_plugin.dll`. You can also point to a
  custom copy explicitly:

```powershell
$env:LIBQUICKJSC_TEST_PATH = 'C:\path\to\quickjs_c_bridge_plugin.dll'
```

- Reports under `build/` are generated artifacts and are not intended to be
  committed.
