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
