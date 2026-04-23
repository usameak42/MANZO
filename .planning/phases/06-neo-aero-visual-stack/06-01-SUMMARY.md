---
phase: 06-neo-aero-visual-stack
plan: "01"
subsystem: ui-chrome
tags: [swift, calayer, neo-aero, p3-color, cagradientlayer, userdefaults, codable]
dependency_graph:
  requires: []
  provides:
    - NeoAeroLayerFactory (make + makeSimplified)
    - ManzoVisualStyle (PanelLayout, ColorTheme, UserDefaults persistence)
  affects:
    - ManzoApp/ManzoApp/ManzoRootView.swift (Plan 02 insertion point)
    - ManzoApp/ManzoApp/AppDelegate.swift (Plan 03 wiring point)
tech_stack:
  added: []
  patterns:
    - CAGradientLayer 5-layer specular stack (spike 008 pattern)
    - CGColorSpace.displayP3 for all brand colors (D-05, VIS-03)
    - shouldRasterize=true + rasterizationScale=2.0 on container (D-08, VIS-04)
    - Codable + UserDefaults JSON persistence for ManzoVisualStyle
key_files:
  created:
    - ManzoApp/ManzoApp/ManzoVisualStyle.swift
    - ManzoApp/ManzoApp/NeoAeroLayer.swift
  modified:
    - ManzoApp/ManzoApp.xcodeproj/project.pbxproj (xcodegen regenerated twice)
decisions:
  - wszSkin falls through to winampClassic in palette() — no v2 code, zero palette values (D-04)
  - Private Palette struct used inside NeoAeroLayerFactory to avoid exposing color internals
  - Shared white-alpha colors extracted as let constants to avoid duplication across themes
  - container tagged via setValue NeoAeroContainer forKey name for Plan 02 layer removal
metrics:
  duration: "2m"
  completed: "2026-04-24"
  tasks_completed: 2
  files_created: 2
  files_modified: 1
---

# Phase 06 Plan 01: Neo-Aero Layer Factory + Visual Style Models Summary

**One-liner:** NeoAeroLayerFactory (5-layer + simplified 2-layer P3 chrome stacks) and ManzoVisualStyle (Codable data models with UserDefaults persistence) for the Neo-Aero visual stack foundation.

## Tasks Completed

| # | Name | Commit | Files |
|---|------|--------|-------|
| 1 | ManzoVisualStyle data models + UserDefaults persistence | d1376d2 | ManzoApp/ManzoApp/ManzoVisualStyle.swift |
| 2 | NeoAeroLayerFactory with all ColorTheme palettes | 8edcbd2 | ManzoApp/ManzoApp/NeoAeroLayer.swift |

## What Was Built

### ManzoVisualStyle.swift
- `PanelLayout` enum (`.unifiedSlab`, `.threeBubbles`, `.bodyFocus`) with `Codable` conformance
- `ColorTheme` enum (`.winampClassic`, `.neoAero`, `.indigoTeal`, `.wszSkin`) with `Codable` conformance — `.wszSkin` is a v2 placeholder with zero implementation
- `ManzoVisualStyle` struct with `Codable` conformance, three independent axes, and `static let default`
- `ManzoVisualStyle.load()` returns `.default` on missing or corrupt UserDefaults data
- `ManzoVisualStyle.save()` encodes to JSON and writes to `UserDefaults` under `"ManzoVisualStyle"` key
- Model-only file — no layer construction, no color values, no AppKit drawing

### NeoAeroLayer.swift
- `NeoAeroLayerFactory.make(style:bounds:)` — full 5-layer stack: base (CAGradientLayer) + specular (CAGradientLayer, top 52%, 3-stop) + lowerGlow (CAGradientLayer, bottom 25%) + rim (CALayer, 0.5pt inset) in container (CALayer, cornerRadius=10, masksToBounds=true)
- `NeoAeroLayerFactory.makeSimplified(style:bounds:)` — 2-layer stack: base + rim only, cornerRadius=0 (for `.bodyFocus` 14pt panels)
- Private `Palette` struct and `palette(for:)` helper — clean separation of color data from layer construction
- All 3 active P3 palettes: `.winampClassic` (dark navy/indigo), `.neoAero` (aqua-teal, outside sRGB), `.indigoTeal` (deep navy, ice blue specular)
- `.wszSkin` falls through to `.winampClassic` — v2 placeholder
- `container.shouldRasterize = true` + `container.rasterizationScale = 2.0` on both `make()` and `makeSimplified()` (D-08, VIS-04)
- Container tagged `"NeoAeroContainer"` via `setValue(_:forKey:)` for layer-removal in Plan 02

## Verification

All plan verification checks passed:

1. `xcodebuild BUILD SUCCEEDED` — no errors, no warnings on new files
2. `struct ManzoVisualStyle: Codable` — present
3. `struct NeoAeroLayerFactory` — present
4. `grep -c "CGColor(red:" NeoAeroLayer.swift` → 0 (no sRGB colors)
5. `grep -c "CGColor(red:" ManzoVisualStyle.swift` → 0
6. `rasterizationScale = 2.0` present twice (once per factory function)

## Deviations from Plan

None — plan executed exactly as written.

The plan spec matched the spike references and CONTEXT.md decisions exactly. No bugs, no missing dependencies, no architectural surprises. The `private Palette` struct (discretionary implementation detail per CONTEXT.md "Claude's Discretion" section) was the only implementation choice not explicitly prescribed — it cleanly encapsulates per-theme color tuples and avoids code duplication across palette cases.

## Known Stubs

None. This plan creates foundational data models and a factory. No data flows to UI rendering yet — that wiring happens in Plan 02 (ManzoRootView.applyStyle) and Plan 03 (AppDelegate). The factory functions are complete and correct; they just haven't been called yet.

## Threat Surface Scan

No new security-relevant surface introduced. Files are pure model/factory with no network endpoints, no file access, no auth paths. UserDefaults write is the only external effect — already covered in the threat model (T-06-01: worst case = wrong theme on corrupt data, `.default` returned).

## Self-Check: PASSED

| Check | Result |
|-------|--------|
| ManzoApp/ManzoApp/ManzoVisualStyle.swift | FOUND |
| ManzoApp/ManzoApp/NeoAeroLayer.swift | FOUND |
| .planning/phases/06-neo-aero-visual-stack/06-01-SUMMARY.md | FOUND |
| Commit d1376d2 (ManzoVisualStyle) | FOUND |
| Commit 8edcbd2 (NeoAeroLayer) | FOUND |
