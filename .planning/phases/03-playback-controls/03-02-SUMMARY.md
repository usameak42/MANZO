---
phase: 03-playback-controls
plan: "02"
subsystem: manzo-core
tags: [rust, integration-tests, test-fixture, mpg123, ffi, playback-state, duration]
dependency_graph:
  requires: [03-01]
  provides: [test2.mp3, integration_test_phase3, duration_probe_fix]
  affects: [manzo-core/tests/integration_test.rs, manzo-core/src/lib.rs, manzo-core/manzo_core.h]
tech_stack:
  added: [lame-3.100 (test fixture generation only)]
  patterns: [secondary-mpg123-handle-for-duration-probe, feed-api-vs-file-api-limitation]
key_files:
  created:
    - manzo-core/tests/fixtures/test2.mp3
    - .planning/phases/03-playback-controls/03-02-SUMMARY.md
  modified:
    - manzo-core/tests/integration_test.rs
    - manzo-core/src/lib.rs
    - manzo-core/manzo_core.h
decisions:
  - test2.mp3 generated via Python wave module + lame (ffmpeg/sox unavailable); installed via brew install lame
  - mpg123_scan() is unsupported on feed/push-API handles (always returns MPG123_ERR); use secondary file-API handle in manzo_open for duration probe
  - total_samples cached as i64 in InnerState at open time; -1 signals unknown; manzo_get_duration reads from cache instead of calling mpg123_length() on the feed handle
  - Secondary probe handle uses mpg123_open + mpg123_scan + mpg123_length then immediately closes — never stored in InnerState
requirements:
  - AUDIO-02
  - AUDIO-03
  - AUDIO-05
metrics:
  duration: ~9m
  completed: "2026-04-22T04:38:58Z"
  tasks_completed: 2
  files_modified: 4
---

# Phase 03 Plan 02: Test Fixture + Integration Tests Summary

**One-liner:** ~1-second CC0 MPEG Layer 3 fixture (test2.mp3) generated via lame; integration_test.rs extended with 4 Phase 3 tests covering STOPPED-after-open, duration > 0, state-machine transitions, and ENDED polling — plus a Rule 1 fix for mpg123_scan() being unavailable on feed-API handles.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Generate ~1s CC0 MPEG Layer 3 fixture test2.mp3 | de4b308 | manzo-core/tests/fixtures/test2.mp3 |
| 2 | Extend integration_test.rs + fix duration probe | 7f8d929 | manzo-core/tests/integration_test.rs, manzo-core/src/lib.rs, manzo-core/manzo_core.h |

## What Was Built

### Task 1: test2.mp3 Fixture

Generated a ~1-second CC0 MPEG Layer 3 fixture at `manzo-core/tests/fixtures/test2.mp3`:
- ffmpeg and sox were unavailable on this machine — installed `lame` via `brew install lame`
- Synthesized 1 second of stereo silence (44100 Hz, 2 channels) as WAV using Python `wave` module, then encoded to 128 kbps MP3 with lame
- 17135 bytes — within the 200 KB sanity bound; `file` reports "MPEG ADTS, layer III, v1, 128 kbps, 44.1 kHz, JntStereo"
- CC0 by construction — synthesized locally from Python stdlib, no third-party content

### Task 2: Integration Tests + Duration Probe Fix

**integration_test.rs edits (3 of 3 applied):**

1. **Import block updated** — added `manzo_get_duration`, `manzo_get_state`, `manzo_pause`, `manzo_stop` to the `use manzo_core::{...}` block
2. **FIXTURE_PATH_2 constant added** — `concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/test2.mp3")`
3. **Four new tests appended:**
   - `get_state_returns_stopped_after_open` — unconditional; asserts `manzo_get_state == 3` immediately after `manzo_open`
   - `get_duration_returns_nonzero_for_valid_mp3` — unconditional; asserts `manzo_get_duration > 0` for test.mp3
   - `state_transitions_play_pause_stop` — `#[ignore]`; walks full state machine PLAYING(1)→PAUSED(2)→STOPPED(3)
   - `state_becomes_ended_after_short_track_completes` — `#[ignore]`; polls for ENDED(4) within 3-second deadline using test2.mp3

All 5 pre-existing Phase 2 tests are preserved verbatim.

**lib.rs changes (Rule 1 fix):**

Added `total_samples: i64` field to `InnerState`. In `manzo_open`, after the primary feed handle is set up, a secondary `mpg123_handle` is created using `mpg123_open()` (file API) + `mpg123_scan()` + `mpg123_length()` to probe total track length. The secondary handle is immediately closed and deleted. `manzo_get_duration` now reads `state.total_samples` from the cache instead of calling `mpg123_length()` on the feed handle (which always returns 0/-1 on feed-API handles).

## Verification Results

| Check | Result |
|-------|--------|
| `file test2.mp3` contains "MPEG" | PASS |
| `ls -la test2.mp3` size 17135 < 200000 | PASS |
| `cargo test --test integration_test` exits 0 | PASS |
| 6 tests passed, 3 ignored, 0 failed | PASS |
| `get_state_returns_stopped_after_open` present | PASS (count=1) |
| `get_duration_returns_nonzero_for_valid_mp3` present | PASS (count=1) |
| `state_transitions_play_pause_stop` present | PASS (count=1) |
| `state_becomes_ended_after_short_track_completes` present | PASS (count=1) |
| FIXTURE_PATH_2 count >= 2 | PASS (count=2) |
| `#[ignore]` count == 3 | PASS (count=3) |
| All 5 pre-existing tests present | PASS (count=5) |
| Unit tests (7/7) still pass | PASS |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] mpg123_scan() unsupported on feed-API handles**

- **Found during:** Task 2 — `get_duration_returns_nonzero_for_valid_mp3` test returned 0
- **Issue:** `mpg123_scan()` always returns MPG123_ERR (-1) when called on a handle opened with `mpg123_open_feed()`. The plan's 03-PATTERNS.md assumed the feed-API handle could be scanned for CBR duration, but the mpg123 documentation (confirmed via C diagnostic) shows this is only supported with the file-based API (`mpg123_open()`).
- **Fix:** Added `total_samples: i64` to `InnerState`. In `manzo_open`, a secondary mpg123 handle is created using `mpg123_open(path)` + `mpg123_scan()` + `mpg123_length()` to probe total samples. The result is cached in `state.total_samples`. `manzo_get_duration` reads from cache rather than calling `mpg123_length()` on the feed handle. Secondary handle is immediately closed/deleted.
- **Files modified:** `manzo-core/src/lib.rs`, `manzo-core/manzo_core.h`
- **Commit:** 7f8d929

**2. [Rule 3 - Blocking] ffmpeg/sox unavailable; installed lame via brew**

- **Found during:** Task 1 — tooling probe showed no ffmpeg, sox, or lame
- **Fix:** Ran `brew install lame` (homebrew was available) to enable Path C from the plan's fallback chain
- **Impact:** No plan changes needed; lame is not a runtime dependency, only needed for fixture generation

## Known Stubs

None. All four new integration tests are either fully unconditional (and passing) or correctly `#[ignore]`'d for headless CI with documented reasons. The `state_becomes_ended_after_short_track_completes` test is stubbed for hardware but its logic is complete.

## Threat Flags

No new security surface introduced. The secondary probe handle follows the same null-guard + delete-on-close pattern as all other mpg123 usage. T-03-11 (test2.mp3 format tamper) is mitigated by the `file` command check in Task 1 acceptance criteria and `manzo_open` returning null for invalid files.

## Self-Check: PASSED

- manzo-core/tests/fixtures/test2.mp3: EXISTS (17135 bytes, MPEG Layer 3)
- manzo-core/tests/integration_test.rs: EXISTS (221 lines, 4 new tests)
- manzo-core/src/lib.rs: EXISTS (total_samples field + probe handle)
- manzo-core/manzo_core.h: EXISTS (updated doc comment)
- Commit de4b308: EXISTS (feat(03-02): generate ~1s CC0 MPEG Layer 3 test fixture test2.mp3)
- Commit 7f8d929: EXISTS (feat(03-02): extend integration tests + fix duration probe for feed-API)
- cargo test --test integration_test: 6 passed, 0 failed, 3 ignored
