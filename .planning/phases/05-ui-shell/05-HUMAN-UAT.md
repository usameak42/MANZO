---
status: partial
phase: 05-ui-shell
source: [05-VERIFICATION.md]
started: 2026-04-23T23:40:00Z
updated: 2026-04-23T23:40:00Z
---

## Current Test

[pending human testing]

## Tests

### 1. Frameless window with OS vibrancy
expected: App launches showing a 275×116 pt window with no system chrome (no title bar, no traffic-light buttons) and visible OS blur/vibrancy behind the glass surface — NOT a solid rectangle.
result: [pending]

### 2. Full-chrome drag
expected: Clicking anywhere on the glass surface and dragging moves the window with the cursor. No subview accidentally blocks mouseDown propagation to performDrag.
result: [pending]

### 3. Position persistence across relaunches
expected: Drag window to a non-default corner, quit (Cmd-Q), relaunch — window reappears at the same position, NOT centered. Verifies setFrameAutosaveName UserDefaults round-trip.
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
