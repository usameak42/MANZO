# Phase 3: Playback Controls - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-22
**Phase:** 03-playback-controls
**Areas discussed:** FFI surface extension, Track-end detection, Track duration, 529-sample trim

---

## FFI Surface Extension

| Option | Description | Selected |
|--------|-------------|----------|
| Extend freely | Phase 3 can add functions as needed; '11 functions' was Phase 1's starting set | ✓ |
| Stay at 11 — sentinel values | Return u64::MAX from manzo_get_position() to signal track-end | |
| Stay at 11 — repurpose existing | Encode state into existing return values | |

**User's choice:** Extend freely
**Notes:** No restriction on FFI growth; Phase 3 adds manzo_get_state() and manzo_get_duration()

---

## Track-End Detection

| Option | Description | Selected |
|--------|-------------|----------|
| manzo_get_state() → i32 enum | Returns PLAYING=1, PAUSED=2, STOPPED=3, ENDED=4. Swift polls ~100ms. | ✓ |
| manzo_is_finished() → bool | Simpler bool; returns true only on natural EOF | |

**User's choice:** manzo_get_state() → i32 enum
**Notes:** Clean 4-state machine distinguishes all cases unambiguously

---

## Track Duration

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — manzo_get_duration() | Total ms via mpg123_length(); needed by Phase 8 seek UI | ✓ |
| No — defer to Phase 8 | Add when playlist/seek UI is built | |

**User's choice:** Yes — manzo_get_duration()
**Notes:** Add now while mpg123 is in scope; simpler than retrofitting in Phase 8

---

## 529-Sample Trim Implementation

| Option | Description | Selected |
|--------|-------------|----------|
| Audio callback counter | startup_skip_remaining: u64 = 529 in manzo_open; callback discards | ✓ |
| MPG123_GAPLESS flag | Let mpg123 handle via LAME metadata; not exactly 529 without valid tags | |

**User's choice:** Audio callback counter
**Notes:** Deterministic, no LAME metadata dependency, exact 529 samples

---

## Trim on Seek

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — re-trim on seek to 0 | Reset startup_skip_remaining to 529 on any seek | |
| No — trim only on manzo_open | Seeking does not re-arm the trim; pop at seek-to-0 acceptable | ✓ |

**User's choice:** No — trim only on manzo_open
**Notes:** User note: "silence gap is acceptable" — pop at seek is not a priority

---

## Claude's Discretion

- State variable internal representation (enum vs i32 field)
- Behavior of manzo_play on a STOPPED/ENDED handle
- Whether "never opened" returns STOPPED or a separate IDLE value
- CBR file duration accuracy via mpg123_length()

## Deferred Ideas

- True gapless crossfade (next track in same audio callback) — not a priority; silence gap OK
- manzo_last_error() rich error API — no UI in Phase 3, defer to Phase 5
- WR-03 mutex-held-across-decode-loop refactor — Phase 5
