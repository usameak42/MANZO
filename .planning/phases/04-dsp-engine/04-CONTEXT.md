# Phase 4: DSP Engine - Context

**Gathered:** 2026-04-22
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire real-time 10-band IIR EQ, preamp, volume, and pan into the Rust audio callback.
Pure Rust phase — no UI, no new FFI functions. All three FFI stubs (`manzo_set_eq`,
`manzo_set_volume`, `manzo_set_pan`) have correct signatures from Phase 3; Phase 4
replaces their no-op bodies with real DSP processing.

**Out of scope:**
- Any UI for EQ controls — Phase 5+
- .eqf preset file loading — Phase 8
- VALTODB mapping utility — Phase 8
- Additional codecs or pipeline changes — unchanged from Phase 2/3

</domain>

<decisions>
## Implementation Decisions

### Signal Chain Order
- **D-01:** Winamp-canonical signal chain in the audio callback:
  `mpg123 float32 → preamp gain → 10-band biquad IIR → dynamic limiter → master volume → stereo pan → cpal output`
  Volume controls perceived loudness post-EQ; preamp prevents biquad input clipping.

### Coefficient Computation
- **D-02:** Biquad coefficients (sin/cos/exp math via `eq10_bsetup`) are pre-computed in
  `manzo_set_eq` on the UI/caller thread, not lazily in the audio callback. The audio callback
  reads pre-computed coefficients — zero trigonometric computation in the hot path.
  The `InnerState` stores the computed `eq10_t` struct (or Rust equivalent), updated under
  the existing Arc<Mutex<>> on each `manzo_set_eq` call.

### Gain Change Smoothing
- **D-03:** EQ band changes are applied instantly at the start of the next buffer (coefficient
  swap — no audible click between consecutive buffers). Volume and pan changes are linearly
  interpolated (ramped) over ~441 samples (~10 ms at 44.1 kHz) to prevent pops on large steps.
  Both use the same Arc<Mutex<>> model from Phase 2; target values are stored under mutex and
  the audio callback applies the ramp logic.

### Output Limiter
- **D-04:** Port the **dynamic limiter** from `eq10dsp.cpp` verbatim — NOT a static multiply.
  The limiter is a peak-detector compressor: it tracks `detect` (instantaneous peak of output
  samples), scales when `detect > EQ10_TRIM_CODE (0.930)`, and decays with
  `detectdecay = pow(0.001, 1.0 / (rate * EQ10_TRIM_RELEASE))` where `EQ10_TRIM_RELEASE = 0.700` seconds.
  Fields to port: `eq10_t.detect`, `eq10_t.detectdecay`. The limiter must be controlled by a
  `config_eq_limiter` boolean (default: enabled) matching the original's behavior.

### Gain Representation
- **D-05:** Internally, band gain is stored as `eq10_db2gain(dB) = pow(10.0, dB/20.0) - 1.0`
  (shifted linear, so 0 dB → gain=0.0, not gain=1.0). The FFI accepts dB (±12.0) and the Rust
  port converts on `manzo_set_eq`. This matches eq10dsp.cpp's `eq10_setgain` exactly.

### `eq10_processf` Channel Handling
- **D-06:** `eq10_processf` in the original takes interleaved multichannel with `idx` (channel
  index) and `step` (channel count). For stereo, it is called twice per buffer: once for L
  (idx=0, step=2) and once for R (idx=1, step=2). The Rust port must replicate this
  per-channel call pattern — one `eq10_t` instance per channel.

### Performance Proof
- **D-07:** Add a `#[test]` integration test that processes 1000 × 1024-sample stereo buffers
  through the full EQ chain, measures each with `Instant::now()`, and asserts max elapsed <
  100 µs. Runs automatically in `cargo test`. Pattern mirrors Winamp's own `#ifdef TESTCASE`
  stress loop but adds a timing gate.

### Claude's Discretion
- Rust struct layout for the ported `eq10_t` (may use f64 fields matching the C original)
- Whether `eq10_t` per-channel instances live inside `InnerState` directly or in a sub-struct
- NEON SIMD optimization — benchmark first; apply only if the integration test fails the 100 µs gate
- Ramp implementation detail (linear ramp state tracking for vol/pan in `InnerState`)
- Whether `config_eq_limiter` is a runtime field in `InnerState` (defaulting to `true`) or a
  compile-time constant for Phase 4

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Primary Source (MANDATORY — read directly, do not rely on spike summaries)
- `winamp/Src/Winamp/eq10dsp.cpp` — Full EQ10 library source: `eq10_processf`, `eq10_bsetup`,
  `eq10_setup`, `eq10_setgain`, dynamic limiter. Port this directly.
- `winamp/Src/Winamp/eq10dsp.h` — EQ10 type definitions: `eq10_t`, `eq10band_t`, constants
  (`EQ10_TRIM_CODE=0.930`, `EQ10_TRIM_RELEASE=0.700`, `EQ10_Q=1.41`, `EQ10_NOFBANDS=10`),
  band frequency tables (Winamp: 70–16K Hz, ISO: 31–16K Hz).
- `winamp/Src/Winamp/In.cpp:1224` — `VALTODB()` reference implementation (defer to Phase 8
  but verify the dB mapping is consistent: raw=0→+12 dB, raw=31→0 dB, raw=63→-12 dB).

### Spike Findings (supplementary — source files above take precedence)
- `.claude/skills/spike-findings-MANZO/references/audio-dsp-pipeline.md` — DSP pipeline context,
  EQ math overview. **Note corrections from source:** (1) the limiter is dynamic, not a static
  TRIM_CODE multiply; (2) VALTODB sign: raw=0→+12 dB (boost), raw=63→-12 dB (cut).

### Existing Code (Phase 2/3 implementation to extend)
- `manzo-core/src/lib.rs` — Current implementation. Key items:
  - `InnerState` struct (add `eq10_l: Eq10State`, `eq10_r: Eq10State`, `target_volume: f32`,
    `target_pan: f32`, ramp state fields)
  - `manzo_set_eq` (line ~490): stub stores gains — replace with biquad coefficient pre-computation
  - `manzo_set_volume` (line ~517): stub stores volume — add target_volume for ramp
  - `manzo_set_pan` (line ~530): stub stores pan — add target_pan for ramp
  - Audio callback body: insert EQ processing, vol/pan ramp application

### Project Planning
- `.planning/REQUIREMENTS.md` — DSP-01, DSP-02, DSP-03, DSP-04
- `.planning/ROADMAP.md` — Phase 4 success criteria (4 items)
- `.planning/PROJECT.md` — Float32 pipeline constraint, EQ < 0.1 ms per 1024-sample buffer on M1

### Prior Phase Context
- `.planning/phases/02-audio-pipeline/02-CONTEXT.md` — D-02 (Arc<Mutex<>> threading model)
- `.planning/phases/03-playback-controls/03-CONTEXT.md` — D-01 (FFI surface can grow beyond 11)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Arc<Mutex<InnerState>>` model: all DSP parameter updates go through the same mutex already
  used by playback state — no new synchronization primitive needed.
- `manzo_set_eq` / `manzo_set_volume` / `manzo_set_pan` stubs: correct signatures, null guards,
  and mutex locking already present — Phase 4 replaces only the body logic.
- `InnerState.eq_gains: [f32; 10]` and `InnerState.eq_preamp: f32` already allocated and clamped
  to ±12.0 dB in the Phase 3 stub.

### Established Patterns
- Float32 interleaved stereo buffer in the cpal audio callback — same buffer that EQ processes
- `Arc<Mutex<InnerState>>` clone held by the cpal callback closure — EQ processing happens
  inside this closure, after the 529-sample startup skip, before the cpal output write
- Return `i32` codes for FFI functions; `0` = success (D-04 from Phase 2)

### Integration Points
- cpal audio callback (in `manzo_play` closure): insert the DSP chain between mpg123 decode
  and the cpal output buffer write. Chain: read decoded float32 → apply preamp scalar →
  call `eq10_processf` for L channel → call `eq10_processf` for R channel → apply dynamic
  limiter → apply vol/pan ramp → write to cpal output buffer.
- cbindgen auto-generates the C header — no new FFI functions means no header changes needed.
- `manzo-core/tests/` integration tests: add `eq_perf_under_100us` test here.

</code_context>

<specifics>
## Specific Ideas

- Read `eq10dsp.cpp` directly from `winamp/Src/Winamp/eq10dsp.cpp` — do not rely solely on
  spike summaries (the dynamic limiter detail was incorrect in the spike summary).
- Dynamic limiter detail: `detect` tracks instantaneous peak, decays over 0.7s. Scale output
  only when `detect > 0.930`. Port `eq10_t.detect` and `eq10_t.detectdecay` as f64 fields.
- Biquad dual-coefficient sets: `ua0/ub1/ub2` (boost) and `da0/db1/db2` (cut) — the per-band
  gain sign selects which coefficient set is used, matching the original branch exactly.
- vol/pan ramp: 441 samples at 44.1 kHz = ~10 ms. Ramp completes when `current == target`.
  Store `vol_ramp_remaining: u32` and `pan_ramp_remaining: u32` in `InnerState`.
- VALTODB is deferred to Phase 8 but the formula is confirmed: `raw=0→+12 dB`, `raw=31→0 dB`,
  `raw=63→-12 dB`. Phase 8 test code can use dB values directly to set EQ without VALTODB.

</specifics>

<deferred>
## Deferred Ideas

- `.eqf` preset file loading → Phase 8 (playlist/library UI); VALTODB utility ports there too
- VALTODB mapping function → Phase 8 (when EQ slider UI is built)
- ISO frequency mode (31–16K Hz) → deferred; Winamp mode (70–16K Hz) hardcoded for v1.
  Phase 8 could expose a config toggle.
- EQ band detector code (`EQ10_DETECTOR_CODE`) → not ported; spike and source both confirm
  this is commented out in the shipped Winamp binary
- NEON SIMD explicit intrinsics → only if integration test fails 100 µs gate

</deferred>

---

*Phase: 04-dsp-engine*
*Context gathered: 2026-04-22*
