---
phase: 07-spectrum-analyzer
plan: 03
status: complete
completed: "2026-04-24"
---

# Plan 07-03 Summary: ManzoSpectrumView Integration

## What was built

- `ManzoRootView.addSpectrumView()` — adds `ManzoSpectrumView` as subview of `bodyView`,
  225×32 pt, centered horizontally, bottom-anchored via `NSLayoutAnchor`
- `applySpectrumChromeMask()` — `CAShapeLayer` evenOdd mask punches a rectangular hole in
  the `NeoAeroContainer` chrome so the spectrum MTKView shows through; handles both
  `unifiedSlab` (root layer) and `threeBubbles`/`bodyFocus` (bodyView layer) layouts
- `AppDelegate` wiring — `ManzoSpectrumView` initialized after `orderFront`, handle wired
  to spectrum view, `startRenderLoop()` called after successful `manzo_play`

## UAT fixes applied (post-execution)

1. **test.mp3 bundle path** — `PBXResourcesBuildPhase` dropped from `project.pbxproj`
   during Phase 7 execution; re-added file references, build file entries, resources
   phase, group membership, and target build phase reference (same fix as Phase 3 UAT)

2. **NeoAeroContainer lookup** — `applySpectrumChromeMask` only searched
   `bodyView.layer?.sublayers`; default `.unifiedSlab` layout inserts the container into
   `layer` (root view). Fixed: search `bodyView.layer` first, fall back to root `layer`,
   convert `spectrumFrame` to root coords via `bodyView.convert(_:to:)`

3. **Dangling-handle crash** (`EXC_BAD_ACCESS`) — render loop called `manzo_get_spectrum`
   on freed Rust pointer after queue exhausted. Fixed: nil `spectrumView.manzoHandle`
   before every `manzo_close`; `stopRenderLoop()` on exhaustion/failure; re-wire handle
   to new track on advance; guard nil in `displayLinkFired` before FFI call

4. **Metal "addPresentedHandler" warning** — `currentRenderPassDescriptor` internally
   calls `currentDrawable` a second time, conflicting with the already-committed drawable
   in a manual render loop (`isPaused=true`). Fixed: build `MTLRenderPassDescriptor`
   manually from `drawable.texture`, eliminating the double-access

## UAT result

- Spectrum bars visible during playback (3 bars confirmed)
- Crash on queue exhaustion: resolved
- Full 75-bar spectrum test deferred to Phase 8 with real audio files
- **Status: Approved**
