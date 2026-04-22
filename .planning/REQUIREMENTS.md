# Requirements: MANZO

**Defined:** 2026-04-20
**Core Value:** A tactile, skeuomorphic music player that sounds and looks like Winamp — running native on Apple Silicon, with glass chrome you can feel and DSP math bit-accurate to the original.

## v1 Requirements

### Audio Core

- [ ] **AUDIO-01**: App plays MP3 files with CoreAudio output via cpal on Apple Silicon
- [x] **AUDIO-02**: App achieves gapless playback by trimming the 529-sample mpg123 decoder delay in Rust
- [x] **AUDIO-03**: User can play, pause, stop, and seek within a track
- [x] **AUDIO-04**: App decodes MP3 via mpg123-sys feed/read streaming API with float32 pipeline end-to-end
- [x] **AUDIO-05**: App auto-advances to the next track in the playlist when a track ends

### DSP

- [ ] **DSP-01**: App applies 10-band parametric EQ using a Rust port of eq10dsp.cpp dual-biquad IIR
- [ ] **DSP-02**: User can adjust each EQ band (±12 dB) in real time without audio dropout
- [ ] **DSP-03**: App exposes EQ preamp gain control
- [ ] **DSP-04**: User can control master volume (0–100%) and stereo pan

### UI Shell

- [ ] **SHELL-01**: App presents a single frameless NSWindow with a custom drag region for the title bar
- [ ] **SHELL-02**: Window composites one root `.behindWindow` NSVisualEffectView; no nested vibrancy views
- [ ] **SHELL-03**: All inner panels are CALayer-only with `isOpaque = false`; no nested NSVisualEffectView
- [ ] **SHELL-04**: User can drag the window by clicking non-interactive chrome areas
- [ ] **SHELL-05**: App restores window position and size between launches via UserDefaults

### Visual (Neo-Aero Stack)

- [ ] **VIS-01**: Panel chrome renders the 5-layer Neo-Aero specular stack (base gradient → specular band → lower glow → rim → wet-floor reflection) via CAGradientLayer — no bitmaps
- [ ] **VIS-02**: Wet-floor reflection is rendered via CAReplicatorLayer on applicable panels
- [ ] **VIS-03**: All brand colors are specified as `CGColor(colorSpace: .displayP3)` — aqua/teal P3 palette
- [ ] **VIS-04**: Static panels set `shouldRasterize = true` for GPU compositing performance

### Spectrum Analyzer

- [ ] **SPEC-01**: MTKView renders the spectrum with `.rgba16Float` pixel format and explicit P3 colorspace
- [ ] **SPEC-02**: FFT magnitude data flows from the Rust audio core to Metal via a shared `MTLBuffer`
- [ ] **SPEC-03**: Spectrum shader applies SDF single-pass bloom effect (v1; MPS two-pass deferred to v2)
- [ ] **SPEC-04**: `CADisplayLink` drives the render loop on a dedicated background thread

### Playlist & Library

- [ ] **LIB-01**: User can add local audio files to the playlist via an NSOpenPanel file picker
- [ ] **LIB-02**: User can reorder tracks in the playlist by drag-and-drop
- [ ] **LIB-03**: Playlist (file paths and metadata) persists between app launches
- [ ] **LIB-04**: User can remove individual tracks from the playlist

### Online Streaming

- [ ] **NET-01**: App bundles a yt-dlp universal binary at `Contents/MacOS/yt-dlp`
- [ ] **NET-02**: User can paste a URL into a field and stream audio via yt-dlp piped into the Rust audio pipeline
- [ ] **NET-03**: App strips the quarantine extended attribute from yt-dlp on first launch

### Build & FFI Bridge

- [x] **BUILD-01
**: Rust audio core compiles as a `staticlib` linked into the Swift/AppKit app via a cbindgen-generated C header
- [x] **BUILD-02
**: FFI surface exposes exactly these functions: `manzo_open`, `manzo_close`, `manzo_play`, `manzo_pause`, `manzo_stop`, `manzo_seek`, `manzo_set_eq`, `manzo_set_volume`, `manzo_set_pan`, `manzo_get_position`, `manzo_get_spectrum`
- [x] **BUILD-03
**: Cargo build is triggered via an Xcode run-script build phase; no manual `cargo build` required

## v2 Requirements

### Liquid Glass (macOS 26)

- **GLASS-01**: Window uses the confirmed Liquid Glass AppKit API when macOS 26 SDK ships
- **GLASS-02**: Liquid Glass effect applied to main window chrome with physical refraction simulation

### Advanced Audio

- **ADVAUDIO-01**: App supports FLAC, AAC, and OGG Vorbis in addition to MP3
- **ADVAUDIO-02**: App exposes an AUv3 plugin slot for third-party effects

### Spectrum Enhancement

- **SPEC-05**: Spectrum renderer uses MPS two-pass Gaussian bloom for higher quality (v2)

### Skins

- **SKIN-01**: User can load classic Winamp .wsz bitmap skin files to replace the Neo-Aero chrome

### Social / Metadata

- **META-01**: App scrobbles currently playing track to Last.fm
- **META-02**: App fetches and displays album art from MusicBrainz / embedded tags

## Out of Scope

| Feature | Reason |
|---------|--------|
| Windows / Linux support | Apple Silicon + macOS-native APIs are core to the aesthetic; no cross-platform abstraction |
| iOS / iPadOS port | UIKit/SwiftUI port is a separate product; desktop-first |
| Win32 DSP plugin DLLs | Not applicable on macOS; AUv3 is the v2 extension mechanism |
| Online music store / streaming subscriptions | Playback tool, not a service |
| AirPlay / DLNA / UPnP | Network output deferred post-v1 |
| x86_64 / Intel Mac support | Apple Silicon NEON SIMD and Metal features not guaranteed on Intel |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| BUILD-01 | Phase 1 | Pending |
| BUILD-02 | Phase 1 | Pending |
| BUILD-03 | Phase 1 | Pending |
| AUDIO-01 | Phase 2 | Pending |
| AUDIO-04 | Phase 2 | Pending |
| AUDIO-02 | Phase 3 | Pending |
| AUDIO-03 | Phase 3 | Pending |
| AUDIO-05 | Phase 3 | Pending |
| DSP-01 | Phase 4 | Pending |
| DSP-02 | Phase 4 | Pending |
| DSP-03 | Phase 4 | Pending |
| DSP-04 | Phase 4 | Pending |
| SHELL-01 | Phase 5 | Pending |
| SHELL-02 | Phase 5 | Pending |
| SHELL-03 | Phase 5 | Pending |
| SHELL-04 | Phase 5 | Pending |
| SHELL-05 | Phase 5 | Pending |
| VIS-01 | Phase 6 | Pending |
| VIS-02 | Phase 6 | Pending |
| VIS-03 | Phase 6 | Pending |
| VIS-04 | Phase 6 | Pending |
| SPEC-01 | Phase 7 | Pending |
| SPEC-02 | Phase 7 | Pending |
| SPEC-03 | Phase 7 | Pending |
| SPEC-04 | Phase 7 | Pending |
| LIB-01 | Phase 8 | Pending |
| LIB-02 | Phase 8 | Pending |
| LIB-03 | Phase 8 | Pending |
| LIB-04 | Phase 8 | Pending |
| NET-01 | Phase 9 | Pending |
| NET-02 | Phase 9 | Pending |
| NET-03 | Phase 9 | Pending |

**Coverage:**
- v1 requirements: 32 total
- Mapped to phases: 32
- Unmapped: 0

---
*Requirements defined: 2026-04-20*
*Last updated: 2026-04-20 after roadmap creation*
