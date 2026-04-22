---
phase: 02-audio-pipeline
verified: 2026-04-22T00:30:00Z
status: human_needed
score: 9/10 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Launch the ManzoApp binary on a Mac with audio hardware; observe NSLog output in Console.app"
    expected: "NSLog prints 'MANZO Phase 2: playback started — /path/to/test.mp3' and audible MP3 plays through speakers"
    why_human: "cargo test marks play_advances_position as #[ignore] because audio hardware is not reliably available in headless CI; actual end-to-end audible output requires a human listener and a machine with a CoreAudio output device"
---

# Phase 2: Audio Pipeline Verification Report

**Phase Goal:** The app decodes an MP3 file via mpg123-sys feed/read API and outputs float32 PCM to CoreAudio through cpal — no int16 conversion at any stage.
**Verified:** 2026-04-22T00:30:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | manzo_open returns a non-null handle for a valid MP3 path | VERIFIED | integration_test `open_returns_non_null_for_valid_mp3` passes; lib.rs lines 57-137 show full mpg123 init path returning `Box::into_raw(Box::new(arc))` |
| 2 | manzo_play starts a cpal CoreAudio stream on a background thread | VERIFIED | lib.rs lines 155-267 call `device.build_output_stream` + `stream.play()`, storing the stream in `InnerState`; audio callback runs on the cpal thread |
| 3 | Float32 PCM flows from mpg123 directly into the cpal callback — no int16 conversion | VERIFIED | `MPG123_FORCE_FLOAT` flag set at line 92; `mpg123_read` writes directly into `&mut [f32]` at line 210; `grep i16` returns only a comment, zero code hits |
| 4 | manzo_close frees the handle and stops the audio stream | VERIFIED | lib.rs lines 141-151: `Box::from_raw` takes ownership, drop propagates to `InnerState::drop` which calls `mpg123_delete`; `cpal::Stream` dropped via `Option` |
| 5 | manzo_get_spectrum zero-fills out_buf with count f32 zeros (D-01) | VERIFIED | lib.rs line 444: `std::ptr::write_bytes(out_buf, 0, count)`; integration test `spectrum_buffer_is_zero_filled` pre-fills NaN and asserts all 512 values == 0.0 — passes |
| 6 | manzo_get_position returns elapsed milliseconds while playing | VERIFIED | lib.rs lines 415-427: `(position_samples * 1000) / sample_rate`; null-guard returns 0; position_samples incremented in audio callback (line 221) |
| 7 | cargo test exits 0 (all unit tests pass after lib.rs rewrite) | VERIFIED | `cargo test` output: 5 unit tests pass, 0 failed; tests renamed from Phase 1 stubs to real behavior assertions |
| 8 | Rust integration test opens a real MP3, plays it, and asserts position advances | PARTIAL | `open_returns_non_null_for_valid_mp3` passes; `play_advances_position` is `#[ignore]` with documented reason — requires audio hardware |
| 9 | AppDelegate calls manzo_open with a real MP3 file path and manzo_play produces audio | VERIFIED (code) | AppDelegate.swift line 27: `manzoHandle = manzo_open(mp3Path)`; line 34: `manzo_play(handle)`; xcodebuild exits 0 (BUILD SUCCEEDED); audible output requires human |
| 10 | cargo test exits 0 including integration tests | VERIFIED | `cargo test --test integration_test` output: 4 passed, 1 ignored, 0 failed; exit code 0 |

**Score:** 9/10 truths verified (1 human-only: audible playback confirmation)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `manzo-core/Cargo.toml` | mpg123-sys and cpal runtime deps | VERIFIED | `[dependencies]` section present; `mpg123-sys = "0.1"`, `cpal = "0.15"`, `libc = "0.2"`; `crate-type = ["staticlib", "rlib"]` |
| `manzo-core/tests/fixtures/test.mp3` | Valid MPEG Layer 3 ~5s fixture | VERIFIED | `file(1)` output: "MPEG ADTS, layer III, v1, 128 kbps, 44.1 kHz, JntStereo"; size 80666 bytes (within 20-200 KB) |
| `manzo-core/src/lib.rs` | InnerState struct, Arc<Mutex<>> threading, all 11 FFI implementations | VERIFIED | `struct InnerState` at line 20; `Arc::new(Mutex::new(inner))` at line 135; all 11 `#[no_mangle] pub extern "C" fn manzo_*` functions present with real bodies |
| `manzo-core/tests/integration_test.rs` | 5 integration tests including open, spectrum zero-fill | VERIFIED | 5 tests present; 4 pass unconditionally; 1 `#[ignore]` for audio hardware dependency |
| `ManzoApp/ManzoApp/AppDelegate.swift` | Real manzo_open call with MP3 path, handle retained as instance var | VERIFIED | `manzoHandle` instance var at line 6; `manzo_open(mp3Path)` at line 27; `manzo_close` in `applicationWillTerminate` at line 45 |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `manzo-core/src/lib.rs manzo_play` | cpal CoreAudio output stream | `device.build_output_stream` | WIRED | Lines 187-257: build_output_stream called with f32 callback, stream stored in InnerState |
| cpal audio callback | mpg123 PCM output | `mpg123_read` into `&mut [f32]` | WIRED | Lines 209-216: mpg123_read writes bytes directly into `data[written..]` cast from f32; `MPG123_FORCE_FLOAT` ensures float32 output |
| `manzo_open` | `Box::into_raw as *mut ManzoHandle` | `Box<Arc<Mutex<InnerState>>>` opaque handle | WIRED | Line 136: `Box::into_raw(Box::new(arc)) as *mut ManzoHandle` |
| `manzo-core/tests/integration_test.rs` | `manzo-core/tests/fixtures/test.mp3` | `CARGO_MANIFEST_DIR` env var in concat! macro | WIRED | Line 18: `concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/test.mp3")` |
| `ManzoApp/ManzoApp/AppDelegate.swift` | manzo-core FFI via bridging header | `manzo_open(mp3Path)` + `manzo_play(handle)` | WIRED | Lines 27, 34: manzo_open and manzo_play called; xcodebuild BUILD SUCCEEDED |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `manzo_get_position` return value | `state.position_samples` | incremented in cpal audio callback (lib.rs line 221) | Conditional — requires audio stream to be running | WIRED; `play_advances_position` test verifies increment but is `#[ignore]` pending hardware |
| `manzo_get_spectrum` out_buf | zeros written by `write_bytes` | `std::ptr::write_bytes(out_buf, 0, count)` | Yes — always writes; D-01 intentional stub until Phase 7 FFT | FLOWING (constant zeros per design) |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Unit tests pass | `cargo test` (lib tests) | 5 passed, 0 failed | PASS |
| Integration tests pass | `cargo test --test integration_test` | 4 passed, 1 ignored, 0 failed; exit 0 | PASS |
| manzo_open returns non-null for valid MP3 | `open_returns_non_null_for_valid_mp3` test | PASS | PASS |
| manzo_get_spectrum zero-fills buffer | `spectrum_buffer_is_zero_filled` test | PASS | PASS |
| Xcode build succeeds with real AppDelegate | `xcodebuild … build` | BUILD SUCCEEDED | PASS |
| play_advances_position | requires audio hardware | `#[ignore]` | SKIP — human needed |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| AUDIO-01 | 02-02-PLAN.md, 02-03-PLAN.md | App plays MP3 files with CoreAudio output via cpal on Apple Silicon | SATISFIED (code) | cpal CoreAudio stream built in `manzo_play`; AppDelegate calls manzo_open + manzo_play; xcodebuild passes; audible playback needs human confirmation |
| AUDIO-04 | 02-01-PLAN.md, 02-02-PLAN.md, 02-03-PLAN.md | App decodes MP3 via mpg123-sys feed/read streaming API with float32 pipeline end-to-end | SATISFIED | `mpg123_open_feed` at line 102; `mpg123_feed` at lines 113, 229, 308; `mpg123_read` at line 210; `MPG123_FORCE_FLOAT` at line 92; no i16 in audio path; integration test verifies open succeeds |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `manzo-core/src/lib.rs` | 446 | `let _ = handle; // unused until Phase 7` in `manzo_get_spectrum` | Info | Intentional — D-01 contract; Phase 7 will wire in FFT; buffer is always written; not a hollow stub |
| `manzo-core/src/lib.rs` | 384, 396, 410 | `// Phase 4 wires into the DSP chain` comments in set_eq/volume/pan | Info | Intentional deferred implementation per plan design; values stored in InnerState; Phase 4 will apply them to audio callback |
| `manzo-core/tests/integration_test.rs` | 43 | `#[ignore = "requires audio hardware..."]` on `play_advances_position` | Warning | Hardware-dependent test cannot run in CI; audible playback confirmation requires human |

No blockers detected. The "stubs" in set_eq/volume/pan and get_spectrum are explicitly documented deferral points per plan design — they store real data and are clearly labelled for Phase 4/7 completion.

### Human Verification Required

#### 1. Audible MP3 Playback via Swift FFI

**Test:** Launch the built ManzoApp.app on a Mac with audio hardware (speakers or headphones connected). Open Console.app, filter for "MANZO". Observe output on app launch.

**Expected:** The log shows "MANZO Phase 2: playback started — /path/to/test.mp3" and a ~5-second 440 Hz sine tone is audible through the audio output. No crash, no null-handle log message.

**Why human:** The `play_advances_position` integration test is marked `#[ignore]` because it requires a default CoreAudio output device — not available in headless CI. Confirming end-to-end audible output through the Mac speaker stack (mpg123 → f32 PCM → cpal callback → CoreAudio → hardware) requires a human with audio hardware.

### Gaps Summary

No structural gaps found. All 10 must-have truths are either fully verified programmatically or require hardware-dependent human confirmation. The code implementation is complete, substantive, and wired end-to-end:

- lib.rs: 492 lines, full real implementation; all 11 FFI bodies with no placeholder returns
- Integration tests: 4/5 pass unconditionally; 1 deferred to hardware verification
- AppDelegate: manzo_open called with real path; handle retained; manzo_close wired to app exit
- Xcode build: BUILD SUCCEEDED with CoreAudio, AudioUnit, AudioToolbox frameworks linked

The only open item is human confirmation of audible audio output, which cannot be automated without audio hardware.

---

_Verified: 2026-04-22T00:30:00Z_
_Verifier: Claude (gsd-verifier)_
