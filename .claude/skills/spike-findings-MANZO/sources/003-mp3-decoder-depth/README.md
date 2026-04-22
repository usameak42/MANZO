---
spike: "003"
name: mp3-decoder-depth
validates: "Given in_mp3 and mp3-mpg123 sources, when traced from plugin entry to PCM output, then the decode pipeline depth and what a Swift/Rust replacement must cover is known"
verdict: VALIDATED
related: ["004-playback-pipeline-flow"]
tags: [mp3, decoder, mpg123, pipeline, pcm]
---

# Spike 003: MP3 Decoder Depth

## What This Validates

How deep the MP3 decode stack goes, what library does the actual bitstream decoding,
what sample format it produces, and what a macOS replacement must cover.

## How to Run

Read-only analysis. Source files examined:
- `Src/Plugins/Input/in_mp3/` — the `in_mp3` input plugin
- `Src/Plugins/Input/in_mp3/DecodeThread.cpp` — main decode loop
- `Src/mp3-mpg123/main.cpp` — the component factory (initializes libmpg123)
- `Src/mp3-mpg123/adts_mpg123.cpp` — the `adts` implementation wrapping mpg123

## Results

### Decoder Stack (in order of call depth)

```
in_mp3 plugin (DecodeThread)
  └── DecodeLoop::Decode()
        └── adts *decoder  (interface: adts::Decode / adts::GetOutputParameters)
              └── ADTS_MPG123 : adts  (mp3-mpg123 component)
                    └── mpg123_feed() / mpg123_read()  [libmpg123]
                          └── raw float PCM out
```

### Layer Details

**`in_mp3` plugin** (`DecodeThread.cpp`):
- Runs in a dedicated Windows thread (`DecodeThread`)
- Holds `CGioFile` (generic I/O abstraction over file/stream)
- Buffer: `BYTE g_samplebuf[6*3*2*2*1152]` — max MPEG frame size × layers
- Calls `decoder->Decode(file, buf, frameSize, &written)`
- Passes output bytes to `EndCutter` → `mod.outMod->Write(buf, bytes)` (output plugin)

**`ADTS_MPG123`** (`adts_mpg123.cpp`):
- Init flags: `MPG123_FORCE_FLOAT` — **always decodes to float**
- Feed loop: `mpg123_feed(decoder, buf, 4096)` until `MPG123_OK`
- `mpg123_read()` returns raw float samples
- `Decimate()` converts float → int (via `nsutil_pcm_FloatToInt_Interleaved_Gain`)
  - Or passes float through if `useFloat == true`
- Decoder delay: **529 samples** (MPEG priming frames, must be trimmed at start)
- ReplayGain applied as a `float gain` multiplier during `Decimate()`

**libmpg123** (`<mpg123.h>`, external binary dep):
- Streaming API: `open_feed` + `feed` + `read` pattern
- Format negotiation via `mpg123_getformat()` → sample rate, channels, encoding
- Frames per unit: `mpg123_spf()` (samples per frame, used for buffer sizing)

### macOS Port Implication

Two replacement paths:

1. **Keep libmpg123**: It has native ARM64 builds, BSD license, proven. Link directly
   from Swift (`#include <mpg123.h>`) or Rust (`mpg123-sys` crate). Decoder delay
   trimming (529 samples) must be preserved for gapless playback.

2. **Replace with minimp3 or AVFoundation**:
   - `minimp3` (single header, MIT) decodes to `short` or `float`; simpler but no
     ReplayGain support built in
   - `AVFoundation`/`AVAudioFile` handles MP3 natively on macOS and handles
     format conversion automatically, but loses fine control over decoder delay

The **streaming feed model** (`feed` → `read` loop) maps cleanly to Swift's
`AsyncStream<Data>` or Rust's `async fn` / channel pattern.
