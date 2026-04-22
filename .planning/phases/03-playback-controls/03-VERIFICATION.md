---
phase: 03-playback-controls
verified: 2026-04-22T08:00:00Z
status: human_needed
score: 11/13 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Run the ManzoApp Debug build, open two consecutive MP3 files, and let the first finish playing"
    expected: "No audible pop or silence gap at the track boundary; the app smoothly advances to track 2"
    why_human: "The 529-sample trim and auto-advance mechanism are wired and code-verified, but the absence of a pop or silence gap is an auditory judgment that cannot be made by grep or test output"
  - test: "While a track is playing, seek to mid-track (e.g. 50%) via manzo_seek and verify playback resumes from the new position without an audible glitch"
    expected: "Playback resumes from the seeked position; no decoder pop; no startup trim fires on seek (startup_skip_remaining unchanged)"
    why_human: "manzo_seek body is correct and D-04 policy is confirmed in code, but audible quality of the seek (no pop, correct position) requires a human listener with audio hardware"
  - test: "Run state_transitions_play_pause_stop and state_becomes_ended_after_short_track_completes with audio hardware (cargo test -- --ignored)"
    expected: "Both ignored tests pass: state walks PLAYING→PAUSED→STOPPED correctly; ENDED (4) is reported within 3 seconds for test2.mp3"
    why_human: "Both tests are marked #[ignore] because they require audio output hardware not available in headless CI; they must be run manually"
---

# Phase 3: Playback Controls Verification Report

**Phase Goal:** Implement playback controls — transport state machine (PLAYING/PAUSED/STOPPED/ENDED), 529-sample mpg123 decoder startup trim, and Swift auto-advance via FFI state polling.
**Verified:** 2026-04-22T08:00:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | InnerState carries `playback_state: i32` and `startup_skip_remaining: u64` | VERIFIED | lib.rs lines 36–40: both fields present in struct after eq_preamp |
| 2 | `manzo_open` initializes `playback_state = 3` (STOPPED) and `startup_skip_remaining = 529` | VERIFIED | lib.rs lines 178–179: `playback_state: 3` and `startup_skip_remaining: 529` in InnerState literal |
| 3 | `manzo_play` sets `playback_state = 1` (PLAYING) and returns 0 on success | VERIFIED | lib.rs line 369: `state.playback_state = 1;` present; existing null-return-minus-one test passes |
| 4 | `manzo_pause` sets `playback_state = 2` (PAUSED) and keeps stream alive | VERIFIED | lib.rs line 385: `state.playback_state = 2;`; stream not dropped in pause path |
| 5 | `manzo_stop` sets `playback_state = 3` (STOPPED) and resets the decoder | VERIFIED | lib.rs line 399: `state.playback_state = 3;` between is_playing=false and position_samples=0 |
| 6 | Audio callback discards the first 529 decoded samples after `manzo_open` before writing PCM | VERIFIED | lib.rs lines 266–303: startup_skip trim block present; does not increment `written`; uses `continue` |
| 7 | Audio callback sets `playback_state = 4` (ENDED) at natural EOF | VERIFIED | lib.rs line 342: `s.playback_state = 4;` in EOF branch before break |
| 8 | `manzo_get_state(handle)` returns the current `playback_state` field; null handle returns 3 | VERIFIED | lib.rs lines 556–564: null guard returns 3; state.playback_state returned; unit test passes (7/7) |
| 9 | `manzo_get_duration(handle)` returns duration in ms; returns 0 on unknown or null | VERIFIED | lib.rs lines 572–587: reads from cached `total_samples` (secondary probe handle); null guard + sample_rate==0 guard + negative guard all present; integration test `get_duration_returns_nonzero_for_valid_mp3` passes |
| 10 | `manzo_seek` does NOT reset `startup_skip_remaining` (D-04) | VERIFIED | `awk '/fn manzo_seek/,/^}/' lib.rs | grep startup_skip_remaining` returns 0 matches |
| 11 | `cargo test` exits 0 (all unit and non-ignored integration tests pass) | VERIFIED | 7 unit tests pass, 6 integration tests pass (3 ignored for audio HW), 0 failures |
| 12 | No audible pop or silence gap at track boundary (529-sample trim in effect, gapless playback) | NEEDS HUMAN | Trim logic is fully wired; auditory verification requires audio hardware |
| 13 | Seek produces correct position without audible glitch; startup_skip_remaining not reset on seek | NEEDS HUMAN | D-04 policy confirmed in code; audible quality requires human testing with audio hardware |

**Score:** 11/13 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `manzo-core/src/lib.rs` | InnerState extended with `playback_state: i32`, `startup_skip_remaining: u64` | VERIFIED | Both fields present at lines 36–40; all 4 state setters + trim block wired |
| `manzo-core/src/lib.rs` | `manzo_get_state` FFI function | VERIFIED | Line 556: `pub extern "C" fn manzo_get_state` with null guard, lock, return state.playback_state |
| `manzo-core/src/lib.rs` | `manzo_get_duration` FFI function | VERIFIED | Line 572: reads `total_samples` cache (deviation from plan: secondary probe handle added in Plan 02 to fix mpg123_scan limitation on feed-API handles) |
| `manzo-core/src/lib.rs` | 529-sample startup skip in audio callback | VERIFIED | Lines 266–303: trim block present with saturating_sub, MPG123_NEED_MORE handling, EOF break |
| `manzo-core/manzo_core.h` | C header includes `manzo_get_state` and `manzo_get_duration` | VERIFIED | Lines 79 and 88 of header: both declarations present; 13 functions total in header |
| `manzo-core/tests/fixtures/test2.mp3` | ~1-second CC0 MPEG Layer 3 fixture | VERIFIED | 17135 bytes, `file` reports "MPEG ADTS, layer III, v1, 128 kbps, 44.1 kHz, JntStereo" |
| `manzo-core/tests/integration_test.rs` | Phase 3 integration tests for state transitions, duration, ENDED detection | VERIFIED | 4 new tests present; 2 unconditional pass; 2 `#[ignore]`'d for audio HW |
| `ManzoApp/ManzoApp/AppDelegate.swift` | Auto-advance smoke test: 2-track queue with `manzo_get_state` polling | VERIFIED | 131 lines; all required instance vars, timer, pollPlaybackState, lifecycle handlers present |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `manzo_open` | `InnerState{playback_state: 3, startup_skip_remaining: 529}` | Field initializers in struct literal | WIRED | lib.rs lines 178–179 |
| Audio callback decode loop | `s.playback_state = 4` at natural EOF | `frames_written == 0` branch in NEED_MORE path | WIRED | lib.rs line 342; EOF sets is_playing=false + playback_state=4 before break |
| Audio callback decode loop | Discarded mpg123_read samples | Scratch Vec<f32> decode when `startup_skip_remaining > 0` | WIRED | lib.rs lines 266–303; samples decoded into scratch, not added to `written` |
| `manzo_get_state` / `manzo_get_duration` | `Arc<Mutex<InnerState>>` | Null-guard + lock + read-field getter pattern | WIRED | lib.rs lines 556–564 and 572–587; identical null-guard + unwrap_or_else pattern as manzo_get_position |
| `AppDelegate.applicationDidFinishLaunching` | 100ms repeating Timer targeting `#selector(pollPlaybackState)` | `pollTimer = Timer.scheduledTimer(timeInterval: 0.1, ...)` | WIRED | AppDelegate.swift lines 60–66 |
| `AppDelegate.pollPlaybackState` | `manzo_open + manzo_play` of next track | `if state == MANZO_STATE_ENDED { ... }` guard | WIRED | AppDelegate.swift lines 94–129: ENDED detected, close-then-open-then-play pattern |
| `AppDelegate.applicationWillTerminate` | `pollTimer?.invalidate() + manzo_close(handle)` | Lifecycle cleanup in correct order (timer before handle) | WIRED | AppDelegate.swift lines 71–79 |
| `integration_test.rs` | `manzo_get_state / manzo_get_duration / manzo_pause / manzo_stop` FFI symbols | `use manzo_core::{...}` import block | WIRED | integration_test.rs lines 10–14: all 4 new symbols imported |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|--------------------|--------|
| `manzo_get_state` | `state.playback_state` | Set by manzo_play/pause/stop and audio callback EOF branch | Yes — 4 code paths write to field; getter reads under same mutex | FLOWING |
| `manzo_get_duration` | `state.total_samples` | Secondary mpg123 file-API probe handle in manzo_open: `mpg123_open + mpg123_scan + mpg123_length` | Yes — secondary handle scans file and caches result; integration test confirms > 0 returned for test.mp3 | FLOWING |
| `AppDelegate.pollPlaybackState` | `state` from `manzo_get_state(handle)` | FFI call to Rust core under Arc<Mutex> | Yes — real FFI call; returns live playback_state field | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| cargo test — 7 unit tests pass | `cargo test 2>&1 \| tail -5` | `test result: ok. 7 passed; 0 failed` | PASS |
| cargo test — integration tests pass | `cargo test --test integration_test` | `test result: ok. 6 passed; 0 failed; 3 ignored` | PASS |
| `manzo_get_state` null returns 3 | unit test `get_state_null_returns_stopped` | Passes | PASS |
| `manzo_get_duration` null returns 0 | unit test `get_duration_null_returns_zero` | Passes | PASS |
| `get_state_returns_stopped_after_open` integration test | Unconditional, no audio HW needed | Passes | PASS |
| `get_duration_returns_nonzero_for_valid_mp3` integration test | Unconditional, no audio HW needed | Passes | PASS |
| `startup_skip_remaining` not in `manzo_seek` body | `awk '/fn manzo_seek/,/^}/' lib.rs \| grep -c startup_skip_remaining` | 0 | PASS |
| state_transitions_play_pause_stop (audio HW required) | `cargo test -- --ignored` (manual) | Cannot run in headless env | NEEDS HUMAN |
| state_becomes_ended_after_short_track_completes (audio HW required) | `cargo test -- --ignored` (manual) | Cannot run in headless env | NEEDS HUMAN |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|------------|------------|-------------|--------|----------|
| AUDIO-02 | 03-01, 03-02 | Gapless playback by trimming the 529-sample mpg123 decoder delay in Rust | SATISFIED (code) / NEEDS HUMAN (audible verification) | startup_skip_remaining initialized to 529; trim block discards samples; `manzo_seek` does not reset counter per D-04 |
| AUDIO-03 | 03-01, 03-02 | User can play, pause, stop, and seek within a track | SATISFIED (code) / NEEDS HUMAN (audible seek quality) | manzo_play/pause/stop set playback_state 1/2/3; manzo_seek unchanged from Phase 2; state integration tests verify state machine |
| AUDIO-05 | 03-01, 03-02, 03-03 | App auto-advances to the next track when a track ends | SATISFIED (code) / NEEDS HUMAN (audible end-to-end) | manzo_get_state returns ENDED=4 at EOF; Swift pollPlaybackState detects ENDED and opens/plays next track; 100ms timer armed |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `manzo-core/src/lib.rs` | 504, 517, 530 | `// Phase 4 wires these into the DSP chain` on volume/pan/EQ setters | Info | Intentional deferral to Phase 4 per roadmap; fields stored but DSP not applied — this is Phase 4's responsibility, not Phase 3 |
| `manzo-core/src/lib.rs` | 606 | `let _ = handle;` in `manzo_get_spectrum` | Info | Intentional Phase 7 deferral; spectrum data stubbed per plan — not Phase 3 scope |

No blockers or warnings found in Phase 3 scope. Volume/pan/EQ and spectrum stubs are pre-existing deferrals to Phases 4 and 7 respectively.

### Human Verification Required

#### 1. Gapless Track Boundary — No Audible Pop or Silence

**Test:** Build and run ManzoApp in Debug. Let it play test.mp3 (first track) to natural completion and auto-advance to test2.mp3 (second track). Listen closely at the boundary.
**Expected:** No audible pop at the start of playback (529-sample trim working), and no noticeable silence gap at the track boundary (auto-advance handoff fast enough to be imperceptible).
**Why human:** The 529-sample trim and close-before-open pattern are code-verified. Whether they produce a perceptibly clean boundary is an auditory judgment that cannot be automated.

#### 2. Seek Without Audible Glitch

**Test:** While a track is playing, call `manzo_seek` to mid-track (e.g., 50%). Listen for pops, position errors, or stuck/restarted audio.
**Expected:** Playback resumes from the seeked position. No audible decoder pop. Startup trim does not fire again on seek (startup_skip_remaining is not reset).
**Why human:** The seek mechanism and D-04 policy are code-correct. Actual audible quality at the seek point requires a human listener. Note: this tests Phase 2 seek behavior — the Phase 3 contribution is confirming D-04 (no trim reset on seek) does not introduce artifacts.

#### 3. Ignored Integration Tests — With Audio Hardware

**Test:** Run `cd /Users/usameak42/Coding/MANZO/manzo-core && cargo test -- --ignored` on a machine with audio output hardware.
**Expected:** All 3 ignored tests pass: `play_advances_position`, `state_transitions_play_pause_stop`, `state_becomes_ended_after_short_track_completes`.
**Why human:** These tests require a functional audio output device. The test logic is fully implemented and correct — they are ignored only due to headless CI constraints, not because they are stubs.

### Notable Deviation (Plan 02 Auto-fix)

Plan 03-02 documented an auto-fixed deviation: `mpg123_scan()` does not work on feed/push-API handles (always returns MPG123_ERR). The plan's original design assumed `manzo_get_duration` would call `mpg123_length()` directly on the primary feed handle; this returns 0/-1 for all files opened via the feed API.

**Fix applied:** A secondary mpg123 file-API handle is opened during `manzo_open`, used to call `mpg123_scan()` + `mpg123_length()`, and immediately closed. The result is cached in a new `total_samples: i64` field on `InnerState`. `manzo_get_duration` reads from this cache. This is a correct and complete fix — the integration test `get_duration_returns_nonzero_for_valid_mp3` confirms it works. The deviation adds one struct field and expands `manzo_open`; it does not change any FFI signatures or the ABI.

### Gaps Summary

No automated gaps. All must-haves are either verified or deferred to human testing for auditory judgment. The implementation is complete and substantive:

- Rust state machine: fully wired (all 4 state setters, trim block, getters)
- C header: regenerated with both new FFI declarations
- Test fixture: valid MPEG Layer 3 file confirmed
- Integration tests: unconditional tests pass; hardware-dependent tests correctly deferred via `#[ignore]`
- Swift AppDelegate: complete auto-advance implementation with timer, queue, and lifecycle cleanup

The 2 human verification items (gapless auditory quality, seek auditory quality) and 1 hardware-gated item (ignored integration tests) are the only outstanding items. These are inherent to audio software — they cannot be verified by static analysis.

---

_Verified: 2026-04-22T08:00:00Z_
_Verifier: Claude (gsd-verifier)_
