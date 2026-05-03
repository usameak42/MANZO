# MANZO Roadmap

**Milestone:** v1.0 — Initial Release
**Granularity:** Fine
**Requirements:** 32 v1 requirements
**Last updated:** 2026-04-23

---

## Phases

- [x] **Phase 1: Build Foundation** — Cargo+Xcode dual build chain with cbindgen FFI bridge
- [x] **Phase 2: Audio Pipeline** — Rust MP3 decode via mpg123-sys + cpal/CoreAudio float32 output
- [x] **Phase 3: Playback Controls** — Gapless playback, transport (play/pause/stop/seek), auto-advance
- [x] **Phase 4: DSP Engine** — 10-band Rust EQ (eq10dsp.cpp port), volume, and pan controls
- [x] **Phase 5: UI Shell** — Frameless NSWindow, single-root vibrancy, drag region, window persistence
- [x] **Phase 6: Neo-Aero Visual Stack** — 5-layer CALayer specular stack, CAReplicatorLayer reflection, P3 color
- [ ] **Phase 7: Spectrum Analyzer** — MTKView FFT pipeline, SDF single-pass bloom, CADisplayLink render loop
- [ ] **Phase 8: Playlist & Library** — File picker, drag-reorder, track removal, playlist persistence
- [x] **Phase 8.1: Transport Controls and LCD Display** — Winamp-style LCD, transport buttons, seek bar, volume/pan sliders (INSERTED)
- [ ] **Phase 9: Complete UI Rewrite** — pixel-accurate implementation of MANZO design system from HTML spec
- [ ] **Phase 10: Online Streaming** — yt-dlp sidecar bundle, URL streaming, quarantine strip

---

## Phase Details

### Phase 1: Build Foundation

**Goal:** The Rust audio core compiles as a staticlib and links into the Swift app via a cbindgen-generated C header, with Cargo triggered automatically from Xcode.
**Depends on:** —
**Requirements:** BUILD-01, BUILD-02, BUILD-03
**UI hint:** no

**Success criteria:**
1. `xcodebuild` completes without manual `cargo build` — Rust staticlib is rebuilt by an Xcode run-script phase on every build.
2. Swift code can call at least one FFI function from the C header (e.g. `manzo_open`) without linker errors.
3. The cbindgen-generated header exposes exactly the 11 specified functions: `manzo_open`, `manzo_close`, `manzo_play`, `manzo_pause`, `manzo_stop`, `manzo_seek`, `manzo_set_eq`, `manzo_set_volume`, `manzo_set_pan`, `manzo_get_position`, `manzo_get_spectrum`.
4. A `cargo test` in the Rust crate passes, confirming the core is independently testable.

**Plans:** 3 plans

Plans:
- [x] 01-01-PLAN.md — Rust crate: manzo-core staticlib + 11 FFI stubs + cbindgen config
- [x] 01-02-PLAN.md — Xcode project: ManzoApp with run-script, bridging header, linker flags
- [x] 01-03-PLAN.md — Integration verification: cargo test + xcodebuild end-to-end

---

### Phase 2: Audio Pipeline

**Goal:** The app decodes an MP3 file via mpg123-sys feed/read API and outputs float32 PCM to CoreAudio through cpal — no int16 conversion at any stage.
**Depends on:** Phase 1
**Requirements:** AUDIO-01, AUDIO-04
**UI hint:** no

**Success criteria:**
1. A local MP3 file plays audibly through the Mac's audio output when triggered from Swift via the FFI.
2. The pipeline is float32 end-to-end — no int16 intermediate conversion between mpg123 output and cpal callback.
3. The mpg123 feed/read streaming API (`mpg123_open_feed` → `mpg123_feed` → `mpg123_read`) is used; `AVAudioFile` and `AVFoundation` are not used for decode.
4. The Rust audio thread runs independently without blocking the Swift main thread.

**Plans:** 3 plans

Plans:
- [x] 02-01-PLAN.md — Cargo.toml deps (mpg123-sys, cpal) + CC0 test MP3 fixture
- [x] 02-02-PLAN.md — lib.rs full implementation: InnerState, mpg123 feed/read, cpal float32 stream, all 11 FFI bodies
- [x] 02-03-PLAN.md — Integration tests + AppDelegate real MP3 wiring

---

### Phase 3: Playback Controls

**Goal:** Users can play, pause, stop, and seek within a track, and the app gaplessly advances to the next track by trimming the 529-sample mpg123 decoder delay.
**Depends on:** Phase 2
**Requirements:** AUDIO-02, AUDIO-03, AUDIO-05
**UI hint:** no

**Success criteria:**
1. User can play, pause, resume, and stop a track via FFI calls; audio state matches the command within one audio buffer cycle.
2. User can seek to an arbitrary position in a track and playback resumes from that position without audible glitch.
3. When one track ends the app automatically begins playing the next track in the playlist without a silence gap between them (529-sample decoder delay trimmed).
4. Gapless transition is verified by back-to-back playback of two MP3 files — no audible pop or silence at the boundary.

**Plans:** 3 plans

Plans:
- [x] 03-01-PLAN.md — Rust core: extend InnerState (playback_state + 529-sample trim) and add manzo_get_state / manzo_get_duration FFI getters
- [x] 03-02-PLAN.md — Test fixture (test2.mp3) + integration tests for state transitions, duration, and ENDED detection
- [x] 03-03-PLAN.md — Swift AppDelegate: 2-track auto-advance demo via 100ms manzo_get_state polling

---

### Phase 4: DSP Engine

**Goal:** Users hear 10-band parametric EQ applied in real time with no audio dropout, plus master volume and stereo pan control — all processing in the Rust audio thread.
**Depends on:** Phase 2
**Requirements:** DSP-01, DSP-02, DSP-03, DSP-04
**UI hint:** no

**Success criteria:**
1. 10-band EQ processes audio via the Rust `eq10dsp.cpp` dual-biquad IIR port; adjusting any band (±12 dB) takes effect within one buffer period with no dropout or click.
2. EQ preamp gain control adjusts the overall level before the biquad chain without clipping at 0 dB input.
3. User can set master volume (0–100%) and stereo pan (left/center/right) via `manzo_set_volume` and `manzo_set_pan` FFI calls; changes are audibly immediate.
4. EQ processing time on M1 stays under 0.1 ms per 1024-sample buffer, verified by Rust timing instrumentation.

**Plans:** 3 plans

Plans:
- [x] 04-01-PLAN.md — eq10.rs module: Eq10Band, Eq10State, eq10_processf, eq10_bsetup, eq10_db2gain (verbatim port of eq10dsp.cpp)
- [x] 04-02-PLAN.md — lib.rs wiring: extend InnerState, replace 3 FFI stubs, insert 5-stage DSP chain into cpal callback
- [x] 04-03-PLAN.md — Integration test: eq_perf_under_100us performance gate (D-07)

---

### Phase 5: UI Shell

**Goal:** The app presents a frameless NSWindow with a single-root `.behindWindow` vibrancy view, a custom drag region, and persistent window position — all inner panels are CALayer-only.
**Depends on:** Phase 1
**Requirements:** SHELL-01, SHELL-02, SHELL-03, SHELL-04, SHELL-05
**UI hint:** yes

**Success criteria:**
1. The app window has no system title bar or standard traffic-light buttons; it appears frameless with a glass/vibrancy background.
2. Exactly one `NSVisualEffectView` with `.behindWindow` blending exists in the window hierarchy; no nested `.behindWindow` views are present.
3. All inner panel views use `CALayer` only (`wantsLayer = true`, `isOpaque = false`); no `NSVisualEffectView` is nested inside the window body.
4. User can drag the window by clicking any non-interactive chrome area; the window moves with the cursor.
5. After relaunch the window appears at the same position and size it was at when last closed.

**Plans:** 2 plans

Plans:
- [ ] 05-01-PLAN.md — ManzoWindow.swift + ManzoRootView.swift: frameless window subclass, single-root vibrancy, three panel NSViews, drag handler
- [ ] 05-02-PLAN.md — AppDelegate wiring: window construction, contentView, orderFront, setFrameAutosaveName, xcodegen verify, visual checkpoint

---

### Phase 6: Neo-Aero Visual Stack

**Goal:** All panel chrome renders the full 5-layer Neo-Aero specular stack (base gradient, specular band, lower glow, rim, wet-floor reflection) using pure CALayer API — no bitmaps, all colors in P3.
**Depends on:** Phase 5
**Requirements:** VIS-01, VIS-02, VIS-03, VIS-04
**UI hint:** yes

**Success criteria:**
1. At least one main panel (e.g. the player chrome) renders all 5 layers — base gradient, specular band, lower glow, rim highlight, and wet-floor reflection — verifiable by visual inspection with no bitmap assets in the layer tree.
2. Wet-floor reflection is implemented via `CAReplicatorLayer` with a `CAGradientLayer` fade mask; it updates automatically as the panel moves without any per-frame CPU work.
3. Every brand color (aqua, teal, rim) in the panel chrome is specified as `CGColor(colorSpace: .displayP3)` — no `NSColor(calibratedRed:...)` or sRGB fallbacks.
4. Static panels have `shouldRasterize = true` and `rasterizationScale = 2.0`; GPU compositing time for 30+ static elements stays under 0.8 ms on M1.

**Plans:** 3 plans

Plans:
- [ ] 06-01-PLAN.md — NeoAeroLayerFactory + ManzoVisualStyle data models (new files)
- [ ] 06-02-PLAN.md — ManzoRootView.applyStyle() + wet-floor CAReplicatorLayer + cornerRadius=10
- [ ] 06-03-PLAN.md — AppDelegate wiring + xcodebuild verify + visual checkpoint

---

### Phase 7: Spectrum Analyzer

**Goal:** An `MTKView` renders real-time FFT magnitude bars from the Rust audio core with SDF single-pass bloom, P3 colorspace, and a `CADisplayLink` render loop on a background thread.
**Depends on:** Phase 2, Phase 5
**Requirements:** SPEC-01, SPEC-02, SPEC-03, SPEC-04
**UI hint:** yes

**Success criteria:**
1. The spectrum MTKView is configured with `.rgba16Float` pixel format and explicit displayP3 colorspace from first launch — `CAMetalLayer.colorspace` is set in code; no silent sRGB fallback.
2. FFT magnitude data flows from the Rust audio core to the Metal vertex shader via a shared `MTLBuffer` — no per-frame CPU copy of the FFT array.
3. The Metal fragment shader applies SDF single-pass bloom: bar quads extend by 3σ and compute analytical Gaussian glow per fragment; the result shows a visible neon-glow halo around active bars.
4. The render loop is driven by `CADisplayLink` on a dedicated background thread; the main thread is never blocked by Metal draw calls.

**Plans:** 3 plans

Plans:
- [ ] 07-01-PLAN.md — Rust FFT pipeline: rustfft dependency, InnerState FFT fields, audio callback computation, live manzo_get_spectrum
- [ ] 07-02-PLAN.md — Metal renderer: ManzoSpectrumView MTKView, Spectrum.metal SDF bloom shaders, project.yml Metal frameworks
- [ ] 07-03-PLAN.md — Integration: wire into ManzoRootView/AppDelegate, NeoAeroContainer chrome mask, build + visual verification

---

### Phase 8: Playlist & Library

**Goal:** Users can build and persist a playlist — adding files via NSOpenPanel, reordering by drag-and-drop, removing tracks, and finding the playlist restored on next launch.
**Depends on:** Phase 3, Phase 5
**Requirements:** LIB-01, LIB-02, LIB-03, LIB-04
**UI hint:** yes

**Success criteria:**
1. User can open an `NSOpenPanel`, select one or more audio files, and see them appear in the playlist immediately.
2. User can drag a track row to a new position in the playlist; the new order is reflected in playback sequence.
3. User can select a track and remove it from the playlist; playback is unaffected if the removed track is not currently playing.
4. On next app launch the playlist (file paths and display metadata) is restored to the state from the previous session.

**Plans:** 5 plans

Plans:
- [x] 08-01-PLAN.md — PlaylistTrack + PlaylistManager (model layer + JSON persistence)
- [x] 08-02-PLAN.md — ManzoPlaylistPanel + PlaylistRowView (visual shell + NeoAero chrome)
- [x] 08-03-PLAN.md — AppDelegate wiring (PlaylistManager integration, PL button, co-move, Alt+E)
- [x] 08-04-PLAN.md — NSTableView drag-reorder + Delete key + right-click context menu
- [ ] 08-05-PLAN.md — Build verification + end-to-end UAT checkpoint

---

### Phase 8.1: Transport Controls and LCD Display (INSERTED)

**Goal:** The main window presents a Winamp-style LCD display (scrolling title, elapsed/total time, bitrate, kHz) and a full transport control row (prev, play/pause, stop, next), a clickable seek bar, and volume/pan sliders — all wired to the existing Rust FFI.
**Depends on:** Phase 8
**Requirements:** CTRL-01, CTRL-02, CTRL-03, CTRL-04
**UI hint:** yes

**Success criteria:**
1. The LCD area in the main window displays the current track title (scrolling if too long), elapsed time, total duration, bitrate in kbps, and sample rate in kHz — green text on black Winamp-style background.
2. Clicking prev/play/pause/stop/next buttons produces the correct audio state change via the existing `manzo_play`, `manzo_pause`, `manzo_stop`, `manzo_seek` FFI calls within one buffer cycle.
3. The seek bar reflects track position in real time (updated on the 100ms polling loop); clicking or dragging it seeks to the corresponding position via `manzo_seek`.
4. Volume and pan sliders are wired to `manzo_set_volume` and `manzo_set_pan`; audio level and stereo position change immediately without dropout.

**Plans:** 3 plans

Plans:
- [x] 08.1-01-PLAN.md — ManzoLCDView + ManzoSeekBar + ManzoSlider (pure view layer, no FFI)
- [x] 08.1-02-PLAN.md — ManzoTransportButton + PlaylistManager.prev() (transport button chrome + model)
- [x] 08.1-03-PLAN.md — ManzoRootView layout methods + AppDelegate wiring + xcodebuild verify

---

### Phase 9: Complete UI Rewrite

**Goal:** The main window, playlist window, and EQ window are pixel-accurately rebuilt to match the MANZO design system HTML spec — correct dimensions (540×116pt main window), VT323 LCD with green glow, teal→green seek/slider fills, Winamp-style transport row, dark playlist, and 10-band EQ with curve graph.
**Depends on:** Phase 8.1
**Requirements:** CTRL-01, CTRL-02, CTRL-03, CTRL-04
**UI hint:** yes

**Reference:** `/Users/usameak42/Coding/MANZO/manzo-design-system/project/manzo_ui_kit.html`

**Success criteria:**
1. Main window is exactly 540×116pt; titlebar shows traffic light dots + centered "MANZO" text; status bar shows "▶ PLAYING" left and "SHUF · REP · EQ" badges right.
2. LCD area renders VT323 timer with P3 green glow, scrolling marquee track title, kbps/kHz/STEREO specs, and spectrum analyzer in the top-right corner.
3. Seek bar has teal→green gradient fill and white thumb; transport buttons match the glass-pill aesthetic from the HTML spec; VOL and BAL sliders use the same gradient fill.
4. Playlist window has a dark background (not white/aqua) with blue-highlight active row; EQ window renders LED ON/OFF buttons, EQ curve graph, preamp + 10 band sliders (31Hz–16kHz), dB scale, and PRESETS button.

**Plans:** TBD

---

### Phase 10.1: YouTube Streaming

**Goal:** User can paste a YouTube URL into the ONLINE tab of the playlist panel; audio streams via yt-dlp stdout into the Rust pipeline; track appears in playlist and obeys all transport controls.
**Depends on:** Phase 2, Phase 8
**Requirements:** NET-01, NET-02, NET-03
**UI hint:** yes

**Success criteria:**
1. yt-dlp universal binary bundled at `Contents/MacOS/yt-dlp`; present and executable after installation without manual setup.
2. Quarantine xattr stripped on first launch; subsequent launches do not re-trigger.
3. YouTube URL → audio begins playing within a few seconds via yt-dlp stdout piped into the Rust pipeline.
4. Track visible in ONLINE tab; play/pause/stop/seek work identically to local tracks.

**Plans:** TBD

---

### Phase 10.2: SoundCloud Streaming

**Goal:** User can paste a SoundCloud URL into the ONLINE tab; audio streams via the same yt-dlp pipeline established in Phase 10.1.
**Depends on:** Phase 10.1
**Requirements:** NET-01, NET-02, NET-03
**UI hint:** yes

**Success criteria:**
1. SoundCloud URL → audio plays via the same yt-dlp pipeline with no changes to the Rust core.
2. SC badge shown in the ONLINE tab row for SoundCloud tracks.
3. No changes needed to Rust core.

**Plans:** TBD

---

## Progress Table

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Build Foundation | 3/3 | Complete | 2026-04-20 |
| 2. Audio Pipeline | 3/3 | Complete | 2026-04-22 |
| 3. Playback Controls | 3/3 | Complete | 2026-04-22 |
| 4. DSP Engine | 0/3 | Not started | - |
| 5. UI Shell | 0/2 | Not started | - |
| 6. Neo-Aero Visual Stack | 0/? | Not started | - |
| 7. Spectrum Analyzer | 0/? | Not started | - |
| 8. Playlist & Library | 0/? | Not started | - |
| 8.1. Transport Controls and LCD Display | 3/3 | Complete | 2026-04-24 |
| 9. Complete UI Rewrite | 0/? | Not started | - |
| 10. Online Streaming | 0/? | Not started | - |

---

## Coverage Validation

| Requirement | Phase |
|-------------|-------|
| BUILD-01 | Phase 1 |
| BUILD-02 | Phase 1 |
| BUILD-03 | Phase 1 |
| AUDIO-01 | Phase 2 |
| AUDIO-04 | Phase 2 |
| AUDIO-02 | Phase 3 |
| AUDIO-03 | Phase 3 |
| AUDIO-05 | Phase 3 |
| DSP-01 | Phase 4 |
| DSP-02 | Phase 4 |
| DSP-03 | Phase 4 |
| DSP-04 | Phase 4 |
| SHELL-01 | Phase 5 |
| SHELL-02 | Phase 5 |
| SHELL-03 | Phase 5 |
| SHELL-04 | Phase 5 |
| SHELL-05 | Phase 5 |
| VIS-01 | Phase 6 |
| VIS-02 | Phase 6 |
| VIS-03 | Phase 6 |
| VIS-04 | Phase 6 |
| SPEC-01 | Phase 7 |
| SPEC-02 | Phase 7 |
| SPEC-03 | Phase 7 |
| SPEC-04 | Phase 7 |
| LIB-01 | Phase 8 |
| LIB-02 | Phase 8 |
| LIB-03 | Phase 8 |
| LIB-04 | Phase 8 |
| CTRL-01 | Phase 8.1 |
| CTRL-02 | Phase 8.1 |
| CTRL-03 | Phase 8.1 |
| CTRL-04 | Phase 8.1 |
| NET-01 | Phase 10 |
| NET-02 | Phase 10 |
| NET-03 | Phase 10 |

**Mapped: 36/36**

---

## v2 Backlog

Features deferred from v1.0 scope. No phase assigned; implement after v1.0 ships.

### FEAT-V2-01: Dynamic Wallpaper Color Sampling

**Summary:** On launch and when the desktop wallpaper changes, sample the wallpaper's dominant colors and generate a matching ManzoVisualStyle palette automatically.

**Implementation sketch:**
- Observe `NSWorkspace.didChangeDesktopImageNotification` for wallpaper changes; also fire on launch
- Read wallpaper via `NSWorkspace.shared.desktopImageURL(for:)` → `CIImage`
- Extract dominant colors using `CIFilter` kMeans clustering (e.g. `CIKMeans` with k=5)
- Map cluster centroids → `ManzoVisualStyle` palette (base gradient stops, specular tint, rim glow color)
- Apply via `NeoAeroLayerFactory` — existing `applyStyle` wiring means gradient updates automatically
- User toggle in preferences: "Auto (match wallpaper)" vs manual theme selection
- Theme persists to `UserDefaults`; auto mode re-samples on next wallpaper change notification

**Dependencies:** Phase 6 (NeoAeroLayerFactory + ManzoVisualStyle) — already complete
