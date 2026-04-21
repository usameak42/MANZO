# Phase 2: Audio Pipeline - Context

**Gathered:** 2026-04-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Replace all 11 FFI stubs with a real MP3 decode + CoreAudio output pipeline.
`manzo_open` opens an MP3 file via mpg123-sys feed/read streaming API; `manzo_play` starts
float32 PCM output through cpal/CoreAudio on a background audio thread. The pipeline is
float32 end-to-end with no int16 conversion at any stage.

Codec scope: MP3 only via mpg123-sys. FLAC/WAV/AAC/OGG are v2 (ADVAUDIO-01) — not in this phase.

</domain>

<decisions>
## Implementation Decisions

### Spectrum Stub Behavior
- **D-01:** `manzo_get_spectrum` must zero-fill `out_buf` (write `count` f32 zeros) rather than
  leaving the buffer unwritten. Phase 2 does NOT implement the FFT pipeline — that is Phase 7's
  responsibility. Correct contract (buffer is always written) must be in place from Phase 2 onward.

### Threading Model
- **D-02:** `ManzoHandle` state (decoder + position + cpal stream) is protected with `Arc<Mutex<>>`.
  cpal's audio callback holds an `Arc<Mutex<InnerState>>` clone; FFI calls from Swift's main
  thread also lock through the same Arc. Mutex contention is negligible for a music player.
  Lock-free channels are explicitly deferred — they add complexity not justified at this stage.

### Test Asset
- **D-03:** A CC0 MP3 test clip (~5 seconds, synthesized tone or royalty-free) is committed
  to `manzo-core/tests/fixtures/test.mp3`. A Rust integration test in `tests/` uses this clip
  to verify the decode pipeline end-to-end (open → play → position advances). This enables
  automated acceptance testing without manual file selection.

### Error Reporting
- **D-04:** `manzo_open` returns null on failure; `manzo_play` / `manzo_seek` return non-zero
  `i32` on failure. No `manzo_last_error()` function in this phase — return codes are sufficient
  for Phase 2 development. A richer error API is deferred to Phase 3 when UI-facing error display
  is needed.

### Codec Scope
- **D-05:** MP3 only via mpg123-sys. FLAC, WAV, AAC, OGG deferred to v2 (ADVAUDIO-01).

### Claude's Discretion
- Internal `InnerState` struct design (fields: mpg123 handle, cpal stream, position tracking,
  playback flag)
- mpg123 feed chunk size (4096 bytes is the validated pattern from spike 003)
- cpal `BufferSize` — let cpal pick the default for CoreAudio; don't override unless there are
  audible glitches
- Ring buffer sizing between mpg123 decode output and cpal callback (if needed)
- File reading strategy (memory-map vs buffered `std::fs::File`)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Spike Findings (validated patterns)
- `.claude/skills/spike-findings-MANZO/references/audio-dsp-pipeline.md` — MP3 decode stack
  (mpg123 feed/read API, float32 pipeline, 529-sample delay), EQ math, pipeline format boundaries

### Project Planning
- `.planning/REQUIREMENTS.md` — AUDIO-01, AUDIO-04 (Phase 2 requirements), ADVAUDIO-01 (v2 deferred)
- `.planning/ROADMAP.md` — Phase 2 success criteria (4 items)
- `.planning/STATE.md` — Project decisions and accumulated constraints
- `.planning/PROJECT.md` — Core constraints, key decisions, tech stack

### Existing Code (Phase 1)
- `manzo-core/src/lib.rs` — All 11 FFI stub implementations to be replaced
- `manzo-core/Cargo.toml` — Crate config; add mpg123-sys, cpal, other deps here
- `manzo-core/cbindgen.toml` — cbindgen config; regenerate header after any FFI signature changes

### External Crates (check current versions)
- `mpg123-sys` — Rust bindings for libmpg123; feed/read streaming API
- `cpal` — Cross-platform audio output; CoreAudio backend on macOS

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ManzoHandle` struct in `lib.rs`: currently an opaque zero-size stub; Phase 2 replaces with
  a real `Box<InnerState>` where `InnerState` holds the mpg123 handle, cpal stream, and
  playback position. The FFI signature (`*mut ManzoHandle`) stays unchanged — callers unaffected.
- All 11 `#[no_mangle] pub extern "C" fn` signatures are correct and stay as-is; only the
  bodies change.

### Established Patterns
- `Box::into_raw` / `Box::from_raw` for opaque FFI handle lifecycle (`manzo_open` allocates,
  `manzo_close` deallocates) — standard safe pattern for this kind of C API.
- `cargo test` in `manzo-core/` is already wired into CI; new integration tests in `tests/`
  directory are picked up automatically.

### Integration Points
- cbindgen run-script in Xcode project generates `manzo_core.h` from `lib.rs`; if Phase 2
  changes any FFI function signatures, the header must be regenerated and the bridging header
  in `ManzoApp/` may need updating. Phase 2 MUST NOT change any FFI function signatures —
  only the implementations.
- ManzoApp/AppDelegate.swift calls `manzo_open` and `manzo_play` in the smoke test; Phase 2
  makes those calls produce real audio.

</code_context>

<specifics>
## Specific Ideas

- User confirmed: no additional codecs in Phase 2 — MP3 via mpg123-sys is the only decoder
- CC0 test clip in `tests/fixtures/test.mp3` enables automated Rust integration testing
- mpg123 feed chunk = 4096 bytes (from spike 003 — validated pattern, not to be changed)
- Decoder delay = 529 samples is a known constraint but gapless trimming is Phase 3's responsibility —
  Phase 2 does not need to handle it

</specifics>

<deferred>
## Deferred Ideas

- FLAC, WAV, AAC, OGG Vorbis codec support → v2, ADVAUDIO-01
- `manzo_last_error()` rich error string API → Phase 3 (when UI error display is needed)
- Lock-free command channel threading model → deferred; Arc<Mutex<>> is sufficient for v1
- Spectrum FFT pipeline (RustFFT, magnitude computation) → Phase 7

</deferred>

---

*Phase: 02-audio-pipeline*
*Context gathered: 2026-04-22*
