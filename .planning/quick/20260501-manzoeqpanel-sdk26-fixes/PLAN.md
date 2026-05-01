---
slug: manzoeqpanel-sdk26-fixes
status: in_progress
created: "2026-05-01"
---

# Fix ManzoEQPanel.swift macOS 26 SDK breakages

Fix 3 compile errors introduced by macOS 26 SDK changes:

1. Line 167: `NSView.tag` is get-only → add `var bandIndex: Int = 0` to VerticalDBSlider, replace `s.tag = i` with `s.bandIndex = i`
2. Line 763: `CGColor.copy(alpha:)` removed → replace `EQColor.curveFill.copy(alpha: 0.02)!` with `EQColor.curveFill.withAlphaComponent(0.02).cgColor`

Files: ManzoApp/ManzoApp/ManzoEQPanel.swift
