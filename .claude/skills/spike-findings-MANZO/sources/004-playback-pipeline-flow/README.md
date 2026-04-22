---
spike: "004"
name: playback-pipeline-flow
validates: "Given the full Winamp source, when tracing decoder → DSP → output plugin, then sample format at each handoff and macOS replacement points are identified"
verdict: VALIDATED
related: ["001-dsp-plugin-interface", "002-eq-math-vs-ui", "003-mp3-decoder-depth"]
tags: [pipeline, pcm, output, wasapi, coreaudiio, format]
---

# Spike 004: Playback Pipeline Flow

## What This Validates

The complete data flow from compressed audio to speaker: sample format at each stage,
where format conversions happen, and what macOS replaces at each layer.

## How to Run

Read-only analysis. Source files examined:
- `Src/Winamp/OUT.H` — output plugin interface
- `Src/Plugins/Output/out_wasapi/`, `out_ds/`, `out_wave/` — output backends
- `Src/Winamp/In.cpp:eq_dosamples_4front()` — EQ+DSP glue
- `Src/Winamp/DSP.cpp:dsp_dosamples()` — DSP dispatch
- `Src/mp3-mpg123/adts_mpg123.cpp:Decimate()` — float→int conversion

## Results

### Full Pipeline (MP3 → Speaker)

```
[File / Stream]
      │
      ▼
in_mp3 → DecodeThread
      │  mpg123_feed() + mpg123_read()
      │  → float PCM (interleaved, N channels)
      │
      ▼
ADTS_MPG123::Decimate()
      │  float → int16 (or int24/32) via nsutil_pcm_FloatToInt_Interleaved_Gain()
      │  → char * raw PCM bytes  [bps=16, nch=2, srate=44100 typical]
      │
      ▼  [passed as short int * to dsp_dosamples via In_Module.dsp_dosamples callback]
eq_dosamples_4front()  [In.cpp:1146]
      │  1. FillFloat(): short int16 → float32, apply preamp + ReplayGain multiplier
      │  2. eq10_processf(): 10-band biquad IIR per channel (float, in-place)
      │  3. FillSamples(): float32 → short int16
      │
      ▼
dsp_dosamples()  [DSP.cpp:76]
      │  winampDSPModule::ModifySamples(short int *, numsamples, bps, nch, srate)
      │  (no-op if no DSP plugin loaded)
      │  → short int * (may expand up to 2× samples)
      │
      ▼
Out_Module::Write(char *buf, int len)   [max 8192 bytes per call]
      │
      ├── out_wasapi  (WASAPI exclusive/shared, id=70) — best latency on Win10+
      ├── out_ds      (DirectSound, id=38)
      ├── out_wave    (WaveOut, id=32)
      └── out_disk    (disk writer, id=33)
```

### Output Plugin Interface (`OUT.H`)

```c
int  Open(int samplerate, int numchannels, int bitspersamp, int bufferlenms, int prebufferms);
int  Write(char *buf, int len);   // raw PCM bytes, <= 8192 bytes, non-blocking
int  CanWrite();                  // bytes available in output buffer
void SetVolume(int volume);       // 0–255
void SetPan(int pan);             // -128 to 128
void Flush(int t_ms);             // seek
int  GetOutputTime();             // played ms
int  GetWrittenTime();            // written ms (for vis sync)
```

Volume and pan are applied **inside the output plugin**, not in the pipeline above it.
This means on macOS, `SetVolume`/`SetPan` must be handled by the CoreAudio graph node,
not upstream.

### Format Boundaries

| Stage | Format |
|-------|--------|
| mpg123 output | float32 interleaved |
| After Decimate | int16 interleaved (`short int`) |
| EQ input/output | int16 → (internally float32) → int16 |
| DSP plugin input | int16 interleaved |
| Output plugin input | raw PCM bytes (int16 typical, or int24/32) |

### macOS Replacement Map

| Winamp component | macOS equivalent |
|-----------------|-----------------|
| `out_wasapi` / `out_ds` | `AVAudioEngine` output node or `AUAudioUnit` / `CoreAudio AudioQueue` |
| `DSP plugin (DLL)` | `AUv3` Audio Unit extension (sandboxed) |
| `SetVolume/SetPan` | `AVAudioMixerNode.volume` / `pan` |
| `CanWrite/Write` non-blocking poll | `AVAudioPlayerNode` schedule-buffer callback |
| `GetOutputTime` | `AVAudioPlayerNode.playerTime` |

The ≤8192-byte `Write()` call loop maps naturally to `AVAudioPlayerNode.scheduleBuffer(_:completionHandler:)`.
