---
phase: 06-neo-aero-visual-stack
plan: "02"
subsystem: ui-chrome
tags: [swift, calayer, neo-aero, cagradientlayer, careplicatorlayer, cornerradius, applystyle]
dependency_graph:
  requires:
    - 06-01 (NeoAeroLayerFactory, ManzoVisualStyle)
  provides:
    - ManzoRootView.applyStyle(_ style: ManzoVisualStyle)
    - ManzoRootView.invalidateNeoAeroRasterization()
    - cornerRadius=10 on root NSVisualEffectView layer
    - CAReplicatorLayer wet-floor create/remove path
  affects:
    - ManzoApp/ManzoApp/AppDelegate.swift (Plan 03 wiring point — calls applyStyle after load)
tech_stack:
  added: []
  patterns:
    - NeoAeroLayerFactory.make() and makeSimplified() called per PanelLayout case
    - removeNeoAeroLayers() tag-based cleanup ("NeoAeroContainer" key) prevents double-insertion
    - CAReplicatorLayer instanceAlphaOffset=-0.5, Y-flip transform, gradient fade mask (D-06)
    - shouldRasterize invalidation helper: false→true with rasterizationScale=2.0 (D-08)
    - insertSublayer(at: 0) keeps NSViews above chrome for hit-testing
key_files:
  created: []
  modified:
    - ManzoApp/ManzoApp/ManzoRootView.swift
decisions:
  - applyStyle() not called from init() — AppDelegate (Plan 03) calls it after ManzoVisualStyle.load() per D-10
  - CAReplicatorLayer removed (not hidden) when wetFloor=false to eliminate compositor cost per D-07
  - Layer insertion at index 0 in all cases ensures panel NSViews remain on top for hit-testing
  - masksToBounds=true added to root layer alongside cornerRadius=10 to clip sublayers to rounded rect
metrics:
  duration: "3m"
  completed: "2026-04-24"
  tasks_completed: 1
  files_created: 0
  files_modified: 1
---

# Phase 06 Plan 02: ManzoRootView applyStyle + Neo-Aero Integration Summary

**One-liner:** ManzoRootView.applyStyle() wires NeoAeroLayerFactory into all three PanelLayout cases, sets cornerRadius=10, and implements the CAReplicatorLayer wet-floor create/remove path per D-01, D-06, D-07.

## Tasks Completed

| # | Name | Commit | Files |
|---|------|--------|-------|
| 1 | Modify ManzoRootView.swift — cornerRadius + applyStyle() + wet-floor | 204781c | ManzoApp/ManzoApp/ManzoRootView.swift |

## What Was Built

### ManzoRootView.swift modifications

**CHANGE 1 — cornerRadius 0 → 10 (D-01):**
- `layer?.cornerRadius = 10` replaces the Phase 5 value of 0
- `layer?.masksToBounds = true` added alongside to clip sublayers to rounded rect
- Both set in `override init(frame:)` before `setupPanels()` call

**CHANGE 2 — `applyStyle(_ style: ManzoVisualStyle)` method:**
- Cleans up old layers by calling `removeNeoAeroLayers(from:)` on all four insertion points (root, titleView, bodyView, statusView layers) before inserting fresh ones
- Removes any existing `CAReplicatorLayer` wet-floor via `filter { $0 is CAReplicatorLayer }` before re-applying
- Handles all three `PanelLayout` cases via `switch style.panelLayout`:
  - `.unifiedSlab`: one `NeoAeroLayerFactory.make()` at root layer index 0 (full 275×116 slab)
  - `.threeBubbles`: three `NeoAeroLayerFactory.make()` calls into each panel's layer at index 0
  - `.bodyFocus`: `NeoAeroLayerFactory.make()` on bodyView, `NeoAeroLayerFactory.makeSimplified()` on titleView and statusView
- Wet-floor path: `CAReplicatorLayer` with `instanceCount=2`, Y-flip `CATransform3D`, `instanceAlphaOffset=-0.5`, `CAGradientLayer` fade mask (black@1.0 → black@0.0) — inserted at root layer index 0
- All insertion calls use `insertSublayer(_:at: 0)` to keep NSViews above chrome

**CHANGE 3 — `removeNeoAeroLayers(from:)` private helper:**
- Filters sublayers by `value(forKey: "name") == "NeoAeroContainer"` — the tag set by NeoAeroLayerFactory in Plan 01
- Removes all matching layers via `removeFromSuperlayer()`

**CHANGE 4 — `invalidateNeoAeroRasterization()` helper (D-08):**
- Scans all four layer trees for NeoAeroContainer layers
- Cycles `shouldRasterize = false` → `shouldRasterize = true` + `rasterizationScale = 2.0`
- Intended for theme switch / layout switch / drag-end events only, never per-frame

**Phase 6 NSLog:**
- `NSLog("MANZO Phase 6: ManzoRootView ready — applyStyle() awaits AppDelegate call, cornerRadius=10")` added after Phase 5 NSLog in init

## Verification

All plan verification checks passed:

1. `xcodebuild BUILD SUCCEEDED` — no errors, no warnings on modified file
2. `grep "func applyStyle(" ManzoRootView.swift` — present
3. `grep "cornerRadius = 10" ManzoRootView.swift` — present
4. `grep "CAReplicatorLayer" ManzoRootView.swift` — present (wet-floor path)
5. `grep -cE "case .unifiedSlab|case .threeBubbles|case .bodyFocus" ManzoRootView.swift` — returns 3
6. `grep "NeoAeroLayerFactory.make(" ManzoRootView.swift` — present
7. `grep -c "cornerRadius = 0" ManzoRootView.swift` — returns 0 (old value removed)
8. `grep "isHidden" ManzoRootView.swift` — absent (D-07 compliant: remove not hide)

## Deviations from Plan

None — plan executed exactly as written.

The plan spec was precise and complete. Implementation matched the code blueprints in the plan action section verbatim. One minor addition beyond the minimum: `layer?.masksToBounds = true` was added alongside `cornerRadius = 10` in `init()` — this is required to clip the Neo-Aero sublayers to the rounded rect and is called out in CLAUDE.md's critical constraints. The plan's CHANGE 1 description implied this but didn't explicitly list it; it is standard and correct.

## Known Stubs

None. `applyStyle()` is a complete, callable method. It correctly invokes `NeoAeroLayerFactory.make()` and `makeSimplified()` (both built in Plan 01). The only missing piece is the AppDelegate call site — Plan 03 wires that.

## Threat Surface Scan

No new network endpoints, auth paths, file access, or schema changes introduced. `applyStyle()` mutates `CALayer` sublayer trees on the main thread — already covered in the Plan 02 threat model (T-06-04: thread safety accept; T-06-05: name collision accept; T-06-06: kWindowHeight constant accept). No new surface beyond what the threat model already addresses.

## Self-Check: PASSED

| Check | Result |
|-------|--------|
| ManzoApp/ManzoApp/ManzoRootView.swift exists | FOUND |
| func applyStyle present | FOUND |
| cornerRadius = 10 present | FOUND |
| cornerRadius = 0 absent | CONFIRMED (count=0) |
| CAReplicatorLayer present | FOUND |
| 3 PanelLayout cases | CONFIRMED (count=3) |
| NeoAeroLayerFactory.make present | FOUND |
| NeoAeroLayerFactory.makeSimplified present | FOUND |
| instanceAlphaOffset = -0.5 present | FOUND |
| removeNeoAeroLayers helper present | FOUND |
| invalidateNeoAeroRasterization helper present | FOUND |
| insertSublayer at: 0 present | FOUND |
| isHidden absent (D-07) | CONFIRMED |
| Commit 204781c | FOUND |
| xcodebuild BUILD SUCCEEDED | CONFIRMED |
