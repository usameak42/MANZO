---
phase: 05-ui-shell
verified: 2026-04-23T21:00:00Z
status: human_needed
score: 7/7 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Launch app and confirm frameless window with vibrancy"
    expected: "275x116 pt window appears with no title bar, no traffic-light buttons, OS blur/vibrancy visible behind the glass — not a solid rectangle"
    why_human: "NSVisualEffectView blending mode and material rendering cannot be verified by grep or build alone — requires visual inspection on a running display"
  - test: "Drag the window by clicking anywhere on the glass chrome"
    expected: "Window moves with cursor when clicked anywhere on the 275x116 pt surface (no controls exist yet to block drag)"
    why_human: "performDrag(with:) wiring is verified in code, but actual drag behavior requires a running app and user interaction"
  - test: "Window position persists across relaunches"
    expected: "Drag window to a non-default position, quit (Cmd-Q), relaunch — window reappears at the same position, not centered"
    why_human: "setFrameAutosaveName is called after orderFront (verified in code), but UserDefaults round-trip requires a running app restart cycle"
---

# Phase 5: UI Shell Verification Report

**Phase Goal:** The app presents a frameless NSWindow with a single-root `.behindWindow` vibrancy view, a custom drag region, and persistent window position — all inner panels are CALayer-only.
**Verified:** 2026-04-23T21:00:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | ManzoWindow subclass overrides canBecomeKey and canBecomeMain to return true | VERIFIED | `ManzoWindow.swift:21-22` — `override var canBecomeKey: Bool { true }` / `override var canBecomeMain: Bool { true }` |
| 2 | Window style mask is [.borderless] — no title bar, no traffic-light buttons | VERIFIED | `ManzoWindow.swift:31` — `styleMask: [.borderless]`. No `.resizable` found anywhere in the file |
| 3 | Exactly one NSVisualEffectView with .behindWindow blending exists (ManzoRootView); no others are created | VERIFIED | `blendingMode = .behindWindow` on line 48 of ManzoRootView.swift. NSVisualEffectView appears only in ManzoRootView.swift (class declaration, type annotation, comments) — zero occurrences in ManzoWindow.swift, AppDelegate.swift, main.swift |
| 4 | All three inner panels (titleView, bodyView, statusView) are plain NSView with wantsLayer=true and isOpaque=false — not NSVisualEffectView | VERIFIED | Lines 37-39: `let titleView = NSView()`, `let bodyView = NSView()`, `let statusView = NSView()`. `panel.wantsLayer = true` on line 68. `panel.isOpaque = false` assignment correctly absent (NSView.isOpaque is get-only in macOS 26.4 SDK; NSView defaults to transparent when wantsLayer=true with no backgroundColor — documented in comment lines 69-71) |
| 5 | mouseDown on ManzoRootView calls window?.performDrag(with:) making the full chrome draggable | VERIFIED | `ManzoRootView.swift:105-106` — `override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }`. No `super.mouseDown` call. No hit-test exclusions |
| 6 | ManzoGlassMaterial is a named constant — single update site for when macOS 26 SDK confirms the case name | VERIFIED | `ManzoRootView.swift:27` — `private let ManzoGlassMaterial: NSVisualEffectView.Material = .hudWindow // TBD: replace .hudWindow with confirmed .glass case name` |
| 7 | setFrameAutosaveName is called after orderFront in AppDelegate | VERIFIED | `AppDelegate.swift:80` — `window.orderFront(nil)`; `AppDelegate.swift:83` — `window.setFrameAutosaveName("ManzoMainWindow")`. orderFront on line 80, autosave on line 83 — correct ordering per D-12 |

**Score:** 7/7 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `ManzoApp/ManzoApp/ManzoWindow.swift` | NSWindow subclass with borderless config, canBecomeKey/canBecomeMain overrides | VERIFIED | 46-line file; single `import AppKit`; private kWindowWidth/kWindowHeight constants; canBecomeKey/canBecomeMain overrides; styleMask=[.borderless]; isOpaque=false and backgroundColor=.clear set inside init() body before any orderFront call |
| `ManzoApp/ManzoApp/ManzoRootView.swift` | NSVisualEffectView subclass with glass material, three panel NSViews, drag handler | VERIFIED | 108-line file; ManzoGlassMaterial constant; blendingMode=.behindWindow; state=.active; wantsLayer=true; cornerRadius=0; three NSView panels with 12 NSLayoutAnchor constraints; mouseDown delegates to performDrag |
| `ManzoApp/ManzoApp/AppDelegate.swift` | Window construction, contentView assignment, orderFront, setFrameAutosaveName | VERIFIED | manzoWindow ivar on line 28; window setup block lines 76-85; ManzoWindow() constructed, ManzoRootView(frame:) set as contentView, center(), orderFront(nil), setFrameAutosaveName("ManzoMainWindow"), retained in manzoWindow ivar; all Phase 3 audio code preserved |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| ManzoWindow | NSWindow | `class ManzoWindow: NSWindow` | WIRED | ManzoWindow.swift:17 |
| ManzoRootView | NSVisualEffectView | `class ManzoRootView: NSVisualEffectView` | WIRED | ManzoRootView.swift:33 |
| ManzoRootView.mouseDown | window.performDrag | `override func mouseDown(with event: NSEvent)` | WIRED | ManzoRootView.swift:105-106 — single-line body, no super call, no exclusions |
| AppDelegate | ManzoWindow() | `let window = ManzoWindow()` | WIRED | AppDelegate.swift:76 |
| AppDelegate | ManzoWindow (retained) | `private var manzoWindow: ManzoWindow? = nil` | WIRED | AppDelegate.swift:28; assigned on line 84 — ARC retention confirmed |
| window.setFrameAutosaveName | UserDefaults (AppKit built-in) | `setFrameAutosaveName("ManzoMainWindow")` | WIRED | AppDelegate.swift:83, called after orderFront on line 80 |

---

### Data-Flow Trace (Level 4)

Not applicable. Phase 5 produces no dynamic data rendering — ManzoRootView and panel NSViews are structural containers with empty layer trees. No state variables, no fetch, no store. Data-flow trace is irrelevant for a structural shell phase.

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Xcode project builds without errors | `xcodebuild -project ManzoApp.xcodeproj -scheme ManzoApp -configuration Debug build` | `BUILD SUCCEEDED` | PASS |
| ManzoWindow and ManzoRootView referenced in project.pbxproj | (auto-included via xcodegen sources glob `path: ManzoApp`) | Both files exist in `ManzoApp/ManzoApp/` and xcodegen glob auto-includes all `.swift` files | PASS |
| Constraint count exactly 12 | `grep -c "constraint(" ManzoRootView.swift` | `12` — 4 per panel (titleView: leading+trailing+top+height, statusView: leading+trailing+bottom+height, bodyView: leading+trailing+top+bottom) | PASS |
| No .resizable in styleMask | `grep "resizable" ManzoWindow.swift` | No output — absent | PASS |
| No nested NSVisualEffectView instantiation | `grep "NSVisualEffectView()" ManzoRootView.swift` | No output — absent | PASS |
| No super.mouseDown in drag handler | `grep "super.mouseDown" ManzoRootView.swift` | No output — absent | PASS |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| SHELL-01 | 05-01-PLAN, 05-02-PLAN | App presents a single frameless NSWindow with a custom drag region for the title bar | SATISFIED | `ManzoWindow.swift:31` — `styleMask: [.borderless]`; no `.resizable`; canBecomeKey/canBecomeMain overrides present |
| SHELL-02 | 05-01-PLAN, 05-02-PLAN | Window composites one root `.behindWindow` NSVisualEffectView; no nested vibrancy views | SATISFIED | `blendingMode = .behindWindow` in ManzoRootView only; NSVisualEffectView appears in no other Swift file; inner panels are `NSView()` not NSVisualEffectView |
| SHELL-03 | 05-01-PLAN, 05-02-PLAN | All inner panels are CALayer-only with `isOpaque = false`; no nested NSVisualEffectView | SATISFIED | All three panels are `NSView()` with `wantsLayer = true`; `isOpaque` assignment omitted (get-only, transparent by default); no backgroundColor set on any panel; no sublayers added |
| SHELL-04 | 05-01-PLAN, 05-02-PLAN | User can drag the window by clicking non-interactive chrome areas | SATISFIED (code) / NEEDS HUMAN (behavior) | `window?.performDrag(with: event)` in mouseDown override — wiring verified; actual drag behavior requires running app |
| SHELL-05 | 05-02-PLAN | App restores window position and size between launches via UserDefaults | SATISFIED (code) / NEEDS HUMAN (behavior) | `setFrameAutosaveName("ManzoMainWindow")` called after `orderFront` on AppDelegate lines 80/83; actual persistence requires relaunch cycle |

All 5 SHELL requirements claimed by the plans are accounted for. No orphaned requirements found — REQUIREMENTS.md maps exactly SHELL-01 through SHELL-05 to Phase 5.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| ManzoRootView.swift | 27 | `ManzoGlassMaterial = .hudWindow // TBD` | INFO | Intentional placeholder — macOS 26 SDK Liquid Glass case name unconfirmed at implementation time. Named constant ensures single update site. Renders as hudWindow blur (existing AppKit material) until updated. Not a stub — visual output is real, material name will be refined |

No blocker or warning anti-patterns found. The `.hudWindow` placeholder is documented, intentional, and explicitly carries forward per the plan's threat model (T-05-02: accepted).

---

### Human Verification Required

#### 1. Frameless window with OS vibrancy effect

**Test:** Build and run the app (`open <DerivedData path>/ManzoApp.app`). Confirm the window has no system chrome — no title bar, no traffic-light close/minimize/zoom buttons. Confirm the window background shows blurred desktop content (OS vibrancy/blur behind it), not a solid rectangle.
**Expected:** Small (~275x116 pt) frameless window with visible OS blur behind the glass surface.
**Why human:** NSVisualEffectView blending mode and material rendering cannot be verified by grep or build check — requires visual inspection on a running macOS display.

#### 2. Full-chrome drag

**Test:** Click anywhere on the glass window surface (not on a subview) and drag. The window should move with the cursor.
**Expected:** Window tracks cursor movement from any click point on the 275x116 pt chrome. No click target fails to initiate drag.
**Why human:** `performDrag(with:)` wiring is confirmed in code, but the actual drag behavior — including that no subview accidentally consumes mouseDown and blocks drag — requires a running app with user interaction.

#### 3. Window position persistence across relaunches

**Test:** (a) Drag the window to a non-default position (e.g., top-right corner of screen). (b) Quit the app (Cmd-Q or close window). (c) Relaunch the app.
**Expected:** Window reappears at the same position as when it was quit — not at the center of the screen.
**Why human:** `setFrameAutosaveName("ManzoMainWindow")` is called after `orderFront` (verified in code), but the UserDefaults save/restore round-trip requires a full quit-and-relaunch cycle that cannot be exercised by static analysis.

---

### Gaps Summary

No gaps found. All 7 observable truths are VERIFIED. All 3 required artifacts exist, are substantive, and are wired. All 5 SHELL requirements are satisfied at the code level. Build succeeds cleanly.

The 3 human verification items represent standard visual/behavioral tests that cannot be verified by static analysis — they are not blockers, but the status is `human_needed` pending sign-off.

---

_Verified: 2026-04-23T21:00:00Z_
_Verifier: Claude (gsd-verifier)_
