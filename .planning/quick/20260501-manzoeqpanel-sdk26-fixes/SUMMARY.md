---
slug: manzoeqpanel-sdk26-fixes
status: complete
completed: "2026-05-01"
---

# Summary

Fixed 3 ManzoEQPanel.swift compile errors caused by macOS 26 SDK breaking changes.

## Fixes Applied

1. **Line 167 — NSView.tag get-only**: Added `var bandIndex: Int = 0` to `VerticalDBSlider`; replaced `s.tag = i` with `s.bandIndex = i`.
2. **Line 763 — CGColor.copy(alpha:) removed**: Replaced `EQColor.curveFill.copy(alpha: 0.02)!` with `EQColor.curveFill.withAlphaComponent(0.02).cgColor`. Root cause: macOS 26 removed `CGColor.copy(alpha:)`, leaving only the `NSCopying.copy()` method (no args, returns `Any`).

## Build Result

** BUILD SUCCEEDED ** (warnings only, no errors)
