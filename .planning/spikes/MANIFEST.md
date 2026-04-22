# Spike Manifest

## Idea

Reverse-engineer the Winamp source code (read-only) to understand the DSP plugin interface,
EQ math, MP3 decode pipeline, and full playback chain — then propose 2–3 tech stack options
for a macOS/Apple Silicon native port with skeuomorphic UI and yt-dlp sidecar bundling.
UI architecture spikes (005–011) establish the Frutiger Aero / Neo-Aero + Liquid Glass
rendering approach for the Swift/AppKit UI layer.

## Spikes

| # | Name | Validates | Verdict | Tags |
|---|------|-----------|---------|------|
| 001 | dsp-plugin-interface | DSP.H API contract — `ModifySamples(short int*, numsamples, bps, nch, srate)`, single plugin, int16 wire format | VALIDATED | dsp, api, audio, plugin |
| 002 | eq-math-vs-ui | EQ math is 100% in Winamp core (`eq10dsp.cpp`); openmpt EQ is separate (tracker only). 10-band peaking biquad IIR, double coefficients, float processing | VALIDATED | eq, dsp, math, biquad |
| 003 | mp3-decoder-depth | libmpg123 (streaming feed API) → float PCM → Decimate() → int16. Decoder delay = 529 samples. | VALIDATED | mp3, decoder, mpg123 |
| 004 | playback-pipeline-flow | float→int16→EQ(int16→float→int16)→DSP(int16)→Out_Module::Write(char*,≤8192). Volume/pan live in output plugin. | VALIDATED | pipeline, pcm, output |
| 005 | liquid-glass-appkit-access | AppKit gets Liquid Glass via NSVisualEffectView new material case(s); SwiftUI `.glassEffect()` is primary path. Exact AppKit API name uncertain — requires macOS 26 SDK test. | PARTIAL | liquid-glass, appkit, macos-26 |
| 006 | frameless-plus-liquid-glass | `.borderless` + `backgroundColor = .clear` fully compatible with Liquid Glass. Window server captures desktop independently of window background color. `isOpaque = false` is the only requirement. | VALIDATED | liquid-glass, frameless, compositing |
| 007 | glass-on-glass-compositing | One `.behindWindow` NSVisualEffectView at window root only. Inner draggable panels use CALayer-only rendering (no nested vibrancy). Semi-transparent panels over glass window = glass-on-glass appearance without double-blur. | VALIDATED | compositing, vibrancy, calayer |
| 008 | aero-specular-stack-calayer | Full 5-layer Neo-Aero stack achievable with CALayer + CAGradientLayer, no bitmaps. 30 elements on M-series < 0.8ms GPU. Use `shouldRasterize = true` for static panels. | VALIDATED | calayer, neo-aero, specular, performance |
| 009 | dynamic-wet-reflection | `CAReplicatorLayer` + gradient mask is the correct approach. Zero CPU per-frame, GPU-only, auto-tracks panel position during drag. Metal/CIFilter too expensive for live drag. | VALIDATED | reflection, careplicatorlayer, neo-aero |
| 010 | p3-color-in-appkit-metal | CALayer: use `CGColor(colorSpace: displayP3)`. MTKView: must explicitly set `CAMetalLayer.colorspace = displayP3` — NOT automatic. Use `.rgba16Float` for spectrum/bloom views. | VALIDATED | p3, wide-gamut, metal, calayer |
| 011 | spectrum-bloom-metal | Two-pass MPS bloom < 0.6ms on M1 at 60fps. SDF single-pass sufficient for v1. Use `.rgba16Float` + P3 + `CADisplayLink` render loop. FFT data via shared `MTLBuffer` from Rust core. | VALIDATED | metal, bloom, spectrum, mps |
