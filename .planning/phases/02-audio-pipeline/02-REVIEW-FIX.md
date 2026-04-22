---
phase: 02-audio-pipeline
fixed_at: 2026-04-22T00:30:00Z
review_path: .planning/phases/02-audio-pipeline/02-REVIEW.md
iteration: 1
findings_in_scope: 4
fixed: 4
skipped: 0
status: all_fixed
---

# Phase 2: Code Review Fix Report

**Fixed at:** 2026-04-22T00:30:00Z
**Source review:** .planning/phases/02-audio-pipeline/02-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 4
- Fixed: 4
- Skipped: 0

## Fixed Issues

### WR-04: `MPG123_NEED_MORE` cast to `i32` — type assumption not checked

**Files modified:** `manzo-core/src/lib.rs`
**Commit:** dd050a7
**Applied fix:** Replaced `as i32` with `as libc::c_int` on line 223 to make the
type intent unambiguous and consistent with the `c_int` return type of
`mpg123_read`. `libc::c_int` = `i32` on all Apple platforms, but the explicit
type name documents the intent and guards against future ports.

---

### WR-01: `manzo_stop` discards `mpg123_open_feed` return value — decoder may be in unknown state

**Files modified:** `manzo-core/src/lib.rs`
**Commit:** 1546a09
**Applied fix:** In the `manzo_stop` reset block, captured the `mpg123_open_feed`
return value into `feed_ret`. On success (`feed_ret == 0`) the existing
`mpg123_feed` call and `file_offset` update proceed unchanged. On failure, the
decoder feed is skipped, `file_offset` is set to 0 (so next `manzo_play`
rebuilds the stream from the beginning), and a diagnostic is printed via
`eprintln!`. Matches the pattern already used in the `manzo_open` path
(lines 102-106).

---

### WR-02: `off_t → usize` cast in `manzo_seek` wraps on negative value

**Files modified:** `manzo-core/src/lib.rs`
**Commit:** d147371
**Applied fix:** Replaced the single-line `(input_byte_offset as usize).min(...)` with
an explicit sign check. If `input_byte_offset >= 0` the existing clamped cast
is used. If negative, `file_offset` is set to 0 (seek-to-start fallback) and a
diagnostic is logged via `eprintln!`. This prevents the wrap-to-huge-number
scenario where `.min(file_data.len())` would silently set the offset to EOF,
causing immediate EOF on the next decode iteration.

---

### WR-03: Mutex held across entire decode loop — can stall UI thread in `manzo_pause` / `manzo_seek`

**Files modified:** `manzo-core/src/lib.rs`
**Commit:** 2225c00
**Applied fix:** Full struct split (separating `ControlState` from `DecoderState`)
is an invasive architecture change not suited to a single atomic commit at this
phase. Instead, added a `KNOWN LIMITATION (WR-03)` block comment at the lock
acquisition site (line 191) explaining:
- The exact failure mode (UI-thread stall if callback is mid-decode)
- The frame budget risk (8 ms on slow paths)
- The concrete Phase 5 fix pattern: split `InnerState` into mutex-guarded
  `ControlState { is_playing, file_offset, position_samples }` and
  audio-thread-only `DecoderState { mpg_handle, file_data, ... }`, copy
  control flags at callback entry, release lock before the `mpg123_read` loop.
- Reference to spike 004 findings for the full pattern.

This documents the technical debt in-code so the Phase 5 implementer cannot miss it.

---

_Fixed: 2026-04-22T00:30:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
