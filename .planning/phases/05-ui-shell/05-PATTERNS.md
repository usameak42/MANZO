# Phase 5: UI Shell - Pattern Map

**Mapped:** 2026-04-23
**Files analyzed:** 4 (2 new Swift files, 1 modified Swift file, 1 verified config file)
**Analogs found:** 3 / 4

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `ManzoApp/ManzoApp/ManzoWindow.swift` | model/config (NSWindow subclass) | request-response (key/main event routing) | `ManzoApp/ManzoApp/AppDelegate.swift` — window-adjacent setup conventions | partial |
| `ManzoApp/ManzoApp/ManzoRootView.swift` | component (NSVisualEffectView subclass) | event-driven (mouseDown drag) | `ManzoApp/ManzoApp/AppDelegate.swift` — code-only UI construction, NSLog diagnostics | partial |
| `ManzoApp/ManzoApp/AppDelegate.swift` (modify) | controller (app lifecycle) | request-response | self — already the canonical pattern | exact |
| `ManzoApp/project.yml` (verify only) | config | n/a | self — sources glob auto-includes new `.swift` files; no edit required | exact |

---

## Pattern Assignments

### `ManzoApp/ManzoApp/ManzoWindow.swift` (NSWindow subclass, request-response)

**Analog:** `ManzoApp/ManzoApp/AppDelegate.swift`

**Imports pattern** (AppDelegate.swift lines 1):
```swift
import AppKit
```
Single `import AppKit` — no Foundation, no UIKit. All new Swift files follow this minimal import style.

**Class declaration pattern** (AppDelegate.swift lines 3):
```swift
@objc class AppDelegate: NSObject, NSApplicationDelegate {
```
Phase 5 does NOT need `@objc` on `ManzoWindow` because it is not bridged to Objective-C via a selector. Use plain `class ManzoWindow: NSWindow`.

**Diagnostic logging pattern** (AppDelegate.swift lines 42, 50, 52, 67):
```swift
NSLog("MANZO Phase 3: playback started — \(firstPath)")
NSLog("MANZO Phase 3: manzo_play failed with code \(playResult) — \(firstPath)")
```
All diagnostic output uses `NSLog(...)` with a `"MANZO Phase N: ..."` prefix. Phase 5 log lines should read `"MANZO Phase 5: ..."`.

**Constants pattern** (AppDelegate.swift lines 13-15):
```swift
private let MANZO_STATE_PLAYING: Int32 = 1
private let MANZO_STATE_PAUSED:  Int32 = 2
private let MANZO_STATE_STOPPED: Int32 = 3
```
Constants are `private let` at class scope with explicit type annotation. Phase 5 window/layout constants follow the same pattern using `CGFloat`:
```swift
private let kWindowWidth:  CGFloat = 275
private let kWindowHeight: CGFloat = 116
```

**Core NSWindow subclass pattern** (from spike-findings-MANZO/references/window-glass-architecture.md):
```swift
// D-03: styleMask = [.borderless] — fixed size, no traffic lights.
// D-04: isOpaque + backgroundColor MUST be set before orderFront (compositor landmine).
// D-06: canBecomeKey/canBecomeMain — mandatory for .borderless keyboard event routing (spike 006).
// Minimum deployment: macOS 26. No #available fallback to macOS 15.
class ManzoWindow: NSWindow {
    override var canBecomeKey:  Bool { true }
    override var canBecomeMain: Bool { true }
}

// Window construction (called from AppDelegate):
let window = ManzoWindow(
    contentRect: NSRect(x: 0, y: 0, width: kWindowWidth, height: kWindowHeight),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
window.isOpaque        = false          // D-04: before orderFront — mandatory
window.backgroundColor = .clear        // D-04: before orderFront — mandatory
window.hasShadow       = true          // D-05
window.collectionBehavior = [.canJoinAllSpaces, .stationary]  // D-05: opt out Stage Manager
```

**No error handling needed** — `ManzoWindow` has no failable operations. The guard/NSLog pattern from AppDelegate is not required here.

---

### `ManzoApp/ManzoApp/ManzoRootView.swift` (NSVisualEffectView subclass, event-driven)

**Analog:** `ManzoApp/ManzoApp/AppDelegate.swift` (code-only AppKit construction style)

**Imports pattern** (AppDelegate.swift line 1):
```swift
import AppKit
```

**Constants pattern** — layout constants at file or class scope, `private let`, explicit `CGFloat`:
```swift
private let kTitleBarHeight:  CGFloat = 14   // Winamp draw_tbar() update_area(0,0,275,14)
private let kStatusBarHeight: CGFloat = 14   // symmetric with title bar
private let kBodyHeight:      CGFloat = 88   // kWindowHeight − kTitleBarHeight − kStatusBarHeight
```

**NSLog diagnostic pattern** (AppDelegate.swift lines 50, 67):
```swift
NSLog("MANZO Phase 5: ManzoRootView initialized")
```

**Core NSVisualEffectView subclass pattern** (from spike-findings-MANZO/references/window-glass-architecture.md + CONTEXT.md D-07, D-09, D-10):
```swift
// D-01: Liquid Glass material — macOS 26 SDK name unconfirmed.
// Day-one action: 30-min Xcode prototype on macOS 26 SDK to find correct case.
// Expected: .glass or similar. Update ONLY this constant when confirmed.
private let ManzoGlassMaterial: NSVisualEffectView.Material = /* TBD: .glass */

class ManzoRootView: NSVisualEffectView {
    // D-08/D-09: Three structural NSViews — NOT NSVisualEffectView (spike 007 rule).
    let titleView  = NSView()
    let bodyView   = NSView()
    let statusView = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        // D-07: single root .behindWindow — the ONLY NSVisualEffectView in this window.
        material     = ManzoGlassMaterial
        blendingMode = .behindWindow
        state        = .active
        wantsLayer   = true
        layer?.cornerRadius = 0   // D-07: rectangular in Phase 5; Phase 6 may add radius

        setupPanels()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used — code-only UI") }
}
```

**Panel setup pattern** (Auto Layout, NSLayoutAnchor — D-10):
```swift
private func setupPanels() {
    for panel in [titleView, bodyView, statusView] {
        panel.translatesAutoresizingMaskIntoConstraints = false  // D-10: Auto Layout
        panel.wantsLayer = true        // D-09: CALayer backing
        panel.isOpaque   = false       // D-09: transparent
        // D-09: plain CALayer() — Phase 6 inserts CAGradientLayer sublayers here.
        // Do NOT set sublayers, backgroundColor, or specialized layer type in Phase 5.
        addSubview(panel)
    }

    NSLayoutConstraint.activate([
        // titleView — top 14 pt strip
        titleView.leadingAnchor.constraint(equalTo: leadingAnchor),
        titleView.trailingAnchor.constraint(equalTo: trailingAnchor),
        titleView.topAnchor.constraint(equalTo: topAnchor),
        titleView.heightAnchor.constraint(equalToConstant: kTitleBarHeight),

        // statusView — bottom 14 pt strip
        statusView.leadingAnchor.constraint(equalTo: leadingAnchor),
        statusView.trailingAnchor.constraint(equalTo: trailingAnchor),
        statusView.bottomAnchor.constraint(equalTo: bottomAnchor),
        statusView.heightAnchor.constraint(equalToConstant: kStatusBarHeight),

        // bodyView — fills between title and status
        bodyView.leadingAnchor.constraint(equalTo: leadingAnchor),
        bodyView.trailingAnchor.constraint(equalTo: trailingAnchor),
        bodyView.topAnchor.constraint(equalTo: titleView.bottomAnchor),
        bodyView.bottomAnchor.constraint(equalTo: statusView.topAnchor),
    ])
}
```

**Drag pattern** (CONTEXT.md D-11, UI-SPEC.md Drag Interaction Contract):
```swift
override func mouseDown(with event: NSEvent) {
    // D-11: Full-chrome drag — matches Winamp main_nonclient.cpp return HTCLIENT for all pixels.
    // Interactive controls added in Phase 6+ consume mouseDown in their own subviews first;
    // drag falls through naturally to unoccupied chrome only.
    window?.performDrag(with: event)
}
```

---

### `ManzoApp/ManzoApp/AppDelegate.swift` (modify — add window wiring)

**Analog:** self — existing `applicationDidFinishLaunching` is the insertion point.

**Existing function structure** (AppDelegate.swift lines 28-68):
```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    // ... existing Phase 3 audio setup ...
    // Phase 5 window setup APPENDED after audio setup:
}
```

**Window wiring addition pattern** — append to `applicationDidFinishLaunching` after existing audio code:
```swift
// Phase 5: create and show the main window.
// D-04: isOpaque + backgroundColor set on ManzoWindow init — before orderFront.
let window = ManzoWindow(
    contentRect: NSRect(x: 0, y: 0, width: kWindowWidth, height: kWindowHeight),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
let rootView = ManzoRootView(frame: window.contentView!.bounds)
window.contentView = rootView

// D-12: single call — AppKit saves frame on move and restores on next launch automatically.
window.setFrameAutosaveName("ManzoMainWindow")
window.center()
window.orderFront(nil)    // D-04: isOpaque/backgroundColor already set before this call
NSLog("MANZO Phase 5: window ordered front — 275×116 pt frameless")
```

**Existing `applicationShouldTerminateAfterLastWindowClosed` pattern** (AppDelegate.swift line 82-84) — RETAIN unchanged:
```swift
func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
}
```
This already provides correct window-close-quits-app behavior — no modification needed.

**State storage pattern** (AppDelegate.swift lines 8, 24) — window reference follows same instance variable pattern:
```swift
private var manzoWindow: ManzoWindow? = nil   // keeps window alive for app lifetime
```

---

### `ManzoApp/project.yml` (verify only — no edit expected)

**Analog:** self — existing `sources` entry uses a directory-level path glob.

**Existing sources entry** (project.yml lines 43-46):
```yaml
sources:
  - path: ManzoApp
    excludes:
      - "*.yml"
```

This glob auto-includes all `.swift` files placed anywhere under `ManzoApp/ManzoApp/`. New files `ManzoWindow.swift` and `ManzoRootView.swift` placed in `ManzoApp/ManzoApp/` are automatically picked up. **No edit required.** Verify with `xcodegen generate` after file creation to confirm Xcode project regenerates cleanly.

**Deployment target note** (project.yml lines 5, 31): Current yml sets `macOS: "15.0"`. CONTEXT.md D-02 declares macOS 26 as the minimum for Phase 5. Update `deploymentTarget.macOS` and `MACOSX_DEPLOYMENT_TARGET` and `LSMinimumSystemVersion` to `"26.0"` when the macOS 26 SDK string is confirmed.

---

## Shared Patterns

### Diagnostic Logging
**Source:** `ManzoApp/ManzoApp/AppDelegate.swift` lines 42, 50-52, 67, 97, 107-108
**Apply to:** All new Swift files (`ManzoWindow.swift`, `ManzoRootView.swift`, additions to `AppDelegate.swift`)
```swift
NSLog("MANZO Phase 5: <descriptive message>")
```
- Prefix is always `"MANZO Phase N: "` where N matches the current phase number.
- No `print()`, no `os_log`, no `Logger` — `NSLog` is the established convention.
- Log all significant lifecycle events: window creation, contentView assignment, orderFront, setFrameAutosaveName.

### Code-Only UI Construction
**Source:** `ManzoApp/ManzoApp/AppDelegate.swift` (entire file — no NIB/storyboard references)
**Apply to:** `ManzoWindow.swift`, `ManzoRootView.swift`
- No `@IBOutlet`, no `@IBAction`, no `NSCoder` path used.
- `required init?(coder:)` should be included but call `fatalError("init(coder:) not used — code-only UI")`.
- All subview creation, constraint setup, and property assignment happens programmatically.

### Private Let Constants Pattern
**Source:** `ManzoApp/ManzoApp/AppDelegate.swift` lines 13-15
**Apply to:** `ManzoWindow.swift` (window dims), `ManzoRootView.swift` (panel heights)
```swift
private let kConstantName: ExplicitType = value
```
- Explicit type annotation on all constants.
- `k`-prefix for layout/dimension constants (Swift convention consistent with CONTEXT.md specifics section).
- `private` access — no cross-file constant sharing needed in Phase 5.

### No Error Handling / Guard Pattern for Pure AppKit API
**Source:** `ManzoApp/ManzoApp/AppDelegate.swift` lines 40-55 — guard+NSLog used only for fallible FFI calls
**Apply to:** `ManzoWindow.swift`, `ManzoRootView.swift`
- `ManzoWindow` init and `ManzoRootView` setup have no failable operations — no guard/throw needed.
- `guard`+`NSLog` pattern from AppDelegate is for FFI `manzo_*` calls only; do not replicate for pure AppKit construction.

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| (none) | — | — | All Phase 5 files have AppKit construction patterns available from AppDelegate.swift. NSWindow subclass and NSVisualEffectView subclass patterns are supplemented by spike-findings-MANZO canonical excerpts. |

---

## Metadata

**Analog search scope:** `ManzoApp/ManzoApp/` (all `.swift` files), `.claude/skills/spike-findings-MANZO/references/`
**Files scanned:** 4 (AppDelegate.swift, main.swift, project.yml, window-glass-architecture.md)
**Pattern extraction date:** 2026-04-23
