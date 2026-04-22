---
phase: 03-playback-controls
plan: "01"
subsystem: manzo-core
tags: [rust, ffi, playback-state, gapless-trim, audio-pipeline]
dependency_graph:
  requires: [02-audio-pipeline]
  provides: [manzo_get_state, manzo_get_duration, playback_state_tracking, 529_sample_trim]
  affects: [ManzoApp/AppDelegate.swift, manzo-core/tests/integration_test.rs]
tech_stack:
  added: []
  patterns: [null-guard-plus-lock, saturating_sub-underflow-prevention, poison-recovery-mutex]
key_files:
  created: []
  modified:
    - manzo-core/src/lib.rs
    - manzo-core/manzo_core.h
decisions:
  - playback_state stored as i32 in InnerState (not enum) to keep FFI ABI simple; values 1/2/3/4 match D-02 constants
  - startup_skip_remaining uses saturating_sub to prevent u64 underflow (T-03-07)
  - mpg123_length negative return cast prevented by explicit < 0 check before as u64 cast (T-03-03)
  - startup_skip_remaining EOF guard breaks out of while loop (not infinite-loops) when file_offset >= file_data.len() during skip phase (T-03-05)
metrics:
  duration: ~8m
  completed: "2026-04-22T04:29:47Z"
  tasks_completed: 2
  files_modified: 2
---

# Phase 03 Plan 01: Playback State Tracking + 529-Sample Trim Summary

**One-liner:** InnerState extended with playback_state (PLAYING/PAUSED/STOPPED/ENDED i32) and 529-sample mpg123 decoder-delay trim, plus manzo_get_state and manzo_get_duration FFI getters with full STRIDE mitigation.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Extend InnerState with playback_state + startup_skip_remaining; wire state transitions in play/pause/stop/EOF | ec2b107 | manzo-core/src/lib.rs |
| 2 | Add manzo_get_state and manzo_get_duration FFI getters + unit tests | 01f9e97 | manzo-core/src/lib.rs, manzo-core/manzo_core.h |

## What Was Built

### Task 1: InnerState Extension + State Transitions

`InnerState` gained two new fields appended after `eq_preamp`:
- `playback_state: i32` — initialized to 3 (STOPPED) in `manzo_open`; set to 1/2/3/4 by play/pause/stop/EOF
- `startup_skip_remaining: u64` — initialized to 529 in `manzo_open`; decremented in audio callback

State transitions wired:
- `manzo_play`: sets `playback_state = 1` (PLAYING) after `is_playing = true`
- `manzo_pause`: sets `playback_state = 2` (PAUSED) after `is_playing = false`
- `manzo_stop`: sets `playback_state = 3` (STOPPED) between `is_playing = false` and `position_samples = 0`
- Audio callback EOF branch: sets `playback_state = 4` (ENDED) before break

529-sample trim block inserted at top of audio callback decode loop:
- Decodes into scratch Vec<f32> when `startup_skip_remaining > 0`
- Uses `saturating_sub` on decrement to prevent underflow
- Handles `MPG123_NEED_MORE` by feeding next chunk
- Breaks (does not infinite-loop) when EOF reached during skip phase
- Does not increment `written` — discarded samples never reach PCM output

`manzo_seek` is unchanged per D-04 (trim fires only on `manzo_open`).

### Task 2: FFI Getters + Unit Tests

`manzo_get_state(handle) -> i32`:
- Null guard returns 3 (STOPPED sentinel) — T-03-01
- Locks `Arc<Mutex<InnerState>>` with poison recovery
- Returns `state.playback_state` directly

`manzo_get_duration(handle) -> u64`:
- Null guard returns 0 — T-03-02
- Returns 0 when `sample_rate == 0` — T-03-04 (division by zero prevention)
- Calls `mpg123_sys::mpg123_length()` and returns 0 for negative results — T-03-03
- Returns `(total_samples as u64 * 1000) / sample_rate as u64`

Two new unit tests added to `#[cfg(test)] mod tests`:
- `get_state_null_returns_stopped` — asserts null handle → 3 (STOPPED)
- `get_duration_null_returns_zero` — asserts null handle → 0

cbindgen regenerated `manzo_core.h` with both new function declarations.

## Verification Results

| Check | Result |
|-------|--------|
| `cargo test` — 7 unit tests | PASS (7/7) |
| `cargo test` — 4 integration tests (1 ignored) | PASS (4/4) |
| `cargo build --target aarch64-apple-darwin` | PASS |
| playback_state field + 4 setters + getter | PASS (7 occurrences) |
| startup_skip_remaining field + init + trim block | PASS (7 occurrences) |
| manzo_seek body does NOT touch startup_skip_remaining | PASS (0 occurrences) |
| manzo_get_state in manzo_core.h | PASS |
| manzo_get_duration in manzo_core.h | PASS |
| WR-03 comment preserved | PASS |
| All 11 Phase 2 FFI signatures present | PASS (11) |

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None. `manzo_get_duration` returns 0 for CBR files without LAME header, but this is explicitly documented as intentional (D-03: CBR scanning deferred to Phase 8), not a stub.

## Threat Flags

No new security surface beyond what the plan's threat model covers. All 8 STRIDE threats (T-03-01 through T-03-08) are mitigated in the implementation:

| Threat | Mitigation | Status |
|--------|-----------|--------|
| T-03-01 Null dereference in manzo_get_state | `if handle.is_null() { return 3; }` first line | Applied |
| T-03-02 Null dereference in manzo_get_duration | `if handle.is_null() { return 0; }` first line | Applied |
| T-03-03 Arithmetic panic on negative samples | `if total_samples < 0 { return 0; }` before `as u64` cast | Applied |
| T-03-04 Division by zero in manzo_get_duration | `if state.sample_rate == 0 { return 0; }` guard | Applied |
| T-03-05 Infinite loop in startup-skip block | `break` when EOF during skip, `MPG123_NEED_MORE` with 0 discarded feeds then retries | Applied |
| T-03-06 Mutex poisoning on state read | `unwrap_or_else(|e| e.into_inner())` on all 10 lock calls | Applied |
| T-03-07 startup_skip_remaining underflow | `saturating_sub(discarded_samples as u64)` | Applied |
| T-03-08 Stale-read race vs Swift poller | Accepted — same Arc<Mutex> as audio callback; ~100ms stale is acceptable per D-05 | Accepted |

## Self-Check: PASSED

- manzo-core/src/lib.rs: EXISTS
- manzo-core/manzo_core.h: EXISTS
- Commit ec2b107: EXISTS (feat(03-01): extend InnerState...)
- Commit 01f9e97: EXISTS (feat(03-01): add manzo_get_state...)
