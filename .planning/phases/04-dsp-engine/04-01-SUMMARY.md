---
phase: 04-dsp-engine
plan: "01"
subsystem: dsp
tags: [rust, biquad-iir, eq10, dsp, audio, winamp-port, f64]

requires:
  - phase: 03-playback-controls
    provides: float32 audio pipeline, manzo-core crate structure, InnerState pattern

provides:
  - "Eq10Band struct: 12 f64 fields (gain, boost/cut biquad coefficients ua0/ub1/ub2/da0/db1/db2, delay lines x1/x2/y1/y2)"
  - "Eq10State::new(rate): initializes all 10 bands at Winamp frequencies + detectdecay = pow(0.001, 1/(rate*0.700))"
  - "eq10_processf: in-place 10-band biquad cascade + dynamic limiter (EQ10_TRIM_CODE=0.930, DENORMAL_FIX=1e-30)"
  - "eq10_bsetup / eq10_bsetup2: dual-Q coefficient computation (cut Q*0.5, boost Q*2.0)"
  - "eq10_db2gain: shifted-linear gain conversion pow(10, dB/20)-1"
  - "10 unit tests all passing"

affects: [04-02-dsp-callback-wiring, 04-03-ffi-eq-surface, integration-test]

tech-stack:
  added: []
  patterns:
    - "eq10.rs as standalone pub(crate) DSP module — independently testable, not in cbindgen surface"
    - "Dual-coefficient biquad: separate ua0/ub1/ub2 (boost Q*2) and da0/db1/db2 (cut Q*0.5) per band"
    - "Gain sign selects coefficient set: gain > 0.0 uses boost, gain <= 0.0 uses cut (verbatim from C source)"
    - "a0 == 0.0 skip: flat bands (gain=0.0) skipped entirely — both correctness and perf optimization"
    - "DENORMAL_FIX: +1e-30_f64 in biquad loop (y0) and limiter loop (detect) — matches original, portable"
    - "#[allow(dead_code)] at module level suppresses warnings until Plan 02 wires module into lib.rs"

key-files:
  created:
    - manzo-core/src/eq10.rs
  modified:
    - manzo-core/src/lib.rs

key-decisions:
  - "Test bound for detectdecay corrected: plan specified d > 0.9998 but actual pow(0.001, 1/(44100*0.700)) = 0.99977; bound widened to d > 0.9997 (Rule 1 auto-fix)"
  - "Nyquist guard in eq10_bsetup2 zeros BOTH ua0 and da0 (matching C source line 44: band->ua0=band->da0=0), not just the active set"
  - "#[allow(dead_code)] module-level annotation used to achieve zero build warnings while items await Plan 02 wiring"
  - "pub(crate) mod eq10 declared in lib.rs; pub(crate) visibility on all exported items"

patterns-established:
  - "Verbatim port discipline: every line of eq10_processf traceable to eq10dsp.cpp line numbers"
  - "In-place processing (buf == outbuf): cascade between bands is automatic, no pointer reset needed"
  - "Local variable hoisting for delay lines (x1/x2/y1/y2) before inner sample loop for register allocation"

requirements-completed: [DSP-01, DSP-02]

duration: 3min
completed: 2026-04-23
---

# Phase 4 Plan 01: DSP Engine — EQ10 Port Summary

**Verbatim Rust port of Winamp eq10dsp.cpp: dual-biquad IIR Eq10Band/Eq10State structs, eq10_processf hot path with dynamic limiter, and eq10_db2gain — all 10 unit tests passing, zero build warnings**

## Performance

- **Duration:** 3 min
- **Started:** 2026-04-23T18:59:36Z
- **Completed:** 2026-04-23T19:02:51Z
- **Tasks:** 1 (single TDD task)
- **Files modified:** 2

## Accomplishments

- Created `manzo-core/src/eq10.rs` — complete Rust port of eq10dsp.cpp/eq10dsp.h with all structs and functions
- All 10 unit tests pass: db2gain (0 dB, +12 dB, -12 dB), detectdecay (non-zero, slow-decay), band coefficient sanity (boost+cut non-zero), flat-eq noop, boost-modifies-buffer, no-panic 1024 frames
- Zero build warnings; zero new crate dependencies; `cargo build` clean

## Task Commits

1. **Task 1: Create eq10.rs — complete Winamp EQ10 port** - `7125636` (feat)

**Plan metadata:** (pending final commit)

## Files Created/Modified

- `manzo-core/src/eq10.rs` — New file: Eq10Band, Eq10State, eq10_bsetup2, eq10_bsetup, eq10_processf, eq10_db2gain, eq10_setgain, 10 unit tests
- `manzo-core/src/lib.rs` — Added `pub(crate) mod eq10;` declaration at top of file

## Decisions Made

- Test bound for `new_detectdecay_is_slow_decay` corrected from `d > 0.9998` (plan spec) to `d > 0.9997` because `pow(0.001, 1/(44100*0.700)) = 0.99977625` — the implementation is correct; the plan's bound was miscalculated
- `#[allow(dead_code)]` applied at module level (`#![allow(dead_code)]` inside eq10.rs) to suppress dead_code warnings until Plan 02 wires the module into the audio callback; removes itself naturally when used
- Nyquist guard correctly zeros both `ua0` and `da0` on Nyquist boundary (matching C source `band->ua0=band->da0=0`), regardless of which coefficient set is being computed

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Test bound for detectdecay miscalculated in plan spec**
- **Found during:** Task 1 (test execution)
- **Issue:** Plan specified `d > 0.9998 && d < 1.0` for detectdecay at 44.1 kHz with 0.700s release. The actual mathematical value `pow(0.001, 1/(44100*0.700)) = 0.99977625` is below 0.9998, causing the test to fail despite the implementation being correct.
- **Fix:** Widened lower bound to `d > 0.9997` — still enforces non-zero, slow-decay behavior; matches the verified mathematical result
- **Files modified:** manzo-core/src/eq10.rs
- **Verification:** Test `new_detectdecay_is_slow_decay` passes with computed value 0.99977625
- **Committed in:** 7125636 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — test bound bug)
**Impact on plan:** The implementation is mathematically correct; only the test assertion bound was wrong. No scope creep.

## Issues Encountered

- Dead_code warnings from `pub(crate)` items unused by `lib.rs` (Plan 02 wires them in). Resolved with module-level `#![allow(dead_code)]` — clean, reversible, standard Rust practice for staged feature development.

## Known Stubs

None — all functions are fully implemented with real DSP math. No placeholder logic.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or trust boundary changes introduced. All STRIDE mitigations from the threat model are implemented:

- T-04-01: `gain > 0.0` (strict) correctly routes boost vs. cut — present at eq10.rs line ~175
- T-04-02: `new_detectdecay_is_slow_decay` test enforces detectdecay > 0.9997 — present
- T-04-03: `+ 1e-30_f64` in both biquad loop (y0) and limiter loop (detect) — present
- T-04-05: `processf_no_panic_1024_frames` test verifies no index overflow — present

## Next Phase Readiness

- `eq10.rs` is complete and independently tested — ready for Plan 02 wiring into the audio callback
- Plan 02 adds `eq_l: Eq10State`, `eq_r: Eq10State`, `config_eq_limiter: bool`, preamp/vol/pan fields to `InnerState` and inserts the DSP chain into the cpal callback
- No blockers; `#![allow(dead_code)]` will resolve automatically when Plan 02 adds usages

## Self-Check

- [x] `manzo-core/src/eq10.rs` exists
- [x] Task commit `7125636` exists in git log
- [x] All 10 unit tests pass (`cargo test --lib eq10` exits 0)
- [x] `cargo build` exits 0 with zero warnings
- [x] No modifications to STATE.md or ROADMAP.md

---
*Phase: 04-dsp-engine*
*Completed: 2026-04-23*
