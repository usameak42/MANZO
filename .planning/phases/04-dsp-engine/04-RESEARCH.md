# Phase 4: DSP Engine - Research

**Researched:** 2026-04-22
**Domain:** Rust DSP — biquad IIR EQ, dynamic limiter, volume/pan ramping
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01** Signal chain: `mpg123 float32 → preamp gain → 10-band biquad IIR → dynamic limiter → master volume → stereo pan → cpal output`
- **D-02** Biquad coefficients pre-computed on caller thread in `manzo_set_eq`; audio callback reads pre-computed values only — no trig in the hot path. Storage: the computed `eq10_t` struct in `InnerState` under existing `Arc<Mutex<>>`.
- **D-03** EQ band changes: coefficient swap at start of next buffer (no click). Volume/pan: linear ramp over ~441 samples (~10 ms at 44.1 kHz). Both use `Arc<Mutex<InnerState>>` target-value model.
- **D-04** Port the **dynamic limiter** from `eq10dsp.cpp` verbatim — not a static multiply. Peak-detector compressor: tracks `detect`, scales when `detect > EQ10_TRIM_CODE (0.930)`, decays with `detectdecay = pow(0.001, 1.0/(rate * 0.700))`. Controlled by `config_eq_limiter` boolean (default: `true`).
- **D-05** Gain representation: `eq10_db2gain(dB) = pow(10.0, dB/20.0) - 1.0` (shifted linear; 0 dB → 0.0). FFI receives dB; Rust converts in `manzo_set_eq`.
- **D-06** `eq10_processf` called twice per buffer: L channel (idx=0, step=2), R channel (idx=1, step=2). One `eq10_t` instance per channel.
- **D-07** Integration test `eq_perf_under_100us` in `manzo-core/tests/`: processes 1000 × 1024-sample stereo buffers, measures each with `Instant::now()`, asserts max elapsed < 100 µs. Runs automatically in `cargo test`.

### Claude's Discretion

- Rust struct layout for the ported `eq10_t` (may use f64 fields matching the C original)
- Whether `eq10_t` per-channel instances live inside `InnerState` directly or in a sub-struct
- NEON SIMD optimization — benchmark first; apply only if the integration test fails the 100 µs gate
- Ramp implementation detail (linear ramp state tracking for vol/pan in `InnerState`)
- Whether `config_eq_limiter` is a runtime field in `InnerState` (defaulting to `true`) or a compile-time constant for Phase 4

### Deferred Ideas (OUT OF SCOPE)

- `.eqf` preset file loading → Phase 8
- VALTODB mapping function → Phase 8
- ISO frequency mode (31–16K Hz) → Phase 8 optional toggle
- EQ band detector code (`EQ10_DETECTOR_CODE`) — commented out in shipped Winamp binary; do not port
- NEON SIMD explicit intrinsics — only if 100 µs gate fails

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DSP-01 | App applies 10-band parametric EQ using a Rust port of eq10dsp.cpp dual-biquad IIR | Full source read; biquad math, coefficient setup, and limiter documented below |
| DSP-02 | User can adjust each EQ band (±12 dB) in real time without audio dropout | Coefficient-swap pattern verified from source; pre-computation on caller thread (D-02) |
| DSP-03 | App exposes EQ preamp gain control | Preamp is a scalar multiply before the biquad chain; clamped to ±12 dB in existing stub |
| DSP-04 | User can control master volume (0–100%) and stereo pan | Linear ramp pattern (D-03); existing `manzo_set_volume`/`manzo_set_pan` stub signatures correct |

</phase_requirements>

---

## Summary

Phase 4 is a pure Rust extension of `manzo-core/src/lib.rs`. No new FFI functions, no Swift changes, no new build wiring. The three stubs — `manzo_set_eq`, `manzo_set_volume`, `manzo_set_pan` — already have correct signatures and mutex locking from Phase 3; Phase 4 replaces their no-op bodies with real DSP logic and inserts the processing chain into the cpal audio callback.

The core work is porting ~200 lines of `eq10dsp.cpp` to idiomatic Rust. The algorithm is a 10-band peaking EQ using dual-coefficient biquad IIR (separate coefficient sets for boost and cut), followed by a peak-detector dynamic limiter. All floating-point operations use f64 internally for the filter state, matching the original exactly; samples flow as f32 (matching the Float32 pipeline constraint from CLAUDE.md).

The performance target — under 100 µs per 1024-sample stereo buffer on M1 — is easily achievable without SIMD. The Winamp `#ifdef TESTCASE` stress loop processes 10,000 × 4096-sample buffers in a single-threaded loop; 1024 samples at 44.1 kHz requires roughly 23 µs of real-time budget. The integration test (D-07) must enforce this mechanically.

**Primary recommendation:** Port `eq10_processf`, `eq10_bsetup`, `eq10_setup`, `eq10_setgain`, and `eq10_db2gain` verbatim to Rust structs `Eq10Band` and `Eq10State`. Insert them into `InnerState` as `eq_l: Eq10State` and `eq_r: Eq10State`. Add target/current ramp fields for volume and pan. Wire the chain into the cpal callback after the 529-sample skip, before the cpal output write.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Biquad coefficient computation | Rust / caller thread | — | Pre-computed in `manzo_set_eq` (D-02); avoids trig in audio hot path |
| EQ sample processing (10-band IIR) | Rust / audio thread (cpal callback) | — | Must run in-band with decoded samples; zero-copy in-place |
| Dynamic limiter | Rust / audio thread (cpal callback) | — | Operates per-sample on EQ output; shares buffer |
| Preamp gain | Rust / audio thread (cpal callback) | — | Scalar multiply before biquad; no floating-point setup needed |
| Volume/pan ramp | Rust / audio thread (cpal callback) | — | Per-sample ramp state; ramp targets read from `InnerState` under mutex |
| DSP parameter updates | Rust / caller (FFI) thread | — | Writes to `InnerState` under `Arc<Mutex<>>`; audio callback reads atomically |
| Performance test | Rust / `cargo test` | — | Integration test in `manzo-core/tests/` (D-07) |

---

## Standard Stack

### Core (no new dependencies required)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| (no new deps) | — | All DSP implemented in pure Rust std | Phase 4 is pure algorithmic code; `f64::sin`, `f64::cos`, `f64::exp`, `f64::powf` from `std` suffice |

**Confirmed:** Cargo 1.95.0, rustc 1.95.0 (2026-04-14). No new crates are required. `[VERIFIED: cargo --version on machine]`

### Supporting (already in Cargo.toml)

| Library | Version | Purpose |
|---------|---------|---------|
| libc | 0.2 | Already present; no new use in Phase 4 |
| cpal | 0.15 | Audio callback where DSP chain executes |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Pure Rust std math (sin/cos) | `libm` crate | `libm` only useful for `no_std`; not needed here |
| Manual NEON SIMD | `std::arch::aarch64` intrinsics | Deferred per D-07: benchmark first. Autovetorizer on AArch64 will handle f64 loops in release mode |

**Installation:** No new packages. `Cargo.toml` unchanged.

---

## Architecture Patterns

### System Architecture Diagram

```
manzo_set_eq(gains[10], preamp)          manzo_set_volume(v)   manzo_set_pan(p)
        │                                        │                    │
        ▼                                        ▼                    ▼
[caller thread: eq10_bsetup × 10 bands]   [InnerState.target_volume]  [InnerState.target_pan]
        │                                        │                    │
        └──────────────────────────────► Arc<Mutex<InnerState>> ◄─────┘
                                                 │
                                    [cpal audio callback — per buffer]
                                                 │
                                    ┌────────────▼────────────┐
                                    │  mpg123_read → f32 PCM  │
                                    │  (interleaved stereo)   │
                                    └────────────┬────────────┘
                                                 │
                                    ┌────────────▼────────────┐
                                    │  preamp scalar multiply  │
                                    │  buf[i] *= preamp_gain  │
                                    └────────────┬────────────┘
                                                 │
                              ┌──────────────────▼──────────────────┐
                              │  eq10_processf L (idx=0, step=2)    │
                              │  10 biquad bands, f64 state, f32 io │
                              └──────────────────┬──────────────────┘
                                                 │
                              ┌──────────────────▼──────────────────┐
                              │  eq10_processf R (idx=1, step=2)    │
                              └──────────────────┬──────────────────┘
                                                 │
                              ┌──────────────────▼──────────────────┐
                              │  dynamic limiter (per-channel)       │
                              │  peak-detect → scale if > 0.930     │
                              └──────────────────┬──────────────────┘
                                                 │
                              ┌──────────────────▼──────────────────┐
                              │  vol/pan ramp (per-sample, 441-samp)│
                              │  data[L] *= vol * L_gain(pan)       │
                              │  data[R] *= vol * R_gain(pan)       │
                              └──────────────────┬──────────────────┘
                                                 │
                                    ┌────────────▼────────────┐
                                    │  cpal output buffer      │
                                    └─────────────────────────┘
```

### Recommended Project Structure

```
manzo-core/
├── src/
│   ├── lib.rs          # FFI surface + InnerState + cpal callback (extend in place)
│   └── eq10.rs         # NEW: Eq10Band, Eq10State structs + all eq10_* functions
└── tests/
    └── integration_test.rs  # ADD: eq_perf_under_100us test
```

**Rationale for `eq10.rs` module:** The biquad implementation is ~120 lines of pure Rust math with no FFI dependencies. Separating it from `lib.rs` keeps the FFI surface file clean and makes the port independently testable. The module is `pub(crate)` — not exposed to cbindgen.

### Pattern 1: Eq10State Rust Struct (direct port of `eq10_t`)

**What:** One `Eq10State` per audio channel, storing all biquad filter state for 10 bands plus the global limiter state.

**Source:** `winamp/Src/Winamp/eq10dsp.h` — `eq10_t`, `eq10band_t` structs read directly.

```rust
// Source: winamp/Src/Winamp/eq10dsp.h (read directly 2026-04-22)
// eq10band_t maps to Eq10Band; eq10_t maps to Eq10State.
// ALL fields are f64 to match the original's double precision.
// EQ10_DETECTOR_CODE is NOT defined in shipped Winamp — omit detect/detectdecay per-band.

pub(crate) struct Eq10Band {
    pub gain: f64,      // shifted-linear gain; 0.0 = 0 dB
    pub ua0: f64, pub ub1: f64, pub ub2: f64,  // boost coefficients
    pub da0: f64, pub db1: f64, pub db2: f64,  // cut coefficients
    pub x1: f64, pub x2: f64,   // input delay line
    pub y1: f64, pub y2: f64,   // output delay line
}

pub(crate) struct Eq10State {
    pub rate: f64,
    pub band: [Eq10Band; 10],
    pub detect: f64,       // global limiter peak tracker
    pub detectdecay: f64,  // precomputed: pow(0.001, 1/(rate * 0.700))
}
```

### Pattern 2: `eq10_bsetup` Rust Port

**What:** Computes two sets of biquad coefficients (boost Q=EQ10_Q*2, cut Q=EQ10_Q*0.5) for one band. Called from `manzo_set_eq` on the caller thread.

**Source:** `winamp/Src/Winamp/eq10dsp.cpp` lines 36–77, read directly.

Key math (verbatim translation):
```rust
// Source: eq10dsp.cpp eq10_bsetup2 (verified 2026-04-22)
// Called twice per band: once with boost Q (Q*2.0), once with cut Q (Q*0.5)
fn eq10_bsetup2(boost: bool, rate: f64, band: &mut Eq10Band, freq: f64, q: f64) {
    let rate = rate.clamp(4000.0, 384000.0);
    let freq = freq.max(20.0);
    if freq >= rate * 0.499 {
        if boost { band.ua0 = 0.0; } else { band.da0 = 0.0; }
        return;
    }
    let angle = 2.0 * std::f64::consts::PI * freq / rate;
    let alpha = angle.sin() / (2.0 * q);
    let b0 = 1.0 / (1.0 + alpha);
    let a0 = b0 * alpha;
    let b1 = b0 * 2.0 * angle.cos();
    let b2 = b0 * (alpha - 1.0);
    if boost {
        band.ua0 = a0; band.ub1 = b1; band.ub2 = b2;
    } else {
        band.da0 = a0; band.db1 = b1; band.db2 = b2;
    }
}
```

### Pattern 3: `eq10_processf` Rust Port — Hot Path

**What:** Per-buffer, per-channel biquad processing. Called twice per cpal buffer (L and R).

**Source:** `winamp/Src/Winamp/eq10dsp.cpp` lines 98–206, read directly.

**Critical behavioral details extracted from source:**

1. `buf` and `outbuf` can be the same pointer (in-place) — the Rust port passes the same slice for both.
2. `in` pointer starts at `buf + idx` and advances by `step` each sample.
3. After each band's inner loop, `in = outbuf` — subsequent bands read the previous band's output. This is the cascade: band 1 output feeds band 2 input.
4. `a0 == 0.0` check: if gain is 0 and coefficient is 0, skip the band entirely (optimization from the original).
5. Denormal fix: `+ 1e-30_f64` is added to `y0` inside the sample loop (DENORMAL_FIX is defined in the original).
6. Limiter reads from `in` (which after the 10-band loop equals `outbuf` = the EQ output). Limiter writes back to `outbuf`.

```rust
// Source: eq10dsp.cpp eq10_processf (verified 2026-04-22)
// In the Rust port, buf == outbuf (same interleaved slice, in-place).
// idx = 0 (L) or 1 (R); step = 2 (stereo).
// sz = number of FRAMES (not samples); inner loops advance by step.
fn eq10_processf(
    eq: &mut Eq10State,
    buf: &mut [f32],   // interleaved stereo, same as outbuf
    sz: usize,         // number of frames
    idx: usize,        // channel index (0=L, 1=R)
    step: usize,       // channel count (2)
    config_eq_limiter: bool,
) {
    // Phase 1: 10-band cascade
    // NOTE: 'in_ptr' logic modeled by tracking offset: starts at idx, then switches to idx
    // after each band (because in-place, outbuf == buf)
    for k in 0..10 {
        let band = &mut eq.band[k];
        let gain = band.gain;
        let (a0, b1, b2) = if gain > 0.0 {
            (band.ua0 * gain, band.ub1, band.ub2)
        } else {
            (band.da0 * gain, band.db1, band.db2)
        };
        if a0 == 0.0 { continue; }

        let mut x1 = band.x1; let mut x2 = band.x2;
        let mut y1 = band.y1; let mut y2 = band.y2;
        for t in 0..sz {
            let i = idx + t * step;
            let x = buf[i] as f64;
            let y0 = (x - x2) * a0 + y1 * b1 + y2 * b2 + 1e-30_f64; // denormal fix
            x2 = x1; x1 = x; y2 = y1; y1 = y0;
            buf[i] = (y0 + x) as f32;   // peaking: add filtered delta to input
        }
        band.x1 = x1; band.x2 = x2; band.y1 = y1; band.y2 = y2;
    }

    // Phase 2: dynamic limiter
    if config_eq_limiter {
        let mut detect = eq.detect;
        let detectdecay = eq.detectdecay;
        for t in 0..sz {
            let i = idx + t * step;
            let s = buf[i] as f64;
            if s.abs() > detect { detect = s.abs(); }
            buf[i] = if detect > 0.930 {
                (s * (0.930 / detect)) as f32
            } else {
                s as f32
            };
            detect *= detectdecay;
            detect += 1e-30_f64; // denormal fix
        }
        eq.detect = detect;
    }
}
```

### Pattern 4: Preamp Gain Application

**What:** Scalar multiply applied to every sample before the biquad chain.

**Source:** CONTEXT.md D-01; `eq10_db2gain` formula from `eq10dsp.cpp` line 208.

```rust
// preamp_gain is stored in InnerState as a linear scalar (NOT dB).
// Converted in manzo_set_eq: preamp_gain_linear = 10_f32.powf(eq_preamp_dB / 20.0)
// In callback:
for sample in data.iter_mut() {
    *sample *= preamp_gain_linear;
}
```

**Note:** The preamp is applied to the entire interleaved buffer before the per-channel EQ calls. No channel-splitting needed at this stage.

### Pattern 5: Volume/Pan Linear Ramp

**What:** Per-sample linear interpolation from `current_volume` → `target_volume` and `current_pan` → `target_pan` over 441 samples.

**Source:** CONTEXT.md D-03; specifics section.

```rust
// Fields added to InnerState:
// target_volume: f32      — written by manzo_set_volume
// current_volume: f32     — ramp tracks toward target_volume
// target_pan: f32         — written by manzo_set_pan
// current_pan: f32        — ramp tracks toward target_pan
// vol_ramp_remaining: u32  — frames left in current ramp (init 0)
// pan_ramp_remaining: u32  — frames left in current ramp (init 0)

// Pan law: constant-power or linear gain split. Linear is simpler and used here:
// L_gain = (1.0 - pan).min(1.0).max(0.0)     (pan=-1 → L=1, pan=0 → L=1, pan=1 → L=0)
// R_gain = (1.0 + pan).min(1.0).max(0.0)
// (For pan in [-1,1]: at center both = 1.0 → 0 dB center; at extremes one goes to 0)

// Per-frame in callback (after limiter):
for frame in 0..num_frames {
    // Advance ramp
    if s.vol_ramp_remaining > 0 {
        let step = (s.target_volume - s.current_volume) / s.vol_ramp_remaining as f32;
        s.current_volume += step;
        s.vol_ramp_remaining -= 1;
    } else {
        s.current_volume = s.target_volume;
    }
    // Same pattern for pan...

    let l = frame * 2;
    let r = frame * 2 + 1;
    let l_gain = (1.0 - s.current_pan).clamp(0.0, 1.0);
    let r_gain = (1.0 + s.current_pan).clamp(0.0, 1.0);
    data[l] *= s.current_volume * l_gain;
    data[r] *= s.current_volume * r_gain;
}
```

**Ramp trigger:** `manzo_set_volume` and `manzo_set_pan` write the new target and reset `vol_ramp_remaining = 441` / `pan_ramp_remaining = 441` under the mutex.

### Anti-Patterns to Avoid

- **Trig in the audio callback:** Coefficient computation (`sin`, `cos`, `powf`) must not happen in `eq10_processf`. They belong in `eq10_bsetup` called from `manzo_set_eq` on the caller thread (D-02). Violation causes audio glitches from CPU spikes.
- **Nested NSVisualEffectView:** Unrelated to this phase, but documented in CLAUDE.md — do not touch UI layers.
- **Forgetting the cascade:** After each EQ band's loop, the next band reads the same buffer (output of prior band). In the in-place port, this is automatic since `buf == outbuf`. Do not re-initialize `in` from `buf` between bands.
- **int16 anywhere:** The existing pipeline is float32 end-to-end. Do not introduce any int16 intermediate (CLAUDE.md: "Float32 pipeline end-to-end").
- **Separate input/output buffers:** The original `eq10_processf` supports `buf != outbuf`, but the Rust port is in-place (`buf == outbuf`). The limiter path `else if (in==buf)&&(buf!=outbuf)` (the copy-only path) does not apply in-place — the in-place port skips this branch entirely.
- **Mutex held during EQ processing:** Per the existing WR-03 comment in `lib.rs`, the mutex is held for the whole callback. Phase 4 does not need to fix this — that refactor is deferred to Phase 5. Do not attempt to restructure locking in Phase 4.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Biquad IIR coefficients | Custom filter math | Port `eq10_bsetup`/`eq10_bsetup2` verbatim | The dual Q-factor trick (Q×2 for boost, Q×0.5 for cut) is specific to this EQ; wrong Q = wrong frequency response |
| Dynamic limiter | Static gain ceiling | Port `eq10_processf` limiter block verbatim | The peak-detector with exponential decay matches Winamp's audible behavior exactly |
| Denormal prevention | Flush-to-zero CPU flag | Keep `+ 1e-30_f64` in the sample loop | FTZ is global CPU state; the additive constant is local and portable |
| Gain representation | dB-direct storage | Use `eq10_db2gain` shifted-linear form | The gain sign selects which coefficient set (ua0 vs da0) — this is structurally load-bearing |

**Key insight:** The EQ math is correct as shipped. The goal is a faithful port, not a redesign. Any deviation from the original arithmetic risks frequency response errors that are audible but hard to diagnose.

---

## Common Pitfalls

### Pitfall 1: Limiter `in` Pointer After Band Loop

**What goes wrong:** In the C code, after the 10-band loop, `in` points to `outbuf` (the last `in = outbuf` assignment inside the band loop). The limiter then reads from `in` (= outbuf). In an in-place Rust port (buf == outbuf), this is automatic — the limiter simply reads from the same buffer. But if someone accidentally re-initializes `in` to `buf` between the band loop and limiter, the limiter reads unprocessed input instead of EQ output.

**Why it happens:** Misreading the C pointer aliasing when translating to Rust slice indexing.

**How to avoid:** In the Rust port, the EQ writes in-place to `buf`. After the band loop, the limiter reads from the same `buf` — no pointer reset needed. The frame index `idx + t * step` is identical for the EQ loop and the limiter loop.

**Warning signs:** Limiter appears to have no effect when EQ gain is applied; output sounds like unprocessed EQ.

### Pitfall 2: `a0 == 0.0` Skip With Zero Gain

**What goes wrong:** `eq10_db2gain(0.0) = pow(10, 0) - 1 = 0.0`. When all bands are at 0 dB (default), every band's gain = 0.0. Then `a0 = ua0 * gain = 0.0` → the `if a0 == 0.0 { continue; }` branch skips ALL bands. This means at flat EQ, the EQ path is a no-op, which is correct and intentional. But if the port omits the `a0 == 0.0` check, it wastes ~10× CPU on the flat case.

**Why it happens:** Overlooking the optimization.

**How to avoid:** Port the `if a0 == 0.0 { continue; }` check verbatim. This is both a correctness detail (skipping avoids accumulated floating-point drift on the 0-gain path) and a performance detail.

### Pitfall 3: Gain Sign Selects Coefficient Set

**What goes wrong:** The biquad uses `gain > 0.0` to pick boost coefficients (`ua0/ub1/ub2`) vs. cut coefficients (`da0/db1/db2`). If the comparison is `>= 0.0` instead of `> 0.0`, a 0 dB gain would use boost coefficients with gain=0 → `a0 = ua0 * 0 = 0`, which is fine numerically but subtly incorrect branch-wise. More critically, if the comparison direction is flipped, boosts become cuts and vice versa.

**Why it happens:** Off-by-one threshold or wrong comparison operator.

**How to avoid:** Port `if gain > 0.0` exactly. Verify with a +6 dB test that frequencies are boosted (not attenuated).

### Pitfall 4: detectdecay Not Computed Per Channel

**What goes wrong:** `eq->detectdecay = pow(0.001, 1.0/(rate * EQ10_TRIM_RELEASE))` is computed once in `eq10_setup` per channel instance. If the Rust `Eq10State` is initialized without calling the equivalent of `eq10_setup`, `detectdecay` defaults to 0.0 → the limiter's `detect *= 0.0` → detect drops to zero every sample → limiter never activates → potential clipping on boosted signals.

**Why it happens:** Forgetting to initialize `detectdecay` when constructing `Eq10State`.

**How to avoid:** The `Eq10State::new(rate: f64)` constructor (equivalent of `eq10_setup`) must compute `detectdecay = 0.001_f64.powf(1.0 / (rate * 0.700))` and set all band coefficients via `eq10_bsetup`. Never use `Eq10State::default()` or zero-initialize.

### Pitfall 5: Buffer Frame Count vs. Sample Count

**What goes wrong:** `eq10_processf` takes `sz` = number of **frames** (time steps), not samples. For stereo interleaved, 1 frame = 2 samples. The cpal callback provides `data.len()` = total samples = `num_frames * 2`. Passing `data.len()` as `sz` causes the inner loop to run twice as long, writing past the allocated buffer.

**Why it happens:** Confusion between "samples" and "frames" in the API.

**How to avoid:** `let num_frames = data.len() / s.channels as usize;` then pass `num_frames` as `sz` to `eq10_processf`. This is the same calculation already used in the Phase 2/3 callback (`position_samples += frames_written / channels`).

### Pitfall 6: Preamp Gain Representation

**What goes wrong:** Storing preamp as dB in InnerState and re-converting per-sample. `powf` in the hot path = ~100 ns overhead = measurable at 44.1 kHz.

**Why it happens:** Forgetting to pre-convert when the stub stores dB values.

**How to avoid:** In `manzo_set_eq`, convert preamp dB to linear scalar before storing: `state.preamp_gain_linear = 10_f32.powf(preamp_db / 20.0)`. The audio callback multiplies by the pre-converted linear value.

---

## Code Examples

### Initializing Eq10State (eq10_setup equivalent)

```rust
// Source: eq10dsp.cpp eq10_setup + eq10_bsetup (verified from source 2026-04-22)
impl Eq10State {
    pub(crate) fn new(rate: f64) -> Self {
        // Winamp frequency table (EQ_FREQUENCIES_WINAMP, hardcoded for v1)
        const FREQS: [f64; 10] = [70.0, 180.0, 320.0, 600.0, 1000.0, 3000.0, 6000.0, 12000.0, 14000.0, 16000.0];
        const Q: f64 = 1.41; // EQ10_Q

        let mut state = Eq10State {
            rate,
            band: std::array::from_fn(|_| Eq10Band::default()),
            detect: 0.0,
            detectdecay: 0.001_f64.powf(1.0 / (rate * 0.700)),
        };
        for (i, band) in state.band.iter_mut().enumerate() {
            eq10_bsetup(rate, band, FREQS[i], Q);
        }
        state
    }
}
```

### Wiring Into the cpal Callback

```rust
// Inside the cpal callback, after 529-sample skip, before cpal output write:
// (s = MutexGuard<InnerState>)

// 1. Preamp (linear scalar, pre-converted in manzo_set_eq)
for sample in data.iter_mut() {
    *sample *= s.preamp_gain_linear;
}

let num_frames = data.len() / 2; // stereo: 2 channels

// 2. EQ — left channel (idx=0, step=2)
eq10_processf(&mut s.eq_l, data, num_frames, 0, 2, s.config_eq_limiter);

// 3. EQ — right channel (idx=1, step=2)
eq10_processf(&mut s.eq_r, data, num_frames, 1, 2, s.config_eq_limiter);

// 4. Volume/pan ramp (per-frame, after EQ+limiter)
apply_vol_pan_ramp(&mut s, data, num_frames);
```

### Performance Integration Test (D-07)

```rust
// Source: CONTEXT.md D-07; mirrors Winamp TESTCASE loop with timing gate
// Location: manzo-core/tests/integration_test.rs (add alongside existing tests)
#[test]
fn eq_perf_under_100us() {
    use std::time::Instant;
    use manzo_core::eq10::{Eq10State, eq10_processf};

    let mut eq_l = Eq10State::new(44100.0);
    let mut eq_r = Eq10State::new(44100.0);
    // Set all bands to max boost to exercise the hot path (not the a0==0 skip)
    for band in eq_l.band.iter_mut().chain(eq_r.band.iter_mut()) {
        band.gain = manzo_core::eq10::eq10_db2gain(12.0);
    }

    let mut buf = vec![0.5_f32; 1024 * 2]; // 1024 frames × 2 channels interleaved
    let mut max_elapsed_us = 0u128;

    for _ in 0..1000 {
        let t0 = Instant::now();
        eq10_processf(&mut eq_l, &mut buf, 1024, 0, 2, true);
        eq10_processf(&mut eq_r, &mut buf, 1024, 1, 2, true);
        let elapsed_us = t0.elapsed().as_micros();
        if elapsed_us > max_elapsed_us { max_elapsed_us = elapsed_us; }
    }

    assert!(
        max_elapsed_us < 100,
        "EQ processing exceeded 100 µs: worst case was {} µs over 1000 iterations",
        max_elapsed_us
    );
}
```

---

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| Winamp: int16→float→EQ→float→int16 | Phase 4 Rust: float32 end-to-end | No precision loss; fewer copies (already decided Phase 2) |
| Winamp: C double for filter state | Rust port: f64 for filter state | Identical numeric behavior |
| Winamp: static global `config_eq_limiter` | Rust port: `InnerState.config_eq_limiter: bool` | Enables per-handle control; default `true` |

**Deprecated/outdated:**
- `EQ10_DETECTOR_CODE` per-band level detection: commented out in all shipped Winamp binaries. Do not port.

---

## Runtime State Inventory

This phase is not a rename/refactor/migration. No runtime state changes are required.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — Phase 4 adds fields only to in-process `InnerState`; no database or persistent store | None |
| Live service config | None | None |
| OS-registered state | None | None |
| Secrets/env vars | None | None |
| Build artifacts | None — no package rename; `manzo-core` crate name unchanged | None |

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Rust toolchain | Cargo build | Yes | rustc 1.95.0 (2026-04-14) | — |
| Cargo | Build + test | Yes | 1.95.0 (2026-03-21) | — |
| `std::f64` math | `eq10_bsetup` (sin/cos/powf) | Yes | stdlib | — |
| `Instant::now()` | Performance test (D-07) | Yes | stdlib | — |
| cpal audio hardware | `#[ignore]` tests only | Per-machine | — | Tests marked `#[ignore]` for headless CI |

**Missing dependencies:** None. All required capabilities are in Rust std.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Rust built-in test (`cargo test`) |
| Config file | None — uses Cargo defaults |
| Quick run command | `cargo test --manifest-path manzo-core/Cargo.toml` |
| Full suite command | `cargo test --manifest-path manzo-core/Cargo.toml -- --include-ignored` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DSP-01 | 10-band biquad processes audio (coefficient correctness) | unit | `cargo test --lib eq10` | ❌ Wave 0 (eq10.rs module) |
| DSP-01 | 10-band biquad processes audio (performance gate) | integration | `cargo test --test integration_test eq_perf_under_100us` | ❌ Wave 0 |
| DSP-02 | EQ band change takes effect next buffer, no dropout | integration (manual) | Covered by perf test + manual listen | ❌ Wave 0 |
| DSP-03 | Preamp gain adjusts level before biquad chain | unit | `cargo test --lib preamp` | ❌ Wave 0 |
| DSP-04 | Volume/pan changes ramped; audibly immediate | unit + manual | `cargo test --lib vol_pan` | ❌ Wave 0 |

### Wave 0 Gaps

- [ ] `manzo-core/src/eq10.rs` — `Eq10Band`, `Eq10State`, all port functions
- [ ] Unit tests for `eq10_db2gain`, `eq10_bsetup` coefficient sanity (non-zero coefficients for in-range freq/Q)
- [ ] Unit tests for preamp linear conversion
- [ ] Unit tests for vol/pan ramp logic (ramp reaches target after 441 samples)
- [ ] Integration test `eq_perf_under_100us` in `manzo-core/tests/integration_test.rs`

### Sampling Rate

- **Per task commit:** `cargo test --manifest-path manzo-core/Cargo.toml`
- **Per wave merge:** `cargo test --manifest-path manzo-core/Cargo.toml`
- **Phase gate:** Full suite green before `/gsd-verify-work`

---

## Security Domain

`security_enforcement` is not explicitly set to `false` in `.planning/config.json`. Applying standard check.

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | N/A — no auth in DSP layer |
| V3 Session Management | No | N/A |
| V4 Access Control | No | N/A |
| V5 Input Validation | Yes | Gain clamped to ±12 dB in existing `manzo_set_eq` stub; preamp clamped ±12 dB; volume clamped 0–1; pan clamped –1–1 |
| V6 Cryptography | No | N/A |

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| NaN/Inf propagation from unclamped gain | Tampering | Existing `clamp(-12.0, 12.0)` in stubs; `eq10_db2gain(12.0) ≈ 2.98` — finite |
| Unsafe pointer in FFI (`gains: *const f32`) | Tampering | Existing null guard + `from_raw_parts` with caller-guaranteed length; no change needed |
| Denormal float stall | Denial of Service | `+ 1e-30_f64` additive fix in sample loop; matches original |

---

## Open Questions

1. **`config_eq_limiter` as runtime field vs. compile-time constant**
   - What we know: CONTEXT.md defers this to Claude's discretion. The original C uses a global variable.
   - What's unclear: Whether Phase 5+ needs to toggle the limiter on/off per-session via FFI.
   - Recommendation: Use a `bool` field in `InnerState` defaulting to `true`. Cost is one branch per buffer; benefit is runtime-toggleable for debugging.

2. **In-place vs. separate output buffer**
   - What we know: The original supports `buf != outbuf`, but the Rust callback uses a single cpal output buffer.
   - What's unclear: Whether any future phase needs separate in/out buffers.
   - Recommendation: Port as in-place (`buf == outbuf`) for Phase 4. Add a note that the API could be extended to separate buffers later.

3. **Pan law: linear vs. constant-power**
   - What we know: Winamp's original pan is implemented in the output plugin (`SetPan(0–255)`), not in the EQ chain. The exact pan law is not in `eq10dsp.cpp`.
   - What's unclear: Whether the user expects constant-power (−3 dB at center-when-panned) or linear split.
   - Recommendation: Use linear split for Phase 4 (simpler; audibly acceptable). Constant-power is a Phase 5+ enhancement.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Pan law: use linear `(1-pan)/(1+pan)` gain split | Pattern 5 | Audible −3 dB center loss if constant-power expected; fixable in Phase 5 without API change |
| A2 | `config_eq_limiter` as `bool` in `InnerState` (not compile-time) | Architecture | No functional risk; only adds one branch per buffer |
| A3 | Per-channel `Eq10State` (eq_l, eq_r) stored directly in `InnerState` (not a sub-struct) | Standard Stack | Struct layout only; no behavioral risk |

---

## Sources

### Primary (HIGH confidence)
- `winamp/Src/Winamp/eq10dsp.cpp` — Read directly 2026-04-22. All function bodies, limiter logic, denormal fix, band loop structure.
- `winamp/Src/Winamp/eq10dsp.h` — Read directly 2026-04-22. `eq10_t`, `eq10band_t`, all constants.
- `winamp/Src/Winamp/In.cpp` lines 1224–1236 — Read directly 2026-04-22. `VALTODB` reference implementation (deferred to Phase 8).
- `manzo-core/src/lib.rs` — Read directly 2026-04-22. InnerState fields, existing stubs, cpal callback structure.
- `manzo-core/tests/integration_test.rs` — Read directly 2026-04-22. Existing test patterns and fixtures.
- `.planning/phases/04-dsp-engine/04-CONTEXT.md` — Read directly 2026-04-22. All locked decisions D-01 through D-07.

### Secondary (MEDIUM confidence)
- `.claude/skills/spike-findings-MANZO/references/audio-dsp-pipeline.md` — Spike synthesis; used to cross-check signal chain. Noted correction: VALTODB sign is `raw=0 → +12 dB` (confirmed from In.cpp source).

### Tertiary (LOW confidence / ASSUMED)
- None in this research. All architectural claims verified against source files.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — verified in Cargo.toml and toolchain; no new deps
- Architecture: HIGH — derived from reading source files directly
- Pitfalls: HIGH — identified from reading eq10dsp.cpp pointer aliasing and data-flow
- Performance claim (<100 µs): MEDIUM — based on algorithmic complexity (10 bands × 1024 frames × ~5 ops/sample at ~3 GHz); not yet profiled on target hardware

**Research date:** 2026-04-22
**Valid until:** 2026-06-01 (algorithm is stable; Rust toolchain update irrelevant for this work)

---

## Project Constraints (from CLAUDE.md)

| Directive | Status in Phase 4 |
|-----------|-------------------|
| Apple Silicon only (aarch64-apple-darwin) | No change — existing Cargo.toml config |
| Float32 pipeline end-to-end — no int16 conversion | Enforced: all sample I/O is f32; internal filter state is f64 only |
| FFI surface: exactly 11 `manzo_*` functions | No new FFI functions in Phase 4 (CONTEXT.md confirmed) |
| P3 colors everywhere | Not applicable — no UI in Phase 4 |
| One `.behindWindow` NSVisualEffectView at root | Not applicable — no UI in Phase 4 |
| `shouldRasterize = true` requires `rasterizationScale = 2.0` | Not applicable — no UI in Phase 4 |
| MP3 gapless: trim exactly 529 samples | Already implemented; Phase 4 does not touch startup skip |
| `cbindgen` auto-generates C header | No new FFI = no header change needed; cbindgen runs unchanged |
