# Phase 4: DSP Engine - Pattern Map

**Mapped:** 2026-04-22
**Files analyzed:** 3 (1 new module, 1 modified, 1 new integration test file)
**Analogs found:** 3 / 3

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `manzo-core/src/eq10.rs` | DSP module (service) | streaming / transform | `winamp/Src/Winamp/eq10dsp.cpp` (source port) + `manzo-core/src/lib.rs` struct patterns | exact (direct port) |
| `manzo-core/src/lib.rs` | FFI service + audio callback | streaming / event-driven | `manzo-core/src/lib.rs` existing (modify in place) | self-analog (extend) |
| `manzo-core/tests/integration_test.rs` | integration test | batch / transform | `manzo-core/tests/integration_test.rs` existing (add alongside) | role-match |

---

## Pattern Assignments

### `manzo-core/src/eq10.rs` (DSP module, transform)

**Analog:** Direct port of `winamp/Src/Winamp/eq10dsp.cpp` + `eq10dsp.h` (read 2026-04-22).
Struct layout follows patterns from `manzo-core/src/lib.rs` `InnerState`.

**Module declaration pattern** — add to `manzo-core/src/lib.rs` line 8 (after existing `use` block):
```rust
mod eq10;
use eq10::{Eq10State, eq10_processf};
```

**Struct layout pattern** — `eq10dsp.h` lines 53–84, translated to Rust:

All fields are `f64` to match the original's `double` precision.
`EQ10_DETECTOR_CODE` is NOT defined in the shipped binary — omit per-band `detect`/`detectdecay`.

```rust
// manzo-core/src/eq10.rs — full struct declarations
// Source: winamp/Src/Winamp/eq10dsp.h lines 53-84

pub(crate) struct Eq10Band {
    pub gain:  f64,          // shifted-linear; 0.0 == 0 dB (eq10_db2gain)
    pub ua0: f64, pub ub1: f64, pub ub2: f64,  // boost coefficients (Q*2)
    pub da0: f64, pub db1: f64, pub db2: f64,  // cut coefficients  (Q*0.5)
    pub x1: f64, pub x2: f64,                  // input delay line
    pub y1: f64, pub y2: f64,                  // output delay line
}

pub(crate) struct Eq10State {
    pub rate: f64,
    pub band: [Eq10Band; 10],
    pub detect:      f64,   // global limiter peak tracker
    pub detectdecay: f64,   // pow(0.001, 1/(rate * 0.700)) — computed in ::new()
}
```

**Constructor / eq10_setup pattern** — `eq10dsp.cpp` lines 79–96:

```rust
// manzo-core/src/eq10.rs — Eq10State::new()
// Source: eq10dsp.cpp eq10_setup (lines 79-96) + eq10_bsetup (lines 68-77)
// Winamp frequency table hardcoded for v1 (config_eq_frequencies == EQ_FREQUENCIES_WINAMP)
const FREQS: [f64; 10] = [70.0, 180.0, 320.0, 600.0, 1000.0,
                           3000.0, 6000.0, 12000.0, 14000.0, 16000.0];
const Q: f64 = 1.41; // EQ10_Q from eq10dsp.h line 42

impl Eq10State {
    pub(crate) fn new(rate: f64) -> Self {
        let mut state = Eq10State {
            rate,
            band: std::array::from_fn(|_| Eq10Band {
                gain: 0.0,
                ua0: 0.0, ub1: 0.0, ub2: 0.0,
                da0: 0.0, db1: 0.0, db2: 0.0,
                x1: 0.0, x2: 0.0, y1: 0.0, y2: 0.0,
            }),
            detect: 0.0,
            detectdecay: 0.001_f64.powf(1.0 / (rate * 0.700)),  // EQ10_TRIM_RELEASE=0.700
        };
        for (i, band) in state.band.iter_mut().enumerate() {
            eq10_bsetup(rate, band, FREQS[i], Q);
        }
        state
    }
}
```

**eq10_bsetup / eq10_bsetup2 pattern** — `eq10dsp.cpp` lines 36–77:

Note: original calls `eq10_bsetup2(-1, ...)` for cut (Q*0.5) then `eq10_bsetup2(1, ...)` for boost (Q*2).
The `u>0` branch sets `ua0/ub1/ub2`; the `u<=0` branch sets `da0/db1/db2`.
Line 44: `if freq >= rate*0.499` sets both `ua0=da0=0` and returns — guards Nyquist.

```rust
// manzo-core/src/eq10.rs — coefficient setup
// Source: eq10dsp.cpp lines 36-77

fn eq10_bsetup2(boost: bool, rate: f64, band: &mut Eq10Band, freq: f64, q: f64) {
    let rate = rate.clamp(4000.0, 384000.0);
    let freq = freq.max(20.0);
    if freq >= rate * 0.499 {
        // Nyquist guard — zero both sets on boundary (matches C line 44: ua0=da0=0)
        band.ua0 = 0.0; band.da0 = 0.0;
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

pub(crate) fn eq10_bsetup(rate: f64, band: &mut Eq10Band, freq: f64, q: f64) {
    // Reset delay lines and coefficients (matches C memset, lines 70-71)
    *band = Eq10Band { gain: 0.0, ua0: 0.0, ub1: 0.0, ub2: 0.0,
                       da0: 0.0, db1: 0.0, db2: 0.0,
                       x1: 0.0, x2: 0.0, y1: 0.0, y2: 0.0 };
    eq10_bsetup2(false, rate, band, freq, q * 0.5);  // cut: Q*0.5
    eq10_bsetup2(true,  rate, band, freq, q * 2.0);  // boost: Q*2
}
```

**eq10_db2gain pattern** — `eq10dsp.cpp` lines 208–211:

```rust
// manzo-core/src/eq10.rs
// Source: eq10dsp.cpp lines 208-211
pub(crate) fn eq10_db2gain(gain_db: f64) -> f64 {
    10.0_f64.powf(gain_db / 20.0) - 1.0
    // 0 dB → 0.0; +12 dB → ≈2.981; -12 dB → ≈-0.749
}
```

**eq10_processf core loop pattern** — `eq10dsp.cpp` lines 98–206:

Critical details from the source:
- Line 104–105: `buf += idx; outbuf += idx;` — pointer advance by channel index before loop
- Line 108: `in = buf;` — after advance, `in` starts at the channel-offset position
- Line 141: `for(t=0;t<sz;t++,in+=step,out+=step)` — step = 2 for stereo; `sz` = FRAMES not samples
- Line 160: `x2=x1; x1=in[0]; y2=y1; y1=y0;` — update state AFTER using `in[0]` as `x`
- Line 162: `out[0] = (float)(y0 + in[0]);` — peaking EQ: add filtered delta to input
- Line 165: `in = outbuf;` — cascade: next band reads previous band's output (in-place: same slice)
- Line 139: `if (a0==0.0) continue;` — skip band when gain=0.0 (both correctness and perf)
- Line 177: limiter reads from `in` (which equals `outbuf` after band loop, line 165)
- Lines 200–204: copy-only else-if branch (`in==buf && buf!=outbuf`) — does NOT apply in-place; skip this branch entirely in the Rust port

```rust
// manzo-core/src/eq10.rs — hot-path function
// Source: eq10dsp.cpp lines 98-206
// In-place port: buf == outbuf (same interleaved slice).
// sz = number of FRAMES (not samples); idx=0(L) or 1(R); step=2(stereo).
pub(crate) fn eq10_processf(
    eq: &mut Eq10State,
    buf: &mut [f32],
    sz: usize,
    idx: usize,
    step: usize,
    config_eq_limiter: bool,
) {
    // 10-band cascade (source lines 109-175)
    for k in 0..10 {
        let band = &mut eq.band[k];
        let gain = band.gain;
        let (a0, b1, b2) = if gain > 0.0 {
            (band.ua0 * gain, band.ub1, band.ub2)   // boost coefficients
        } else {
            (band.da0 * gain, band.db1, band.db2)   // cut coefficients
        };
        if a0 == 0.0 { continue; }  // source line 139 — skip flat band

        let mut x1 = band.x1; let mut x2 = band.x2;
        let mut y1 = band.y1; let mut y2 = band.y2;
        for t in 0..sz {
            let i = idx + t * step;
            let x = buf[i] as f64;
            let y0 = (x - x2) * a0 + y1 * b1 + y2 * b2 + 1e-30_f64; // DENORMAL_FIX
            x2 = x1; x1 = x; y2 = y1; y1 = y0;
            buf[i] = (y0 + x) as f32;   // peaking: filtered delta added to input
        }
        band.x1 = x1; band.x2 = x2; band.y1 = y1; band.y2 = y2;
        // in-place: next band reads buf — cascade is automatic, no pointer reset needed
    }

    // Dynamic limiter (source lines 177-199; EQ10_TRIM_CODE=0.930, EQ10_TRIM_RELEASE=0.700)
    // Note: the copy-only else-if (source lines 200-204) is omitted — in-place port.
    if config_eq_limiter {
        let mut detect = eq.detect;
        let detectdecay = eq.detectdecay;
        for t in 0..sz {
            let i = idx + t * step;
            let s = buf[i] as f64;
            let abs_s = s.abs();
            if abs_s > detect { detect = abs_s; }
            buf[i] = if detect > 0.930 {
                (s * (0.930 / detect)) as f32
            } else {
                s as f32
            };
            detect *= detectdecay;
            detect += 1e-30_f64; // DENORMAL_FIX
        }
        eq.detect = detect;
    }
}
```

---

### `manzo-core/src/lib.rs` (FFI service + audio callback, modify in place)

**Analog:** Self-analog — extend `manzo-core/src/lib.rs` existing code.

**InnerState extension pattern** — current `InnerState` definition starts at line 20.
Add after existing `eq_gains`/`eq_preamp` fields (currently lines 32–33).
Replace the Phase 4 placeholder comment at line 29 with real fields:

```rust
// manzo-core/src/lib.rs — InnerState additions (Phase 4)
// Source: CONTEXT.md D-03, D-05; RESEARCH.md Pattern 5; manzo-core/src/lib.rs lines 20-47

struct InnerState {
    // ... all existing fields unchanged (lines 20-47) ...

    // Phase 4 DSP: replace existing volume/pan/eq_gains/eq_preamp fields with:
    volume: f32,          // kept as-is (was already present)
    pan: f32,             // kept as-is
    eq_gains: [f32; 10],  // kept (clamped dB, source of truth for manzo_set_eq)
    eq_preamp: f32,       // kept (clamped dB, source of truth for manzo_set_eq)

    // NEW Phase 4 fields:
    preamp_gain_linear: f32,    // pre-converted: 10^(eq_preamp/20); avoids powf in hot path
    eq_l: Eq10State,            // left-channel biquad state (one instance per D-06)
    eq_r: Eq10State,            // right-channel biquad state
    config_eq_limiter: bool,    // dynamic limiter toggle; default true (D-04)
    target_volume: f32,         // ramp destination (written by manzo_set_volume)
    current_volume: f32,        // ramp current value (audio thread advances toward target)
    vol_ramp_remaining: u32,    // frames left in volume ramp; 0 = at target
    target_pan: f32,            // ramp destination (written by manzo_set_pan)
    current_pan: f32,           // ramp current value
    pan_ramp_remaining: u32,    // frames left in pan ramp; 0 = at target
}
```

**InnerState initializer pattern** — `manzo_open` creates `InnerState` at line 165:

```rust
// manzo-core/src/lib.rs — InnerState { ... } literal in manzo_open (line 165)
// Add new fields after existing field initializers:
let inner = InnerState {
    // ... all existing fields unchanged ...
    preamp_gain_linear: 1.0_f32,           // 0 dB = unity gain
    eq_l: Eq10State::new(44100.0),         // initialized at 44.1 kHz; updated if sample_rate differs
    eq_r: Eq10State::new(44100.0),
    config_eq_limiter: true,               // enabled by default (D-04)
    target_volume: 1.0,
    current_volume: 1.0,
    vol_ramp_remaining: 0,
    target_pan: 0.0,
    current_pan: 0.0,
    pan_ramp_remaining: 0,
};
```

**manzo_set_eq body replacement pattern** — current stub at lines 490–513:

Replace the body between the existing mutex lock and the closing brace (after line 511):

```rust
// manzo-core/src/lib.rs — manzo_set_eq Phase 4 body
// Source: CONTEXT.md D-02, D-05; RESEARCH.md Pitfall 6
// Existing null guard + mutex lock at lines 496-503 remain unchanged.
// Replace only the loop body and trailing comment at lines 508-513 with:

for (i, (&src_db, dst)) in gain_slice.iter()
    .zip(state.eq_gains.iter_mut())
    .enumerate()
{
    let clamped_db = src_db.clamp(-12.0_f32, 12.0_f32);
    *dst = clamped_db;
    let gain_linear = eq10::eq10_db2gain(clamped_db as f64);
    state.eq_l.band[i].gain = gain_linear;
    state.eq_r.band[i].gain = gain_linear;
}
state.eq_preamp = preamp.clamp(-12.0_f32, 12.0_f32);
// Pre-convert preamp to linear scalar — avoids powf in the audio callback hot path (Pitfall 6)
state.preamp_gain_linear = 10_f32.powf(state.eq_preamp / 20.0);
```

**manzo_set_volume body replacement pattern** — current stub at lines 517–526:

```rust
// manzo-core/src/lib.rs — manzo_set_volume Phase 4 body
// Source: CONTEXT.md D-03; RESEARCH.md Pattern 5
// Existing null guard + mutex lock remain unchanged.
state.target_volume = volume.clamp(0.0_f32, 1.0_f32);
state.vol_ramp_remaining = 441;  // ~10 ms at 44.1 kHz (D-03)
```

**manzo_set_pan body replacement pattern** — current stub at lines 530–539:

```rust
// manzo-core/src/lib.rs — manzo_set_pan Phase 4 body
// Source: CONTEXT.md D-03; RESEARCH.md Pattern 5
// Existing null guard + mutex lock remain unchanged.
state.target_pan = pan.clamp(-1.0_f32, 1.0_f32);
state.pan_ramp_remaining = 441;  // ~10 ms at 44.1 kHz (D-03)
```

**DSP chain insertion pattern** — audio callback in `manzo_play`, after line 307 (after the startup-skip block ends and before `let mut done`):

The insertion point is inside the `while written < data.len()` loop, immediately after startup-skip has drained. The chain processes the entire decoded slice once per callback invocation, not inside the per-chunk `while` loop. The correct insertion point is after `written` fills to `data.len()` — i.e., after the decode loop completes and before the callback returns.

```rust
// manzo-core/src/lib.rs — DSP chain wired into cpal callback
// Source: RESEARCH.md "Wiring Into the cpal Callback"; CONTEXT.md D-01; eq10dsp.cpp
// Insert after the decode while-loop exits (after the data[written..].fill(0.0) EOF branch),
// before the callback closure ends. Operates on the fully-decoded `data` slice.

// 1. Preamp — scalar multiply on entire interleaved buffer (RESEARCH.md Pattern 4)
let preamp = s.preamp_gain_linear;
if preamp != 1.0_f32 {
    for sample in data.iter_mut() {
        *sample *= preamp;
    }
}

// 2. EQ — per-channel biquad cascade + dynamic limiter (D-06: called twice)
let num_frames = data.len() / s.channels as usize;  // frames, not samples (Pitfall 5)
eq10_processf(&mut s.eq_l, data, num_frames, 0, 2, s.config_eq_limiter);  // L
eq10_processf(&mut s.eq_r, data, num_frames, 1, 2, s.config_eq_limiter);  // R

// 3. Volume/pan linear ramp (D-03; RESEARCH.md Pattern 5)
for frame in 0..num_frames {
    // Advance volume ramp
    if s.vol_ramp_remaining > 0 {
        let step = (s.target_volume - s.current_volume) / s.vol_ramp_remaining as f32;
        s.current_volume += step;
        s.vol_ramp_remaining -= 1;
    } else {
        s.current_volume = s.target_volume;
    }
    // Advance pan ramp
    if s.pan_ramp_remaining > 0 {
        let step = (s.target_pan - s.current_pan) / s.pan_ramp_remaining as f32;
        s.current_pan += step;
        s.pan_ramp_remaining -= 1;
    } else {
        s.current_pan = s.target_pan;
    }
    // Linear pan law: L_gain=(1-pan).clamp(0,1), R_gain=(1+pan).clamp(0,1) (Assumption A1)
    let l_gain = (1.0 - s.current_pan).clamp(0.0, 1.0);
    let r_gain = (1.0 + s.current_pan).clamp(0.0, 1.0);
    let l = frame * 2;
    let r = frame * 2 + 1;
    data[l] *= s.current_volume * l_gain;
    data[r] *= s.current_volume * r_gain;
}
```

---

### `manzo-core/tests/integration_test.rs` (integration test, add alongside existing)

**Analog:** `manzo-core/tests/integration_test.rs` (existing tests, read 2026-04-22).

**File-level import pattern** — existing file lines 10–19 use `use manzo_core::{...}` and `std::ffi::CString`. The new test uses the `eq10` module directly:

```rust
// manzo-core/tests/integration_test.rs — imports to ADD at top of existing file
// Source: integration_test.rs lines 10-15 (existing pattern) + RESEARCH.md D-07
use manzo_core::eq10::{Eq10State, eq10_processf, eq10_db2gain};
use std::time::Instant;
```

**Performance test pattern** — new test function to append at the end of the existing file:

```rust
// manzo-core/tests/integration_test.rs — append after line 221
// Source: CONTEXT.md D-07; RESEARCH.md "Performance Integration Test"
// Mirrors eq10dsp.cpp TESTCASE block (lines 248-275) with a timing gate.
// NOT marked #[ignore] — this must run in CI (no hardware required).
#[test]
fn eq_perf_under_100us() {
    let mut eq_l = Eq10State::new(44100.0);
    let mut eq_r = Eq10State::new(44100.0);
    // Set all bands to max boost to exercise the 10-band hot path (not the a0==0 skip).
    // Pitfall 2: at 0 dB all bands skip — this test must use non-zero gain.
    for band in eq_l.band.iter_mut().chain(eq_r.band.iter_mut()) {
        band.gain = eq10_db2gain(12.0);
    }

    let mut buf = vec![0.5_f32; 1024 * 2]; // 1024 frames × 2 channels, interleaved
    let mut max_elapsed_us = 0u128;

    for _ in 0..1000 {
        let t0 = Instant::now();
        eq10_processf(&mut eq_l, &mut buf, 1024, 0, 2, true);  // L channel
        eq10_processf(&mut eq_r, &mut buf, 1024, 1, 2, true);  // R channel
        let elapsed_us = t0.elapsed().as_micros();
        if elapsed_us > max_elapsed_us { max_elapsed_us = elapsed_us; }
    }

    assert!(
        max_elapsed_us < 100,
        "EQ processing exceeded 100 µs budget: worst case {} µs over 1000 iterations \
         (DSP-01 performance requirement, D-07)",
        max_elapsed_us
    );
}
```

**Existing test structure to follow** (lines 25–35 pattern for non-hardware tests):

```rust
// Pattern: non-hardware tests have no #[ignore].
// Pattern: hardware tests (play_advances_position, state_transitions_...) carry:
//   #[ignore = "requires audio output hardware; not available in headless CI environments"]
// The eq_perf_under_100us test requires NO hardware — no #[ignore].
// The FIXTURE_PATH const pattern (line 19) is used for existing open/close tests;
// the new perf test constructs Eq10State directly without opening a file.
```

---

## Shared Patterns

### Arc<Mutex<InnerState>> Threading Model
**Source:** `manzo-core/src/lib.rs` lines 251–254 (callback lock), lines 502–503 (FFI lock)
**Apply to:** `manzo_set_eq`, `manzo_set_volume`, `manzo_set_pan` body replacements and the cpal callback DSP insertion.

```rust
// FFI functions — existing pattern, lines 502-503
let arc = unsafe { &*(handle as *mut Arc<Mutex<InnerState>>) };
let mut state = arc.lock().unwrap_or_else(|e| e.into_inner());

// Callback — existing pattern, lines 251-254
let mut s = match inner_clone.lock() {
    Ok(s) => s,
    Err(e) => e.into_inner(),
};
```

**WR-03 note** (`lib.rs` line 244–251 comment): The mutex is held for the ENTIRE callback including the new DSP chain. Phase 4 does NOT restructure locking — that refactor is deferred to Phase 5. Do not attempt to drop and re-acquire the mutex around the DSP block.

### Null Guard + Return Pattern
**Source:** `manzo-core/src/lib.rs` lines 496–501 (in `manzo_set_eq`)
**Apply to:** All three stub replacements (`manzo_set_eq`, `manzo_set_volume`, `manzo_set_pan`).

```rust
// Pattern used by every FFI function in lib.rs:
if handle.is_null() { return; }
if gains.is_null() { return; }  // only where pointer args exist
let arc = unsafe { &*(handle as *mut Arc<Mutex<InnerState>>) };
let mut state = arc.lock().unwrap_or_else(|e| e.into_inner());
```

### FFI Return Code Convention
**Source:** `manzo-core/src/lib.rs` lines 203, 370–374
**Apply to:** Phase 4 adds no new FFI functions, so this pattern applies only as a reminder for any helper function that returns i32.
- `0` = success
- `-1` = error / null handle
- No panics in `extern "C"` functions — they must catch/handle all errors

### Input Clamping Pattern
**Source:** `manzo-core/src/lib.rs` lines 507–511
**Apply to:** All DSP parameter updates in `manzo_set_eq`, `manzo_set_volume`, `manzo_set_pan`.

```rust
// Existing pattern — clamp before storing to prevent NaN/Inf in DSP chain
src.clamp(-12.0_f32, 12.0_f32)  // EQ gains and preamp
volume.clamp(0.0_f32, 1.0_f32)
pan.clamp(-1.0_f32, 1.0_f32)
```

### Frame Count vs. Sample Count
**Source:** `manzo-core/src/lib.rs` line 327 (`position_samples += frames_written / channels`)
**Apply to:** `eq10_processf` call sites in the cpal callback.

```rust
// Existing pattern at lib.rs line 327 — same calculation:
let num_frames = data.len() / s.channels as usize;
// Pass num_frames (not data.len()) as sz to eq10_processf — Pitfall 5
```

---

## No Analog Found

No files in this phase lack a codebase analog. All three files have direct patterns:
- `eq10.rs` — direct Rust port of `eq10dsp.cpp` (source read verbatim)
- `lib.rs` extension — extends existing `InnerState` and stub patterns in the same file
- `integration_test.rs` addition — extends existing test file structure

---

## Metadata

**Analog search scope:**
- `manzo-core/src/lib.rs` — primary analog for InnerState, FFI, and cpal callback patterns
- `manzo-core/tests/integration_test.rs` — primary analog for test structure
- `winamp/Src/Winamp/eq10dsp.cpp` — direct port source (read fully, 277 lines)
- `winamp/Src/Winamp/eq10dsp.h` — type definitions (read fully, 176 lines)
- `manzo-core/Cargo.toml` — confirmed no new dependencies required

**Files scanned:** 5 source files read directly
**Pattern extraction date:** 2026-04-22
