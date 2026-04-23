---
phase: 05-ui-shell
reviewed: 2026-04-23T00:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - ManzoApp/ManzoApp/ManzoWindow.swift
  - ManzoApp/ManzoApp/ManzoRootView.swift
  - ManzoApp/ManzoApp/AppDelegate.swift
findings:
  critical: 0
  warning: 2
  info: 3
  total: 5
status: issues_found
---

# Phase 5: Code Review Report

**Reviewed:** 2026-04-23
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

Three Swift/AppKit files implement the Phase 5 frameless NSWindow shell: `ManzoWindow`, `ManzoRootView`, and `AppDelegate`. The core architectural constraints from spikes 006 and 007 are correctly implemented — `canBecomeKey`/`canBecomeMain` overrides are present, `isOpaque = false` is set before `orderFront`, and exactly one `.behindWindow` NSVisualEffectView exists at the window root. Panel layout math (14 + 88 + 14 = 116) is consistent with the Winamp source dimensions.

Two warnings are raised: a latent force-unwrap in `AppDelegate` that is safe today but fragile under refactoring, and a frame-size mismatch when constructing `ManzoRootView`. Three info items cover a placeholder material constant, redundant centering behavior, and retained `NSLog` diagnostics that will accumulate in production logs.

No critical issues found.

---

## Warnings

### WR-01: Force-unwrap on `manzoHandle` inside nested else branch

**File:** `ManzoApp/ManzoApp/AppDelegate.swift:51`
**Issue:** `manzo_play(manzoHandle!)` force-unwraps `manzoHandle` inside the `else` branch of `if manzoHandle == nil`. While the nil check on line 48 makes this safe today, the `!` operator creates a fragile pattern: any future refactor that hoists the `manzo_play` call out of this `else` block (or restructures the guard) will produce a runtime crash with no compile-time warning. Swift's optional binding eliminates the risk entirely.
**Fix:**
```swift
// Replace lines 48-68 with optional binding:
if let handle = manzo_open(firstPath) {
    manzoHandle = handle
    let playResult = manzo_play(handle)
    if playResult == 0 {
        NSLog("MANZO Phase 3: playback started — \(firstPath)")
    } else {
        NSLog("MANZO Phase 3: manzo_play failed with code \(playResult) — \(firstPath)")
    }
    pollTimer = Timer.scheduledTimer(
        timeInterval: 0.1,
        target: self,
        selector: #selector(pollPlaybackState),
        userInfo: nil,
        repeats: true
    )
    NSLog("MANZO Phase 3: 100 ms state poll timer armed — queue size \(trackQueue.count)")
} else {
    NSLog("MANZO Phase 3: manzo_open returned null for \(firstPath)")
}
```

---

### WR-02: `ManzoRootView` initialized with `window.frame` instead of content bounds

**File:** `ManzoApp/ManzoApp/AppDelegate.swift:77`
**Issue:** `ManzoRootView(frame: window.frame)` passes the window's screen frame (origin: `(0, 0)` before `center()`, size: 275×116). AppKit repositions the `contentView` to window-local coordinates automatically, so the visual result is correct. However, `window.frame` includes any window decoration offsets (zero for `.borderless`, but non-zero for other style masks), and passing `window.frame` rather than the content bounds is semantically incorrect and will silently break if the style mask changes. The correct value is the content rect.
**Fix:**
```swift
// Replace line 77:
let rootView = ManzoRootView(frame: NSRect(origin: .zero, size: CGSize(width: kWindowWidth, height: kWindowHeight)))
// Or, generically derived from the window:
let rootView = ManzoRootView(frame: window.contentRect(forFrameRect: window.frame))
```

---

## Info

### IN-01: `.hudWindow` placeholder material will ship without a compile-time reminder

**File:** `ManzoApp/ManzoApp/ManzoRootView.swift:27`
**Issue:** `ManzoGlassMaterial` is set to `.hudWindow` as a stand-in for the unconfirmed macOS 26 Liquid Glass material name. The comment documents the TBD clearly. The risk is that this placeholder ships unmodified if the day-one prototype action is deferred — the window will show a translucent HUD appearance rather than Liquid Glass, with no build failure or runtime warning.
**Fix:** Add a compile-time `#warning` so the constant cannot be forgotten:
```swift
// Line 27 — add above or inline:
#warning("Replace .hudWindow with confirmed macOS 26 Liquid Glass material name after SDK prototype")
private let ManzoGlassMaterial: NSVisualEffectView.Material = .hudWindow
```

---

### IN-02: `window.center()` is overridden on second launch by `setFrameAutosaveName`

**File:** `ManzoApp/ManzoApp/AppDelegate.swift:79,83`
**Issue:** `center()` is called on line 79, then `setFrameAutosaveName("ManzoMainWindow")` is called on line 83. On second launch, `setFrameAutosaveName` immediately restores the saved screen position, silently discarding the result of `center()`. The comment on line 81 notes that `setFrameAutosaveName` must be called after `orderFront` — this is correct. The side effect is that `center()` is effectively a no-op after the first launch. This is harmless, but the ordering implies `center()` is authoritative when it is not.
**Fix:** No behavioral change required. Optionally, add a comment to document the first-launch-only semantics:
```swift
window.center()   // first launch only — overridden by autosave on subsequent launches
window.orderFront(nil)
window.setFrameAutosaveName("ManzoMainWindow")
```

---

### IN-03: `NSLog` diagnostic calls retained across all three files

**Files:** `ManzoApp/ManzoApp/ManzoWindow.swift:44`, `ManzoApp/ManzoApp/ManzoRootView.swift:55,97`, `ManzoApp/ManzoApp/AppDelegate.swift:45,53,55,68,85,115,125,133,141,147`
**Issue:** Fourteen `NSLog` calls spanning the three files will write to the system log on every launch, track-end event, and panel layout pass. `NSLog` is synchronous, unbuffered, and visible in Console.app by default — appropriate for a development phase, but not production. There is no build-configuration guard (`#if DEBUG`) around any of them.
**Fix:** Wrap in `#if DEBUG` or migrate to `os_log` with a subsystem/category that can be disabled at runtime:
```swift
#if DEBUG
NSLog("MANZO Phase 5: ManzoWindow initialized — 275×116 pt borderless")
#endif

// Or, preferred for production code:
import os.log
private let log = OSLog(subsystem: "com.manzo.app", category: "window")
os_log("ManzoWindow initialized — 275×116 pt borderless", log: log, type: .debug)
```

---

_Reviewed: 2026-04-23_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
