---
phase: 07-spectrum-analyzer
plan: "01"
subsystem: rust-fft-pipeline
tags: [rust, fft, dsp, spectrum, rustfft, double-buffer, atomic]
dependency_graph:
  requires: [04-dsp-engine]
  provides: [live-fft-magnitudes, manzo_get_spectrum]
  affects: [07-02-metal-renderer]
tech_stack:
  added: [rustfft = "6"]
  patterns: [circular-ring-buffer, double-buffer-atomic-index, try_lock-non-blocking-read]
key_files:
  modified:
    - manzo-core/Cargo.toml
    - manzo-core/src/lib.rs
decisions:
  - "FFT stride = 512 (not 1024) for smoother visuals — fires twice as often as Winamp-equivalent"
  - "Normalization divisor = 256.0 (FFT size / 4) — full-scale sine saturates at 1.0, typical music 0.3-0.8"
  - "fft_sample_pos stored as local var before indexing — borrow checker requires read-before-index pattern"
  - "FftPlanner created fresh each FFT run (not stored in InnerState) — heap-allocating, clean per Plan spec"
  - "try_lock on contention returns zero-fill (not stale) — simpler, imperceptible at 60fps (T-07-02)"
metrics:
  duration: "2m"
  completed_date: "2026-04-24"
  tasks_completed: 2
  files_modified: 2
---

# Phase 7 Plan 01: Rust FFT Pipeline Summary

**One-liner:** 1024-point rustfft pipeline in cpal callback with 512-sample stride, 75-bar double-buffer, and live manzo_get_spectrum via AtomicUsize + try_lock.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add rustfft dependency + FFT fields to InnerState | 60c9ad2 | manzo-core/Cargo.toml, manzo-core/src/lib.rs |
| 2 | FFT computation in audio callback + live manzo_get_spectrum | d72814e | manzo-core/src/lib.rs |

## What Was Built

### Task 1: rustfft + InnerState FFT fields
- Added `rustfft = "6"` to `[dependencies]` in `manzo-core/Cargo.toml`
- Added `use rustfft::{FftPlanner, num_complex::Complex}` and `use std::sync::atomic::{AtomicUsize, Ordering}` imports
- Extended `InnerState` with six new fields:
  - `fft_sample_buf: [f32; 1024]` — circular ring buffer for mono-downmixed audio samples
  - `fft_sample_pos: usize` — write head (wraps at 1023 via `& 1023`)
  - `fft_samples_since_last: usize` — counter triggering FFT every 512 samples
  - `fft_bufs: [[f32; 75]; 2]` — double-buffer holding two sets of 75 bar magnitudes
  - `fft_write_idx: usize` — which slot the callback currently writes (0 or 1)
  - `fft_read_idx: AtomicUsize` — atomically published slot index for Swift to read
- All fields initialized to zero/0 in `manzo_open` InnerState literal

### Task 2: FFT pipeline + live manzo_get_spectrum
- Inserted FFT block after `// ── End Phase 4 DSP chain` comment, before closing callback brace
- Mono downmix: `(L + R) * 0.5` per frame, written into circular ring buffer
- FFT fires every 512 new samples: copies last 1024 samples in time order from ring buffer
- 1024-point forward FFT via `FftPlanner::new().plan_fft_forward(1024)` (no windowing, D-08)
- 75 bar magnitudes: each bar averages 4 consecutive FFT bins (`bar * 4` to `bar * 4 + 3`)
- Normalization: `avg_mag / 256.0`, clamped to `[0.0, 1.0]`
- Quantized to 16 levels: `(normalized * 15.0).round() as u8 / 15.0` (D-05)
- Atomic publish: `fft_read_idx.store(write_slot, Ordering::Relaxed)` after writing
- Write slot flipped: `fft_write_idx = 1 - write_slot`
- Replaced `manzo_get_spectrum` stub: now uses `try_lock()` on the Arc<Mutex>
  - Lock acquired: copies `fft_bufs[fft_read_idx]` into caller's buffer
  - Lock busy: zero-fills (T-07-02, imperceptible at 60fps)
  - Null handle: zero-fills (safe sentinel)
  - Null out_buf: returns 0 (T-07-01)
  - Writes exactly `min(count, 75)` elements; pads remainder if count > 75
- Updated tests: `spectrum_writes_zeros` replaced by `spectrum_null_handle_writes_zeros` + `spectrum_returns_75_values`

## Verification

```
cargo test: 18/18 unit tests pass, 7/10 integration tests pass (3 ignored - require audio HW)

test tests::spectrum_null_handle_writes_zeros ... ok
test tests::spectrum_returns_75_values ... ok
test tests::spectrum_null_buf_returns_zero ... ok
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Rust borrow checker: simultaneous mutable + immutable borrow of `s`**
- **Found during:** Task 2, first `cargo test` run
- **Issue:** `s.fft_sample_buf[s.fft_sample_pos] = mono` — indexing with `s.fft_sample_pos` (immutable borrow) while also mutably indexing `s.fft_sample_buf` in the same expression
- **Fix:** Read `fft_sample_pos` into a local variable `pos` before the assignment: `let pos = s.fft_sample_pos; s.fft_sample_buf[pos] = mono; s.fft_sample_pos = (pos + 1) & 1023;`
- **Files modified:** manzo-core/src/lib.rs
- **Commit:** d72814e (included in Task 2 commit)

## Threat Surface Scan

All security mitigations from the plan's threat model were implemented:
- T-07-01: `out_buf.is_null()` guard before any write; writes exactly `min(count, 75)` elements
- T-07-02: `try_lock()` contention returns zero-fill — no spin, no blocking
- T-07-03: `Ordering::Relaxed` accepted — FFT data is non-sensitive visualization only

No new threat surface beyond the plan's `<threat_model>`.

## Known Stubs

None — `manzo_get_spectrum` is now fully live. The zero-fill stub has been replaced.

## Self-Check: PASSED

- FOUND: manzo-core/Cargo.toml
- FOUND: manzo-core/src/lib.rs
- FOUND: .planning/phases/07-spectrum-analyzer/07-01-SUMMARY.md
- FOUND commit: 60c9ad2 (Task 1 — rustfft + InnerState fields)
- FOUND commit: d72814e (Task 2 — FFT callback + live manzo_get_spectrum)
- No accidental file deletions
