---
phase: 01-build-foundation
plan: "02"
subsystem: xcode-swift-ffi
tags: [xcode, swift, appkit, xcodegen, ffi, bridging-header, static-library, arm64]

dependency_graph:
  requires:
    - phase: 01-01
      provides: libmanzo_core.a static library and manzo_core.h C header (11 FFI stubs)
  provides:
    - ManzoApp Xcode project with run-script pre-build phase invoking cargo build --release
    - Swift bridging header importing manzo_core.h
    - AppDelegate.swift with manzo_play(nil) FFI smoke test
    - Linker settings wiring libmanzo_core.a into Swift binary
  affects: [01-03-PLAN.md (xcodebuild end-to-end validation), Phase 2 audio pipeline Swift side]

tech-stack:
  added: [xcodegen 2.45.4, AppKit/Swift 5.10, ManzoApp.xcodeproj]
  patterns:
    - xcodegen project.yml for reproducible Xcode project generation
    - PBXShellScriptBuildPhase runs cargo build --release before Swift compile
    - LIBRARY_SEARCH_PATHS + OTHER_LDFLAGS = -lmanzo_core for static library linking
    - HEADER_SEARCH_PATHS → manzo-core/ for bridging header resolution
    - Bridging header with relative #include path to cbindgen-generated C header

key-files:
  created:
    - ManzoApp/project.yml
    - ManzoApp/ManzoApp.xcodeproj/project.pbxproj
    - ManzoApp/ManzoApp/main.swift
    - ManzoApp/ManzoApp/AppDelegate.swift
    - ManzoApp/ManzoApp/ManzoApp-Bridging-Header.h
    - ManzoApp/ManzoApp/Info.plist
  modified: []

key-decisions:
  - "Used xcodegen (installed via brew) rather than hand-crafting project.pbxproj — reproducible and diff-friendly"
  - "Bridging header uses relative path #include ../manzo-core/manzo_core.h — HEADER_SEARCH_PATHS in build settings resolves it (T-01-06 mitigation)"
  - "Pre-build script runs cbindgen re-generation conditionally (if command -v cbindgen) — header stays fresh on incremental builds"

patterns-established:
  - "xcodegen project.yml is the source of truth for Xcode settings — never hand-edit project.pbxproj"
  - "FFI smoke test in AppDelegate.applicationDidFinishLaunching: call stub, assert result == 0, NSLog confirmation"

requirements-completed: [BUILD-01, BUILD-02, BUILD-03]

duration: 1m
completed: "2026-04-20"
---

# Phase 1 Plan 02: ManzoApp Xcode Project Summary

**AppKit Xcode project generated via xcodegen with run-script cargo build, libmanzo_core.a linker wiring, and Swift bridging header importing the cbindgen C FFI surface.**

## Performance

- **Duration:** 1 min
- **Started:** 2026-04-20T16:00:33Z
- **Completed:** 2026-04-20T16:01:50Z
- **Tasks:** 1
- **Files modified:** 6

## Accomplishments

- ManzoApp.xcodeproj generated from project.yml with all required build settings
- Pre-build run-script phase: `cargo build --release --target aarch64-apple-darwin` fires automatically before Swift compile
- ManzoApp-Bridging-Header.h imports `../manzo-core/manzo_core.h` (relative path, HEADER_SEARCH_PATHS resolves)
- AppDelegate.swift calls `manzo_play(nil)` and asserts result == 0 — Phase 1 FFI smoke test
- MACOSX_DEPLOYMENT_TARGET = 15.0, ARCHS = arm64, OTHER_LDFLAGS = -lmanzo_core all set

## Task Commits

1. **Task 1: Create ManzoApp Xcode project** - `b3e5b8d` (feat)

## Files Created/Modified

- `ManzoApp/project.yml` — xcodegen spec (source of truth for project settings)
- `ManzoApp/ManzoApp.xcodeproj/project.pbxproj` — generated Xcode project with run-script, linker flags, header search paths
- `ManzoApp/ManzoApp/main.swift` — NSApplication entry point
- `ManzoApp/ManzoApp/AppDelegate.swift` — FFI smoke test: manzo_play(nil) call with assertion
- `ManzoApp/ManzoApp/ManzoApp-Bridging-Header.h` — imports manzo_core.h via relative path
- `ManzoApp/ManzoApp/Info.plist` — generated app bundle metadata (macOS 15+)

## Decisions Made

- Used xcodegen rather than hand-crafting project.pbxproj — generates reproducible, reviewable output and avoids UUID drift
- Bridging header uses `#include "../manzo-core/manzo_core.h"` (relative) rather than absolute path — pairs with HEADER_SEARCH_PATHS for deterministic resolution (T-01-06 mitigation from threat model)
- cbindgen re-generation inside the run-script is conditional (`if command -v cbindgen`) — safe in CI environments without cbindgen installed

## Deviations from Plan

### Auto-fixed Issues

None - plan executed exactly as written. xcodegen was unavailable but was installed via `brew install xcodegen` as specified in the plan's primary approach (this is expected plan flow, not a deviation).

## Issues Encountered

None. xcodegen installed cleanly, project.yml generated correct pbxproj on first run. All acceptance criteria passed immediately.

## Known Stubs

No stubs introduced in this plan. All Swift source is minimal and intentional: AppDelegate calls manzo_play(nil) stub from Phase 1 Rust crate; there is no UI to stub out (deferred to Phase 5).

## Threat Flags

No new threat surface beyond the plan's threat model. T-01-06 (bridging header #include path spoofing) is mitigated: relative path + HEADER_SEARCH_PATHS via Xcode build settings, as designed.

## Next Phase Readiness

- ManzoApp.xcodeproj is ready for `xcodebuild` end-to-end validation (Plan 01-03)
- Wave 3 can run: `xcodebuild -project ManzoApp/ManzoApp.xcodeproj -scheme ManzoApp -configuration Release build`
- Expected: cargo build triggers automatically, libmanzo_core.a links, Swift compiles, xcodebuild exits 0

## Self-Check: PASSED

All 7 files verified present on disk. Commit b3e5b8d verified in git log.

---
*Phase: 01-build-foundation*
*Completed: 2026-04-20*
