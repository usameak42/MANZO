---
spike: "001"
name: dsp-plugin-interface
validates: "Given Winamp's DSP.H + DSP.cpp, when audio flows through the chain, then the exact API contract (sample format, buffer layout, callback signature) is known for a macOS port"
verdict: VALIDATED
related: ["004-playback-pipeline-flow"]
tags: [dsp, api, audio, plugin]
---

# Spike 001: DSP Plugin Interface

## What This Validates

The exact ABI a macOS port must replicate (or redesign) for DSP plugin compatibility.
Specifically: what sample format enters `ModifySamples`, what the return contract is,
and how many plugins can be active simultaneously.

## How to Run

Read-only analysis. Source files examined:
- `Src/Winamp/DSP.H` — plugin struct definition
- `Src/Winamp/DSP.cpp` — host-side loader and dispatcher
- `Src/Winamp/eq10dsp.h/.cpp` — internal DSP implementation (4Front EQ10)

## What to Expect

A clear struct definition with typed callback signatures.

## Results

### The Contract (`DSP.H`)

```c
int ModifySamples(winampDSPModule *this_mod,
                  short int *samples,   // interleaved int16 PCM, in-place
                  int numsamples,       // sample count per channel
                  int bps,             // bits per sample (16 typical)
                  int nch,             // num channels
                  int srate);          // sample rate Hz
// Returns: new numsamples (0.5x–2x input; never < 128 recommended)
```

Key observations:
- **Single plugin only**: `DSP.cpp` holds one `winampDSPModule *mod`. No chain/rack.
- **16-bit signed integer interleaved PCM** is the wire format into external plugins.
- Plugin loaded via `winampDSPGetHeader2()` exported from a DLL; host fills `hwndParent` + `hDllInstance` before `Init()`.
- `dsp_dosamples()` in `DSP.cpp:76` is the only call site — called after the internal EQ.
- Version flags: `DSP_HDRVER 0x20` (basic), `0x22` (with HWND pass-through).

### macOS Port Implication

A macOS port can either:
1. **Drop external DSP plugins entirely** (no Win32 DLL loading) and expose a native audio unit / AUv3 slot instead.
2. **Keep the int16 interleaved PCM contract** and wrap it in a Swift/Rust trait/protocol for native plugin extensions.

The EQ10 DSP (`eq10dsp.cpp`) is the **internal** EQ — it runs before the external plugin slot and operates on floats internally (see Spike 002).
