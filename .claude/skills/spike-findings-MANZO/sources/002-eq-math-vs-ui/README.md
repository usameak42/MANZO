---
spike: "002"
name: eq-math-vs-ui
validates: "Given EQ code in both Winamp core and openmpt-trunk, when we diff their roles, then we know where real IIR/biquad math lives and what a macOS port must reimplement"
verdict: VALIDATED
related: ["001-dsp-plugin-interface", "004-playback-pipeline-flow"]
tags: [eq, dsp, math, biquad, iir, openmpt]
---

# Spike 002: EQ Math vs UI

## What This Validates

Whether the real EQ signal processing is in Winamp's own core, in the openmpt library,
or split between them — and exactly what the filter math looks like for porting.

## How to Run

Read-only analysis. Source files examined:
- `Src/Winamp/Eq.cpp` — EQ window UI logic
- `Src/Winamp/Equi.cpp` — EQ mouse/slider interaction
- `Src/Winamp/eq10dsp.h/.cpp` — 4Front EQ10 math engine
- `Src/Winamp/In.cpp:1146–1248` — `eq_dosamples_4front()` — glue layer
- `Src/external_dependencies/openmpt-trunk/sounddsp/EQ.h` — openmpt EQ

## Results

### Verdict: Two completely independent EQ implementations, zero overlap.

---

### 1. Winamp's Built-in EQ (used for MP3/WAV/all normal audio)

**UI layer** (`Eq.cpp`, `Equi.cpp`, `draw_eq.cpp`):
- Win32 dialog/subclassing for the EQ window
- Reads slider positions as `unsigned char eq_tab[10]` (0–63 range per band)
- Calls `eq_set(on, data[10], preamp)` → `VALTODB(v)` maps `0–63 → +12dB to -12dB`
- Calls `eq10_setgain(eq, nch, bandnr, dB)` on slider change

**Math layer** (`eq10dsp.cpp`):

10-band peaking equalizer using dual biquad IIR (one per boost direction):

```c
// Biquad coefficients computed in eq10_bsetup2():
angle  = 2π * freq / srate
alpha  = sin(angle) / (2 * Q)        // Q = 1.41 global
b0     = 1 / (1 + alpha)
a0     = b0 * alpha                   // stored as ua0 (boost) or da0 (cut)
b1     = b0 * 2 * cos(angle)
b2     = b0 * (alpha - 1)

// Inner loop per sample (eq10_processf):
y0 = (x[n] - x[n-2]) * a0 + y[n-1]*b1 + y[n-2]*b2
out[n] = y0 + x[n]   // peaking: add filtered delta to input
```

Bands: `{70, 180, 320, 600, 1000, 3000, 6000, 12000, 14000, 16000}` Hz (Winamp mode)
or ISO: `{31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000}` Hz

- **Double-precision coefficients**, float sample processing
- Dynamic output limiter at -0.6 dB (`EQ10_TRIM_CODE = 0.930`)
- Denormal fix: adds `1e-30` to prevent subnormal float stalls

**Processing glue** (`In.cpp:eq_dosamples_4front()`):
```
int16 PCM → FillFloat() → eq10_processf() → FillSamples() → int16 PCM → DSP plugin
```
Preamp + ReplayGain applied during `FillFloat()` conversion.

---

### 2. OpenMPT EQ (`external_dependencies/openmpt-trunk/sounddsp/EQ.h`)

**Completely separate**. Used only by `in_mod-openmpt` for tracker file playback (MOD, XM, S3M, IT).
- 6 bands max, 4 channels max (`MAX_EQ_CHANNELS = 4`, `MAX_EQ_BANDS = 6`)
- Standard direct-form II biquad (`a0,a1,a2,b1,b2` in `EQBANDSETTINGS`)
- `CEQ::Process()` operates on `MixSampleInt` or `MixSampleFloat` — tracker mixing types
- Never called in the MP3/WAV playback path.

---

### macOS Port Implication

The EQ10 math is ~200 lines of C. Direct port to Swift/Rust is trivial:
- Replace `double` coefficients with `Float64`, `float` samples with `Float32`
- The inner loop `y0 = (x-x2)*a0 + y1*b1 + y2*b2` is straightforwardly vectorizable with `vDSP_biquad` (Accelerate) or Rust's `ndarray`/manual NEON intrinsics
- Retain the dual-biquad trick (separate coefficients for boost vs. cut)
- The `VALTODB()` mapping (`0–63 → ±12dB`) must be preserved for preset compatibility
