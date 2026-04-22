---
phase: 03-playback-controls
fixed_at: 2026-04-22T05:02:47Z
review_path: .planning/phases/03-playback-controls/03-REVIEW.md
iteration: 1
findings_in_scope: 4
fixed: 4
skipped: 0
status: all_fixed
---

# Phase 03: Code Review Fix Report

**Fixed at:** 2026-04-22T05:02:47Z
**Source review:** .planning/phases/03-playback-controls/03-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 4
- Fixed: 4
- Skipped: 0

## Fixed Issues

### WR-01: Wrong byte-to-frame divisor in startup-skip branch causes 2x over-trim on stereo

**Files modified:** `manzo-core/src/lib.rs`
**Commit:** 9fd96f6
**Applied fix:** Changed `remaining_in_buf_samples` / `skip_samples` to frame-based arithmetic (`data.len() / channels`). Changed the `mpg123_read` byte count to `skip_frames * channels * 4`. Changed `discarded_bytes / 4` to `discarded_bytes / (4 * channels)` so the counter decrements in mono-equivalent frames, matching the `startup_skip_remaining` unit of 529 frames. Also renamed the variable to `discarded_frames` for clarity.

---

### WR-02: Potential infinite spin in startup-skip loop when decoder returns OK with zero bytes

**Files modified:** `manzo-core/src/lib.rs`
**Commit:** 9fd96f6
**Applied fix:** Changed the feed-more-data condition from `ret == MPG123_NEED_MORE && discarded_samples == 0` to simply `discarded_frames == 0`. This feeds a new chunk whenever no progress is made, regardless of the mpg123 return code, preventing an infinite spin when the decoder returns MPG123_OK with zero bytes during warm-up. The now-unused `ret` binding in the startup-skip block was renamed to `_ret` to suppress the unused-variable compiler warning.

---

### WR-03: `manzo_set_eq` stores EQ gains without range validation

**Files modified:** `manzo-core/src/lib.rs`
**Commit:** cafa0bb
**Applied fix:** Replaced `state.eq_gains.copy_from_slice(gain_slice)` with an explicit per-element loop using `f32::clamp(-12.0, 12.0)`. Added the same clamp to `eq_preamp`. `f32::clamp` maps NaN inputs to the boundary value, so this also guards against NaN/Inf propagating into the Phase 4 biquad DSP chain.

---

### WR-04: Hardcoded absolute developer path baked into the Swift binary

**Files modified:** `ManzoApp/ManzoApp/AppDelegate.swift`
**Commit:** d4dfb75
**Applied fix:** Replaced the literal `/Users/usameak42/Coding/MANZO/manzo-core/tests/fixtures/...` fallback with two portable alternatives: (1) a `MANZO_FIXTURE_DIR` environment variable override for CI runners and test machines, and (2) a bundle-relative path derived from `Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()` so the fallback resolves correctly on any machine regardless of developer home directory.

---

_Fixed: 2026-04-22T05:02:47Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
