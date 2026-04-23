---
phase: 04-dsp-engine
plan: "02"
subsystem: dsp
tags: [rust, biquad-iir, eq10, dsp, audio, cpal-callback, vol-pan-ramp, ffi]

requires:
  - phase: 04-dsp-engine
    plan: "01"
    provides: Eq10State, eq10_processf, eq10_db2gain (pub(crate) from eq10.rs)

provides:
  - wired-dsp-chain: 5-stage DSP chain active in cpal audio callback
  - preamp-pre-conversion: preamp dB→linear computed on caller thread (manzo_set_eq)
  - vol-pan-ramp: linear 441-frame ramp for volume and pan changes
  - eq-ffi: manzo_set_eq, manzo_set_volume, manzo_set_pan fully wired

affects:
  - manzo-core/src/lib.rs

tech-stack:
  added: []
  patterns:
    - borrow-split: copy bool (config_eq_limiter) before mutable field borrow to satisfy Rust borrow checker
    - collect-then-mutate: collect clamped values into stack array before mutating multiple struct fields
    - ramp-interpolation: linear frame-by-frame ramp for click-free volume/pan transitions

key-files:
  modified:
    - path: manzo-core/src/lib.rs
      description: Extended InnerState with 9 DSP fields; wired 5-stage DSP chain into cpal callback; replaced 3 FFI stubs with real logic

decisions:
  - "Removed dead volume/pan fields (Phase 3 legacy) — fully superseded by current_volume/current_pan ramp fields; removal eliminates dead_code warning"
  - "Copied config_eq_limiter (bool: Copy) to local before eq10_processf mutable borrows — borrow checker requires separating immutable reads from mutable field borrows"
  - "Used std::array::from_fn to collect clamped dB values before the loop that mutates eq_gains and eq_l/eq_r.band[i].gain — avoids holding iter_mut borrow across struct field access"

metrics:
  duration_minutes: 4
  tasks_completed: 2
  tasks_total: 2
  files_modified: 1
  completed_date: "2026-04-23"
---

# Phase 4 Plan 02: DSP Chain Wiring Summary

**One-liner:** 5-stage DSP chain (preamp → EQ L/R biquad cascade → vol/pan linear ramp) wired into cpal audio callback with pre-computed coefficients and click-free 441-frame ramps.

## Tasks Completed

| # | Name | Commit | Files |
|---|------|--------|-------|
| 1 | Add mod declaration + extend InnerState + update manzo_open initializer | 7e45994 | manzo-core/src/lib.rs |
| 2 | Replace stub bodies + wire DSP chain into cpal callback | 392c20d | manzo-core/src/lib.rs |

## What Was Built

**Task 1** added the `use eq10::{Eq10State, eq10_processf, eq10_db2gain}` import and extended `InnerState` with 9 new DSP fields: `preamp_gain_linear`, `eq_l`, `eq_r`, `config_eq_limiter`, `target_volume`, `current_volume`, `vol_ramp_remaining`, `target_pan`, `current_pan`, `pan_ramp_remaining`. All fields initialized in `manzo_open` with safe defaults (unity gain, limiter enabled, ramp counters at zero).

**Task 2** replaced the three Phase 3 no-op stubs:
- `manzo_set_eq`: now pre-computes shifted-linear gain via `eq10_db2gain` into both `eq_l.band[i].gain` and `eq_r.band[i].gain`, and pre-converts preamp dB to linear scalar (avoids `powf` in the audio callback hot path)
- `manzo_set_volume`: writes `target_volume` and resets `vol_ramp_remaining = 441`
- `manzo_set_pan`: writes `target_pan` and resets `pan_ramp_remaining = 441`

The cpal callback now runs the full 5-stage DSP chain after the decode while-loop completes:
1. Preamp scalar multiply (skipped when == 1.0)
2. `eq10_processf` on left channel (idx=0, step=2)
3. `eq10_processf` on right channel (idx=1, step=2)
4. Per-frame volume/pan linear ramp (441 frames ≈ 10 ms at 44.1 kHz)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Borrow checker: config_eq_limiter read during mutable borrow of eq_l/eq_r**
- **Found during:** Task 2, first build attempt
- **Issue:** `eq10_processf(&mut s.eq_l, data, num_frames, 0, 2, s.config_eq_limiter)` — passing `s.config_eq_limiter` as immutable while `&mut s.eq_l` holds a mutable borrow of `s` caused E0502
- **Fix:** Copy `config_eq_limiter` (bool: Copy) to a local `let limiter = s.config_eq_limiter;` before the `eq10_processf` calls
- **Files modified:** manzo-core/src/lib.rs
- **Commit:** 392c20d

**2. [Rule 1 - Bug] Borrow checker: iter_mut on eq_gains held while accessing eq_l/eq_r**
- **Found during:** Task 2, first build attempt
- **Issue:** `state.eq_gains.iter_mut().zip(...)` held a mutable borrow of `state` across `state.eq_l.band[i].gain` and `state.eq_r.band[i].gain` assignments, causing E0499
- **Fix:** Collect clamped dB values into a `[f32; 10]` stack array via `std::array::from_fn` first, then iterate the owned array to update all three targets
- **Files modified:** manzo-core/src/lib.rs
- **Commit:** 392c20d

**3. [Rule 1 - Bug] Dead code warning: volume and pan fields never read**
- **Found during:** Task 2 final build check
- **Issue:** Phase 3 legacy `volume: f32` and `pan: f32` fields on `InnerState` were superseded by the ramp fields (`current_volume`, `current_pan`). `manzo_set_volume` and `manzo_set_pan` stubs no longer wrote to them; `cargo build` emitted `dead_code` warning, violating the zero-warnings requirement
- **Fix:** Removed `volume` and `pan` from struct definition and `manzo_open` initializer
- **Files modified:** manzo-core/src/lib.rs
- **Commit:** 392c20d

## Verification

```
cargo test --manifest-path manzo-core/Cargo.toml --lib
# 17 passed; 0 failed

cargo build --manifest-path manzo-core/Cargo.toml
# Finished with 0 warnings

grep "eq10_processf" manzo-core/src/lib.rs
# 3 lines: 1 use import + 2 call sites (L and R)

grep "vol_ramp_remaining" manzo-core/src/lib.rs
# 5 lines: declaration, initializer, check, use, reset

grep "preamp_gain_linear" manzo-core/src/lib.rs
# 4 lines: declaration, initializer, callback read, set_eq assignment

grep "Phase 4 wires" manzo-core/src/lib.rs
# (no output — placeholder comments removed)
```

## Known Stubs

None. All DSP fields are wired. The `manzo_get_spectrum` function remains a zero-fill stub (Phase 7), but that is outside the scope of this plan.

## Threat Surface Scan

No new network endpoints, auth paths, or schema changes introduced. All changes are within the existing `Arc<Mutex<InnerState>>` trust boundary. Threat mitigations T-04-06 through T-04-10 are fully implemented:
- T-04-06: `gains` null guard preserved; `from_raw_parts(gains, 10)` with caller-guaranteed length
- T-04-07: NaN/Inf clamped via `.clamp()` with finite bounds in all three FFI functions
- T-04-08: Mutex held for full DSP chain (accepted per WR-03; Phase 5 will restructure)
- T-04-09: `powf` on caller thread only (manzo_set_eq), not in callback hot path
- T-04-10: Division-by-zero impossible — `vol_ramp_remaining > 0` guard before division

## Self-Check: PASSED

- [x] manzo-core/src/lib.rs modified and committed
- [x] Commit 7e45994 exists (Task 1)
- [x] Commit 392c20d exists (Task 2)
- [x] 17 unit tests pass
- [x] Zero build warnings
- [x] `mod eq10` present at line 5
- [x] `eq10_processf` called twice (L and R)
- [x] `preamp_gain_linear` pre-computed in manzo_set_eq
- [x] `state.target_volume = volume.clamp` present
- [x] `state.target_pan = pan.clamp` present
- [x] Old `state.volume = volume` and `state.pan = pan` stubs removed
