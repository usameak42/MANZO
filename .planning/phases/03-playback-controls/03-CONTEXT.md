# Phase 3: Playback Controls - Context

**Gathered:** 2026-04-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire up working transport controls (play/pause/stop/seek) and auto-advance to the existing
Phase 2 audio pipeline. This is a pure Rust phase — no UI. Phase 3 delivers:

- `manzo_play`, `manzo_pause`, `manzo_stop`, `manzo_seek` working correctly with proper state transitions
- `manzo_get_state()` — new FFI function exposing current playback state (PLAYING/PAUSED/STOPPED/ENDED)
- `manzo_get_duration()` — new FFI function returning total track length in ms
- 529-sample mpg123 decoder delay trimmed at track open (no audible pop on track start)
- Auto-advance: Swift polls `manzo_get_state()` and calls `manzo_open` + `manzo_play` on the next track when ENDED

**Out of scope:**
- True gapless (seamless crossfade within single audio callback) — NOT required; silence gap is acceptable
- Playlist management or UI — Phase 8
- EQ/volume/pan DSP wiring — Phase 4
- Spectrum FFT — Phase 7

</domain>

<decisions>
## Implementation Decisions

### FFI Surface Extension
- **D-01:** FFI surface grows beyond 11 functions. Phase 1 established the initial 11 as stubs;
  Phase 3 adds two new query functions. The 11-function count was a starting set, not a permanent cap.
  New functions: `manzo_get_state(handle) -> i32` and `manzo_get_duration(handle) -> u64`.

### Track-End Detection
- **D-02:** `manzo_get_state()` returns an `i32` with these values:
  - `1` = PLAYING — audio callback is actively writing PCM
  - `2` = PAUSED — `manzo_pause` was called; audio callback fills silence
  - `3` = STOPPED — `manzo_stop` was called; decoder has been reset
  - `4` = ENDED — natural EOF reached by the audio callback (mpg123 returned DONE)
  
  ENDED is distinct from STOPPED so Swift can distinguish "user pressed stop" from "track finished".
  Swift polls `manzo_get_state()` on a ~100ms timer; when it returns ENDED (4), Swift calls
  `manzo_open` + `manzo_play` on the next track. Silence gap during this handoff is acceptable.

### Track Duration
- **D-03:** `manzo_get_duration(handle) -> u64` returns total track length in milliseconds,
  computed via `mpg123_length()` (returns total samples) divided by sample rate.
  Returns 0 if mpg123 cannot determine length (e.g., CBR file without LAME header scanned).
  Needed by Phase 8 seek UI and progress display; simpler to add now than retrofit later.

### 529-Sample Decoder Delay Trim
- **D-04:** Add `startup_skip_remaining: u64` field to `InnerState`, initialized to `529` in
  `manzo_open`. The audio callback reads-and-discards those samples before writing to the
  output buffer (decode into a temp buffer, write silence or simply advance without outputting).
  This eliminates the mpg123 decoder startup pop on each new track open.
  
  **Trim fires only on `manzo_open`** — `manzo_seek` does NOT reset the counter. Seeking
  mid-track (including seek-to-0) restarts the mpg123 decoder internally but a pop at seek
  is acceptable (silence gap is OK per project constraint).

### Gapless Policy
- **D-05:** True gapless (next track in same audio callback) is NOT required for v1.
  The minimum bar is no audible pop at track start. The 529-sample trim (D-04) achieves this.
  Auto-advance is Swift-driven via polling (D-02). A silence gap between tracks is acceptable.

### Claude's Discretion
- State variable storage: add a `PlaybackState` enum or `i32` field to `InnerState`
- Whether "never opened" / fresh handle returns STOPPED (3) or a distinct IDLE state
- How to handle `manzo_play` called on a STOPPED handle (re-play from start, or error?)
- Thread-safety of the new state transitions (same Arc<Mutex<InnerState>> model from Phase 2)
- Whether `manzo_get_duration` needs to scan CBR files to estimate length, or returns 0 and leaves it to Phase 8

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Spike Findings (validated patterns)
- `.claude/skills/spike-findings-MANZO/references/audio-dsp-pipeline.md` — MP3 decode stack
  (mpg123 feed/read API, float32 pipeline, 529-sample decoder delay). The 529 figure is
  confirmed here — do not change it.

### Project Planning
- `.planning/REQUIREMENTS.md` — AUDIO-02 (gapless trim), AUDIO-03 (transport), AUDIO-05 (auto-advance)
- `.planning/ROADMAP.md` — Phase 3 success criteria (4 items)
- `.planning/PROJECT.md` — Core constraints, key decisions, tech stack

### Existing Code (Phase 2 implementation to extend)
- `manzo-core/src/lib.rs` — Full Phase 2 implementation. Key items for Phase 3:
  - `InnerState` struct (add `startup_skip_remaining`, `playback_state` fields here)
  - Audio callback body (lines ~200–260) — add 529-sample skip logic and ENDED state here
  - `manzo_stop` (resets decoder via `mpg123_open_feed`) — set state to STOPPED (3)
  - `manzo_seek` (uses `mpg123_feedseek`) — does NOT reset startup_skip_remaining
  - `manzo_play` — set state to PLAYING (1)
  - `manzo_pause` — set state to PAUSED (2)
  - WR-03: mutex held across decode loop — known limitation, keep the existing warning comment

### Phase 2 Context
- `.planning/phases/02-audio-pipeline/02-CONTEXT.md` — D-02 (Arc<Mutex threading),
  D-04 (return codes only, no manzo_last_error in Phase 3)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `InnerState` in `lib.rs`: Extend with two new fields:
  - `startup_skip_remaining: u64` — initialized to 529 in `manzo_open`, decremented in audio callback
  - `playback_state: i32` — mirrors the `manzo_get_state()` return values (1/2/3/4)
- Audio callback already handles `is_playing: false` by filling silence and breaking — the
  ENDED state just needs to set `playback_state = 4` before that break.
- `manzo_stop` already calls `mpg123_open_feed` to reset the decoder — set `playback_state = 3` there.

### Established Patterns
- `Arc<Mutex<InnerState>>` — all state access goes through the mutex (D-02 from Phase 2)
- `#[no_mangle] pub extern "C" fn` pattern for all FFI functions — new functions follow the same
- cbindgen will auto-generate the header entries for new functions
- Return `i32` codes: 0 = success, negative = error (D-04 from Phase 2)
- WR-03 limitation (mutex held across decode loop) is documented and accepted for v1

### Integration Points
- `ManzoApp/AppDelegate.swift` — Swift smoke test; Phase 3 should demonstrate 2-file auto-advance
  by polling `manzo_get_state()` on a timer and calling `manzo_open`/`manzo_play` when ENDED
- cbindgen run-script regenerates `manzo_core.h` — new functions appear automatically after cargo build
- `manzo-core/tests/fixtures/test.mp3` — existing CC0 test clip; Phase 3 may need a second clip
  for the back-to-back gapless integration test

</code_context>

<specifics>
## Specific Ideas

- "Minimum bar is no audible pop; silence gap is acceptable" — this is the explicit v1 gapless policy
- 529 = the exact sample count from the mpg123 decoder startup delay (spike-validated). Hardcode this constant, do not try to read it from LAME metadata.
- `manzo_get_state()` returns `i32` (not an enum) to keep the C ABI simple — constants defined in
  the Swift bridging header as `MANZO_STATE_PLAYING = 1` etc.
- `manzo_get_duration()` uses `mpg123_length()` — available after the first successful `mpg123_read`
  call; may need to pre-read a chunk in `manzo_open` to bootstrap format detection before this works.

</specifics>

<deferred>
## Deferred Ideas

- True gapless (next track in same audio callback) — deferred; silence gap is acceptable for v1
- `manzo_last_error()` rich error string API — still no UI in Phase 3; defer to Phase 5
- Mutex-held-across-decode-loop fix (WR-03) — Phase 5 structural refactor planned
- CBR file duration scanning — `mpg123_length()` may return 0 for CBR files without LAME header;
  full scan deferred to Phase 8 when seek UI needs accurate duration

</deferred>

---

*Phase: 03-playback-controls*
*Context gathered: 2026-04-22*
