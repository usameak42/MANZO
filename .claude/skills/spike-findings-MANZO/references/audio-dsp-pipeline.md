# Audio DSP Pipeline

Validated patterns from Winamp source reverse-engineering for the Rust audio core.

## Validated Patterns

### DSP Plugin Contract (Spike 001)
Winamp's external DSP ABI: `ModifySamples(module, short int* samples, numsamples, bps, nch, srate)`.
Only **one** plugin active at a time — no chain. Wire format is int16 interleaved PCM.
macOS replacement: expose an AUv3 Audio Unit slot, or a Rust `DspPlugin` trait with identical signature.

### EQ Math — Dual Biquad IIR (Spike 002)
10-band peaking EQ in `eq10dsp.cpp` (~200 lines). Direct Rust port:
```rust
// Per sample, per band:
let y0 = (x - x2) * a0 + y1 * b1 + y2 * b2 + 1e-30_f64; // denormal fix
out = y0 + x; // peaking: add filtered delta
```
- Double-precision coefficients, float32 sample processing
- **Dual coefficient sets**: separate `(ua0,ub1,ub2)` for boost, `(da0,db1,db2)` for cut
- Dynamic output limiter at -0.6 dB (`TRIM_CODE = 0.930`)
- Bands (Winamp): `{70, 180, 320, 600, 1000, 3000, 6000, 12000, 14000, 16000}` Hz, Q=1.41

### `VALTODB()` Mapping (Spike 002)
EQ preset format uses `unsigned char [10]` values 0–63. Mapping:
```swift
// v=31 → 0dB; v>31 → positive gain; v<31 → negative gain
if v > 31 { return -12.0 * (v - 31) / 32.0 }  // boost: 0 → +12dB
else       { return -12.0 * (v - 31) / 31.0 }  // cut: 0 → -12dB
```
Must preserve exactly for `.eqf` preset file compatibility.

### MP3 Decode Stack (Spike 003)
`in_mp3` → `ADTS_MPG123` → libmpg123 streaming feed API:
```
mpg123_open_feed → mpg123_feed(buf, 4096) → mpg123_read → float32 PCM
```
- `MPG123_FORCE_FLOAT` flag — always outputs float
- **Decoder delay = 529 samples** — must trim for gapless playback
- Rust: `mpg123-sys` crate preserves this API exactly

### Full Playback Pipeline — Format Boundaries (Spike 004)
```
mpg123 → float32 interleaved
Decimate() → int16 interleaved          ← unnecessary conversion; collapse in port
eq_dosamples_4front():
  FillFloat()  int16 → float32          ← 2nd unnecessary int16↔float round-trip
  eq10_processf() float32 in-place
  FillSamples() float32 → int16
DSP plugin → int16 interleaved
Out_Module::Write(char*, ≤8192 bytes)  → CoreAudio
```
macOS port should **collapse both int16↔float conversions** — run float32 end-to-end
from mpg123 output through EQ to CoreAudio. Zero precision loss, fewer copies.

### macOS Output Replacement Map (Spike 004)
| Winamp | macOS |
|--------|-------|
| `Out_Module::Write(char*, ≤8192)` | `AVAudioPlayerNode.scheduleBuffer(_:completionHandler:)` |
| `SetVolume(0–255)` / `SetPan(-128–128)` | `AVAudioMixerNode.volume` / `.pan` |
| `CanWrite()` non-blocking poll | `AVAudioPlayerNode` buffer completion callback |
| `GetOutputTime()` | `AVAudioPlayerNode.playerTime` |
| `DSP plugin (DLL)` | AUv3 Audio Unit extension |

## Landmines

- **openmpt's `EQ.h` is unrelated** — it's a 6-band EQ for tracker music (MOD/XM) only, never called in the MP3/WAV path. Do not confuse with the main EQ.
- **AVFoundation hides decoder delay** — if using `AVAudioFile` for MP3, the 529-sample priming trim is not exposed. Use libmpg123 directly for gapless accuracy.
- **Volume/pan live in the output plugin**, not the pipeline. Do not add a gain stage upstream of `AVAudioMixerNode`.
- **DSP plugin returns variable sample count** (0.5×–2× input). Any replacement must handle dynamic buffer resizing.

## Constraints

- EQ preset files (`.eqf`) use `unsigned char [10]` 0–63 range — `VALTODB()` mapping is fixed
- Decoder priming delay: exactly 529 samples for MPEG Layer 3
- `Out_Module::Write` contract: ≤8192 bytes per call, non-blocking (returns 1 if full)
- EQ bands: Winamp mode (70–16000 Hz) or ISO mode (31–16000 Hz) — config-selectable

## Origin
Synthesized from spikes: 001, 002, 003, 004
Source files: `sources/001-dsp-plugin-interface/`, `sources/002-eq-math-vs-ui/`, `sources/003-mp3-decoder-depth/`, `sources/004-playback-pipeline-flow/`
