---
phase: 02-audio-pipeline
plan: 03
subsystem: audio-core
tags: [rust, integration-test, swift, ffi, appdelegate, coreaudio, mpg123]
dependency_graph:
  requires: [02-02]
  provides: [integration-test-suite, real-appdelegate-playback]
  affects:
    - manzo-core/tests/integration_test.rs
    - manzo-core/Cargo.toml
    - manzo-core/src/lib.rs
    - ManzoApp/ManzoApp/AppDelegate.swift
    - ManzoApp/project.yml
    - ManzoApp/ManzoApp.xcodeproj/project.pbxproj
tech_stack:
  added: [rlib crate-type for integration test linking]
  patterns:
    - extern C integration test via rlib link path
    - mpg123_init() called once per manzo_open (library init idempotent)
    - OpaquePointer handle stored as Swift instance var (T-02-09)
    - Bundle.main path lookup with dev-fixture fallback
key_files:
  created:
    - manzo-core/tests/integration_test.rs
  modified:
    - manzo-core/Cargo.toml
    - manzo-core/src/lib.rs
    - ManzoApp/ManzoApp/AppDelegate.swift
    - ManzoApp/project.yml
    - ManzoApp/ManzoApp.xcodeproj/project.pbxproj
decisions:
  - Added rlib to crate-type alongside staticlib so integration tests can link against the Rust symbols
  - mpg123_init() added to manzo_open — required before mpg123_new; omission caused null return
  - Integration test uses extern C declarations resolved via rlib (not use manzo_core::) — cleaner than re-exporting
  - CoreAudio/AudioUnit/AudioToolbox frameworks added to project.yml dependencies (cpal requirement)
  - libmpg123.dylib copied to stable release path via pre-build script for Xcode linker
  - play_advances_position marked #[ignore] — requires audio hardware, not available in headless CI
metrics:
  duration: 6m
  completed: "2026-04-22T00:14:38Z"
  tasks_completed: 2
  files_modified: 6
---

# Phase 02 Plan 03: Integration Tests + AppDelegate Wiring Summary

**One-liner:** 5-test integration suite via rlib FFI + AppDelegate wired to manzo_open/manzo_play with CoreAudio framework deps resolved in project.yml.

## What Was Built

### Task 1: Rust Integration Tests

`manzo-core/tests/integration_test.rs` contains 5 tests exercising the full FFI surface:

- `open_returns_non_null_for_valid_mp3` — manzo_open with `tests/fixtures/test.mp3` returns non-null handle; manzo_close doesn't crash
- `open_returns_null_for_invalid_path` — manzo_open with nonexistent path returns null (D-04)
- `play_advances_position` — `#[ignore]` — requires audio hardware; documents the pattern for when hardware is available
- `spectrum_buffer_is_zero_filled` — pre-fills with NaN, asserts all 512 values are exactly 0.0 after manzo_get_spectrum (D-01 contract)
- `spectrum_null_buf_returns_zero` — null out_buf returns 0 without crash (T-02-06)

Fixture path resolved at compile time via `concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/test.mp3")`.

### Task 2: AppDelegate Phase 2 Integration

`ManzoApp/ManzoApp/AppDelegate.swift` replaces the Phase 1 nil smoke test with:
- `manzoHandle` instance variable (`UnsafeMutablePointer<manzo_ManzoHandle>?`) — keeps handle alive for app lifetime
- Bundle path lookup with dev-fixture fallback (`/Users/.../manzo-core/tests/fixtures/test.mp3`)
- `FileManager.default.fileExists` guard before FFI call
- `manzo_open(mp3Path)` → `manzo_play(handle)` → logs result
- `manzo_close(handle)` in `applicationWillTerminate` (T-02-09 mitigation)

## Decisions Made

1. **rlib added to crate-type**: `crate-type = ["staticlib", "rlib"]` — integration tests need the `rlib` artifact to resolve Rust symbol references. The `staticlib` remains for Xcode linking; `rlib` is used only by `cargo test`.

2. **mpg123_init() missing**: `manzo_open` returned null because `mpg123_new` requires `mpg123_init()` to be called first. Added `unsafe { mpg123_sys::mpg123_init() }` as first step in `manzo_open`. The function is idempotent and safe to call on every `manzo_open` invocation.

3. **Framework deps in project.yml**: cpal's CoreAudio backend requires `CoreAudio.framework`, `AudioUnit.framework`, and `AudioToolbox.framework`. These were absent from `project.yml`; Xcode didn't auto-link them. Added as `dependencies` entries.

4. **libmpg123.dylib stable path**: mpg123-sys builds to a hash-named subdirectory; Xcode linker can't use `-lmpg123` without a stable search path. Pre-build script now copies `libmpg123.dylib` to `target/aarch64-apple-darwin/release/` after cargo build.

5. **play_advances_position #[ignore]**: The test would pass on a machine with audio hardware but fails in headless CI (no default output device). Marked `#[ignore]` with documented reason. All other 4 tests pass unconditionally.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] manzo_open returned null due to missing mpg123_init()**
- **Found during:** Task 1 test execution — `open_returns_non_null_for_valid_mp3` failed
- **Issue:** `mpg123_new()` requires `mpg123_init()` to be called first; without it the mpg123 handle is always null
- **Fix:** Added `unsafe { mpg123_sys::mpg123_init() }` at the start of `manzo_open` in `lib.rs`
- **Files modified:** `manzo-core/src/lib.rs`
- **Commit:** `1e39d46`

**2. [Rule 3 - Blocking] Integration test couldn't link — crate-type staticlib only**
- **Found during:** Task 1 first compile attempt
- **Issue:** `use manzo_core::...` fails for `staticlib`-only crates (no rlib artifact); `extern "C"` declarations don't resolve via rlib either
- **Fix:** Added `"rlib"` to `crate-type` in `Cargo.toml`; integration test uses `use manzo_core::...` path
- **Files modified:** `manzo-core/Cargo.toml`
- **Commit:** `1e39d46`

**3. [Rule 3 - Blocking] Xcode linker missing CoreAudio/AudioUnit/AudioToolbox frameworks**
- **Found during:** Task 2 xcodebuild — undefined `_AudioComponentFindNext`, `_AudioUnitInitialize` etc.
- **Issue:** cpal's CoreAudio backend uses these frameworks; project.yml didn't declare them as dependencies
- **Fix:** Added `CoreAudio.framework`, `AudioUnit.framework`, `AudioToolbox.framework` as SDK dependencies in `project.yml`; regenerated xcodeproj via `xcodegen generate`
- **Files modified:** `ManzoApp/project.yml`, `ManzoApp/ManzoApp.xcodeproj/project.pbxproj`
- **Commit:** `6844dc7`

**4. [Rule 3 - Blocking] Xcode linker missing libmpg123 at stable path**
- **Found during:** Task 2 first build — `_mpg123_*` symbols undefined
- **Issue:** mpg123-sys places the dylib in a hash-named build subdir; Xcode `LIBRARY_SEARCH_PATHS` only points to the release root
- **Fix:** Pre-build script copies `libmpg123.dylib` to `target/aarch64-apple-darwin/release/` after cargo build; added `-lmpg123` to `OTHER_LDFLAGS`
- **Files modified:** `ManzoApp/project.yml`
- **Commit:** `6844dc7`

## Known Stubs

None introduced by this plan. Pre-existing stubs from 02-02 (manzo_set_eq/volume/pan, manzo_get_spectrum FFT) remain documented in `02-02-SUMMARY.md`.

## Threat Flags

None — no new network endpoints, auth paths, or schema changes. All trust boundaries pre-enumerated in plan's threat model.

## Verification Results

1. `cargo test --test integration_test` — 4 passed, 1 ignored, 0 failed
2. `grep "open_returns_non_null_for_valid_mp3" manzo-core/tests/integration_test.rs` — match found
3. `grep "spectrum_buffer_is_zero_filled" manzo-core/tests/integration_test.rs` — match found
4. `grep "manzo_open(mp3Path)" ManzoApp/ManzoApp/AppDelegate.swift` — match found
5. `grep "manzoHandle" ManzoApp/ManzoApp/AppDelegate.swift` — match found (instance var)
6. `grep "manzo_close" ManzoApp/ManzoApp/AppDelegate.swift` — match found (applicationWillTerminate)
7. `grep "manzo_play(nil)" ManzoApp/ManzoApp/AppDelegate.swift` — no match (nil call removed)
8. `xcodebuild -project ManzoApp/ManzoApp.xcodeproj -scheme ManzoApp -configuration Debug build` — BUILD SUCCEEDED

## Self-Check

### Files Exist
- `manzo-core/tests/integration_test.rs` — FOUND
- `ManzoApp/ManzoApp/AppDelegate.swift` — FOUND
- `.planning/phases/02-audio-pipeline/02-03-SUMMARY.md` — FOUND

### Commits Exist
- `1e39d46` — FOUND (test(02-03): add 5 integration tests)
- `6844dc7` — FOUND (feat(02-03): update AppDelegate)

## Self-Check: PASSED
