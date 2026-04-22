# Phase 4: DSP Engine - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-22
**Phase:** 04-dsp-engine
**Areas discussed:** Signal chain order, Click prevention, Output limiter (TRIM_CODE), Performance proof method, .eqf preset loading

---

## Signal Chain Order

| Option | Description | Selected |
|--------|-------------|----------|
| preamp → EQ → vol → pan | Winamp-canonical. EQ shapes tone, volume controls perceived loudness post-EQ. | ✓ |
| vol → preamp → EQ → pan | Volume before EQ as input attenuation. Safer for hot tracks but non-standard. | |
| preamp → EQ → pan → vol | Pan before volume — minor difference, only relevant for non-linear pan/vol interaction. | |

**User's choice:** preamp → EQ → vol → pan (Winamp-canonical)

---

## Click Prevention — Volume / Pan

| Option | Description | Selected |
|--------|-------------|----------|
| Ramp over ~10 ms | Linear interpolation over ~441 samples. Inaudible latency, eliminates pop on large steps. | |
| Instant at buffer start | Zero latency, may click on large jumps (e.g. 0→1.0). | |
| Instant for EQ, ramp for vol/pan | EQ instant (coefficient swap, inaudible). Vol/pan get 10ms ramp. Best of both. | ✓ |

**User's choice:** Instant for EQ, ramp for vol/pan

---

## Coefficient Computation — EQ Update

| Option | Description | Selected |
|--------|-------------|----------|
| Instant at next buffer start | Recompute biquad coefficients (sin/cos) in audio callback on each parameter change. | |
| Pre-computed in manzo_set_eq | Compute coefficients on UI thread; audio callback reads ready-to-use values. Zero trig in hot path. | ✓ |

**User's choice:** Pre-computed in manzo_set_eq (UI thread)

---

## Output Limiter (TRIM_CODE)

| Option | Description | Selected |
|--------|-------------|----------|
| Port verbatim — TRIM_CODE=0.930 | Full dynamic limiter from eq10dsp.cpp (detect + detectdecay + TRIM_RELEASE). Bit-accurate. | ✓ |
| Omit — rely on float32 range | Simpler code; heavy multi-band boosts will clip at DAC. | |

**User's choice:** Port verbatim — dynamic limiter (NOT a static multiply)

**Notes:** User explicitly clarified post-selection that the limiter is a dynamic peak-detector
compressor, not a static TRIM_CODE multiply. Phase 4 must port `eq10.detect`, `eq10.detectdecay`,
and `EQ10_TRIM_RELEASE=0.700s`. User also flagged that the Winamp source at
`/Users/usameak42/Coding/MANZO/Winamp` must be read directly — spike summary was inaccurate
on this point.

---

## Performance Proof Method

| Option | Description | Selected |
|--------|-------------|----------|
| Integration test, Instant::now() | #[test] asserting < 100 µs per buffer; runs in cargo test automatically. | ✓ |
| Print-only bench, no assertion | eprintln! timing, human verifies once. No CI gate. | |
| cargo bench (criterion) | Separate bench/, requires cargo bench separately; better for trend tracking. | |

**User's choice:** Integration test with Instant::now() assertion

**Notes:** User researched the original Winamp source first. Finding: Winamp has NO timing
assertions in eq10dsp.cpp — only a `#ifdef TESTCASE` correctness stress loop (10,000 iterations,
no timing). User directed to read source directly and not rely on spike summary.

---

## .eqf Preset Loading / VALTODB

| Option | Description | Selected |
|--------|-------------|----------|
| Defer to Phase 8 | VALTODB only needed for .eqf loading or UI sliders; both are Phase 8. FFI accepts dB directly. | ✓ |
| Include VALTODB in Phase 4 | Add valtodb() helper + manzo_load_eq_preset() FFI function. | |

**User's choice:** Defer to Phase 8

**Notes:** VALTODB mapping confirmed from `winamp/Src/Winamp/In.cpp:1224`:
raw=0 → +12 dB (boost), raw=31 → 0 dB (flat), raw=63 → -12 dB (cut). The spike summary
had the sign label wrong but the formula is correct.

---

## Claude's Discretion

- Rust struct layout for ported eq10_t (f64 fields to match C original)
- Per-channel eq10_t instance placement in InnerState
- NEON SIMD — only if 100 µs test fails
- config_eq_limiter as runtime bool in InnerState vs compile-time constant
- Ramp state field names in InnerState

## Deferred Ideas

- .eqf preset file loading → Phase 8
- VALTODB utility → Phase 8
- ISO frequency mode (31–16K Hz) → Phase 8 config toggle
- EQ band detector code (EQ10_DETECTOR_CODE) → not ported (commented out in Winamp binary)
- NEON SIMD optimization → only if performance test fails
