## 2026-06-26 - Task: Research mr for Flutter absorption

### What was done
- Downloaded `DandanLLab/mr` into `D:\Gemini反重力\references\mr` as a local read-only reference because `git clone` was blocked by the local Git proxy.
- Compared `mr` against the existing Flutter `read` project across source import, Legado rule parsing, JS bridge, source debugging, and reader modules.
- Produced a formal absorption report that keeps `read` UI/product structure as the baseline and treats `mr` as a module-level reference implementation.

### Testing
- Ran local source scans with `rg` and PowerShell against both `D:\Gemini反重力\references\mr` and `D:\Gemini反重力\read`.
- Verified `mr` license is MIT and recorded the licensing requirement in the report.
- No application source code was changed and no Flutter build/test was run in this research-only task.

### Notes
- Changed files:
  - `docs/2026-06-26-mr-flutter-absorption-report.md`: documented the `mr` absorption conclusion, module priorities, phased plan, and risks.
  - `progress.md`: recorded this research/documentation task.
- External reference:
  - `D:\Gemini反重力\references\mr`: local copy of `DandanLLab/mr` for comparison; not part of the `read` repository.
- Rollback: delete `docs/2026-06-26-mr-flutter-absorption-report.md` and this `progress.md` entry/file; optionally remove `D:\Gemini反重力\references\mr` if the local reference is no longer needed.
