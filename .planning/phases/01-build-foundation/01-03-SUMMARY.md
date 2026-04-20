---
phase: 01-build-foundation
plan: "03"
subsystem: build-verification
tags: [cargo, xcodebuild, ffi, aarch64, cbindgen, static-library, verification]

dependency_graph:
  requires:
    - phase: 01-01
      provides: manzo-core staticlib with 11 FFI stubs, manzo_core.h, libmanzo_core.a (arm64)
    - phase: 01-02
      provides: ManzoApp Xcode project with cargo run-script, linker flags, bridging header
  provides:
    - Phase 1 gate verification: all 8 acceptance criteria pass
    - Proven end-to-end Rust-to-Swift FFI link via xcodebuild
  affects: [Phase 2 audio pipeline — green field on this foundation]

tech-stack:
  added: []
  patterns:
    - cbindgen invocation must use (cd <crate-dir> && cbindgen --config cbindgen.toml --output ...) not --crate <path>
    - xcodebuild PhaseScriptExecution fires cargo build before Swift compile — confirmed working

key-files:
  created: []
  modified:
    - ManzoApp/project.yml
    - ManzoApp/ManzoApp.xcodeproj/project.pbxproj

key-decisions:
  - "cbindgen run-script invocation uses subshell cd pattern, not --crate flag — --crate expects crate name, not directory path"

patterns-established:
  - "Gate plans produce only a SUMMARY — no code created, only evidence collected"

requirements-completed: [BUILD-01, BUILD-02, BUILD-03]

duration: 2min
completed: "2026-04-20"
---

# Phase 1 Plan 03: Build Verification Gate Summary

**Full end-to-end build verification: cargo test 4/4, libmanzo_core.a arm64, all 11 FFI symbols linked in ManzoApp binary, xcodebuild exits 0 with run-script invoking cargo automatically.**

## Performance

- **Duration:** 2 min
- **Started:** 2026-04-20T16:03:59Z
- **Completed:** 2026-04-20T16:05:59Z
- **Tasks:** 2
- **Files modified:** 2 (bug fix only — project.yml + generated project.pbxproj)

## Accomplishments

- Confirmed cargo test passes 4/4 unit tests on aarch64-apple-darwin target
- Confirmed libmanzo_core.a is arm64-only (non-fat)
- Confirmed manzo_core.h has all 11 manzo_* function declarations with MANZO_CORE_H include guard
- Fixed cbindgen invocation bug in run-script (--crate <dir> → cd + cbindgen form)
- Confirmed xcodebuild exits 0, run-script fires cargo build, 0 undefined manzo_* symbols, all 11 FFI symbols defined in linked binary, binary is arm64

## Verification Evidence

### Task 1: cargo test + static library + header

| Check | Command | Result |
|-------|---------|--------|
| cargo test passes | `cargo test --target aarch64-apple-darwin` | `test result: ok. 4 passed; 0 failed` |
| libmanzo_core.a is arm64 | `lipo -info libmanzo_core.a` | `Non-fat file ... is architecture: arm64` |
| libmanzo_core.a has no x86_64 | same lipo output | No x86_64 slice present |
| 11 functions in header (for-loop) | `for fn in manzo_open ... do grep -q; done` | All 11: OK |
| MANZO_CORE_H include guard | `grep MANZO_CORE_H manzo_core.h` | `#ifndef MANZO_CORE_H`, `#define MANZO_CORE_H`, `#endif  /* MANZO_CORE_H */` |

### Task 2: xcodebuild end-to-end + FFI link

| Check | Command | Result |
|-------|---------|--------|
| xcodebuild exits 0 | `xcodebuild build ...` | `** BUILD SUCCEEDED **` |
| Run-script fired | `PhaseScriptExecution Build Rust manzo-core` in log | Confirmed |
| Run-script contains cargo build | Script-*.sh content | `cargo build --release --target aarch64-apple-darwin` present |
| No undefined manzo_* symbols | `nm ManzoApp | grep " U " | grep "manzo_"` | `NO_UNDEFINED_MANZO_SYMBOLS` |
| All 11 FFI symbols linked | for-loop nm check | All 11: LINKED |
| Binary is arm64 | `file ManzoApp.app/.../ManzoApp` | `Mach-O 64-bit executable arm64` |

## Phase 1 Gate Checklist

```
[x] cargo test --target aarch64-apple-darwin: 4 tests pass, exit 0
[x] lipo -info libmanzo_core.a: reports arm64
[x] manzo_core.h: 11 manzo_* declarations + MANZO_CORE_H guard
[x] xcodebuild build: exits 0, prints "BUILD SUCCEEDED"
[x] xcodebuild log: contains PhaseScriptExecution "Build Rust manzo-core" (run-script fired)
[x] nm ManzoApp binary: 0 undefined manzo_* symbols
[x] nm ManzoApp binary: 11 defined manzo_* symbols
[x] file ManzoApp binary: arm64
```

All 8 gate criteria: PASSED.

## Task Commits

1. **Bug fix: cbindgen invocation** - `8fb41d3` (fix)

**Plan metadata:** *(docs commit — added below after STATE.md update)*

## Files Created/Modified

- `ManzoApp/project.yml` — Fixed cbindgen run-script: `--crate <dir>` replaced with `(cd <dir> && cbindgen --config cbindgen.toml --output manzo_core.h)`
- `ManzoApp/ManzoApp.xcodeproj/project.pbxproj` — Regenerated via `xcodegen generate` after project.yml fix

## Decisions Made

- cbindgen `--crate` flag expects a crate name, not a directory path. Passing `"$SRCROOT/../manzo-core"` caused `cargo metadata` to look for `Cargo.toml` in the Xcode project directory instead of the Rust crate. The `(cd <dir> && cbindgen ...)` subshell pattern is the correct form when the manifest is not in the current directory.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed cbindgen --crate path error in Xcode run-script**
- **Found during:** Task 2 (xcodebuild end-to-end)
- **Issue:** Run-script used `cbindgen --crate "$SRCROOT/../manzo-core"` — the `--crate` flag expects a crate name string, not a directory path. cbindgen executed `cargo metadata` against the current working directory (`ManzoApp/`) looking for `Cargo.toml`, which does not exist, causing `PhaseScriptExecution` to exit nonzero and BUILD FAILED.
- **Fix:** Changed to `(cd "$SRCROOT/../manzo-core" && cbindgen --config cbindgen.toml --output manzo_core.h)` in both `project.yml` and the regenerated `project.pbxproj`
- **Files modified:** `ManzoApp/project.yml`, `ManzoApp/ManzoApp.xcodeproj/project.pbxproj`
- **Verification:** xcodebuild BUILD SUCCEEDED; all 11 FFI symbols present in linked binary
- **Committed in:** `8fb41d3` (fix(01-03): correct cbindgen invocation in run-script)

---

**Total deviations:** 1 auto-fixed (1 Rule 1 bug)
**Impact on plan:** Necessary correctness fix. The cbindgen invocation pattern from plan 01-02 was wrong; this is the correct pattern for all future run-scripts that invoke cbindgen against a non-cwd crate.

## Issues Encountered

The initial xcodebuild invocation failed with `Couldn't execute cargo metadata with manifest .../ManzoApp/Cargo.toml does not exist`. This was diagnosed as the cbindgen `--crate` flag misuse documented above.

## Known Stubs

None introduced in this plan. All 11 FFI stubs are pre-existing intentional stubs from plan 01-01.

## Threat Flags

No new threat surface. Build log written to `/tmp/xcodebuild_manzo.log` (developer-local temp file, accepted per T-01-07 in the plan's threat model). No credentials in build output.

## Next Phase Readiness

Phase 1 is complete. All gate criteria pass. Phase 2 (Audio Pipeline) can begin:
- `manzo-core/` Rust crate is ready for real audio implementation (mpg123, cpal/CoreAudio)
- `ManzoApp.xcodeproj` will auto-trigger cargo build on every Xcode build — no manual steps needed
- All 11 FFI stubs are in place; Phase 2 will replace them with real implementations

## Self-Check: PASSED

- 01-03-SUMMARY.md: FOUND
- commit 8fb41d3 (fix cbindgen invocation): FOUND
- ManzoApp/project.yml (cbindgen fix): FOUND
- ManzoApp/ManzoApp.xcodeproj/project.pbxproj (regenerated): FOUND

---
*Phase: 01-build-foundation*
*Completed: 2026-04-20*
