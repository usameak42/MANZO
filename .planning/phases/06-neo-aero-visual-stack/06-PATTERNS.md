# Phase 6: Neo-Aero Visual Stack - Pattern Map

**Mapped:** 2026-04-24
**Files analyzed:** 5 (3 modified + 2 new Swift files + 1 config)
**Analogs found:** 5 / 5

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `ManzoApp/ManzoApp/ManzoRootView.swift` | component | request-response | self (existing file) | exact — modify in-place |
| `ManzoApp/ManzoApp/AppDelegate.swift` | controller | request-response | self (existing file) | exact — modify in-place |
| `ManzoApp/ManzoApp/NeoAeroLayer.swift` | utility / factory | transform | spike 008 code in `neo-aero-visual-stack.md` | exact — copy directly |
| `ManzoApp/ManzoApp/ManzoVisualStyle.swift` | model | CRUD | `ManzoWindow.swift` (value-type config struct analog) | role-match |
| `ManzoApp/project.yml` | config | — | self (existing file) | exact — modify in-place |

---

## Pattern Assignments

### `ManzoApp/ManzoApp/NeoAeroLayer.swift` (utility/factory, transform)

**Analog:** `.claude/skills/spike-findings-MANZO/references/neo-aero-visual-stack.md` (spike 008/009/010 validated code)
**No existing Swift factory file exists** — this is the first one. The spike reference is the authoritative source.

**Imports pattern** — copy from every existing Swift file (lines 1 of ManzoRootView.swift / ManzoWindow.swift):
```swift
import AppKit
```
QuartzCore is part of AppKit on macOS; `CAGradientLayer`, `CAReplicatorLayer`, `CALayer` are available via `import AppKit` alone.

**P3 color construction pattern** (spike 010, neo-aero-visual-stack.md):
```swift
let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
// Usage — never use sRGB CGColor(red:green:blue:alpha:) for brand colors
let topColor    = CGColor(colorSpace: p3, components: [0.09, 0.09, 0.16, 1.0])!  // winampClassic base top
let bottomColor = CGColor(colorSpace: p3, components: [0.22, 0.22, 0.35, 1.0])!  // winampClassic base bottom
let specularColor = CGColor(colorSpace: p3, components: [0.74, 0.81, 0.84, 0.50])!  // specular @ 50%
```

**Core 5-layer factory pattern** (spike 008, neo-aero-visual-stack.md lines 12–44):
```swift
// [1] Base gradient
let base = CAGradientLayer()
base.colors = [topColor, bottomColor]
base.cornerRadius = 10
base.frame = bounds

// [2] Specular band — top 52% only
let specular = CAGradientLayer()
specular.colors   = [CGColor(gray: 1, alpha: 0.50),
                     CGColor(gray: 1, alpha: 0.08),
                     CGColor(gray: 1, alpha: 0.0)]
specular.locations = [0.0, 0.45, 1.0]
specular.frame    = CGRect(x: 0, y: 0,
                           width: bounds.width,
                           height: bounds.height * 0.52)

// [3] Lower glow — bottom 25%
let lowerGlow = CAGradientLayer()
lowerGlow.colors = [CGColor(gray: 1, alpha: 0.0),
                    CGColor(gray: 1, alpha: 0.12)]
lowerGlow.frame  = CGRect(x: 0, y: bounds.height * 0.75,
                          width: bounds.width,
                          height: bounds.height * 0.25)

// [4] Rim highlight
let rim = CALayer()
rim.frame = bounds.insetBy(dx: 0.5, dy: 0.5)
rim.cornerRadius = 9.5
rim.borderWidth  = 1.0
rim.borderColor  = CGColor(gray: 1, alpha: 0.45)

// [5] Container — clips rounded rect, caches rasterization
let container = CALayer()
container.cornerRadius    = 10
container.masksToBounds   = true
container.addSublayer(base)
container.addSublayer(specular)
container.addSublayer(lowerGlow)
container.addSublayer(rim)
container.shouldRasterize    = true
container.rasterizationScale = 2.0   // ALWAYS pair — Retina requirement (D-08)
```

**Wet-floor CAReplicatorLayer pattern** (spike 009, neo-aero-visual-stack.md lines 77–92):
```swift
let replicator = CAReplicatorLayer()
replicator.instanceCount = 2
replicator.instanceTransform = CATransform3D(
    m11: 1, m12: 0, m13: 0, m14: 0,
    m21: 0, m22: -1, m23: 0, m24: 0,    // Y-flip
    m31: 0, m32: 0, m33: 1, m34: 0,
    m41: 0, m42: windowHeight * 2, m43: 0, m44: 1  // offset below window
)
replicator.instanceAlphaOffset = -0.5   // reflection at 50% opacity

let fadeMask = CAGradientLayer()
fadeMask.colors = [CGColor(gray: 0, alpha: 1.0),
                   CGColor(gray: 0, alpha: 0.0)]
fadeMask.frame  = reflectionRect
replicator.mask = fadeMask
```

**Rasterization invalidation pattern** (D-08 — invalidate on state change only, never per-frame):
```swift
// On theme/layout switch:
container.shouldRasterize = false   // flush stale cache
container.shouldRasterize = true    // re-cache with new visual state
container.rasterizationScale = 2.0  // re-set after toggling
```

**NSLog diagnostic pattern** (project-wide convention, ManzoRootView.swift line 55 / ManzoWindow.swift line 44):
```swift
NSLog("MANZO Phase 6: NeoAeroLayerFactory.make — layout=%@, theme=%@", "\(style.panelLayout)", "\(style.colorTheme)")
```

---

### `ManzoApp/ManzoApp/ManzoVisualStyle.swift` (model, CRUD)

**Analog:** `ManzoApp/ManzoApp/ManzoWindow.swift` — nearest value-type configuration file in codebase (private constants + class with init). ManzoVisualStyle is a struct, not a class, but follows the same "constants at top, init sets everything" convention.

**Imports pattern** (ManzoWindow.swift line 1):
```swift
import AppKit
```

**Constant declaration pattern** (ManzoWindow.swift lines 14–15 — private file-scope constants):
```swift
private let kWindowWidth:  CGFloat = 275
private let kWindowHeight: CGFloat = 116
```
Apply same pattern for UserDefaults key:
```swift
private let kVisualStyleKey = "ManzoVisualStyle"
```

**Struct shape** — from CONTEXT.md D-02 (authoritative, no existing analog):
```swift
struct ManzoVisualStyle: Codable {
    var panelLayout: PanelLayout
    var colorTheme:  ColorTheme
    var wetFloor:    Bool

    static let `default` = ManzoVisualStyle(
        panelLayout: .unifiedSlab,
        colorTheme:  .winampClassic,
        wetFloor:    false
    )
}
```

**Enum shape** — from CONTEXT.md D-03/D-04:
```swift
enum PanelLayout: String, Codable {
    case unifiedSlab   // default — single glass slab spanning full 116pt
    case threeBubbles  // 3 independent r=10 containers
    case bodyFocus     // bodyView full stack; title/status get base+rim only
}

enum ColorTheme: String, Codable {
    case winampClassic  // #181829 / #39395A / #BDCED6 specular
    case neoAero        // P3 aqua-teal
    case indigoTeal     // deep navy-teal
    case wszSkin        // v2 placeholder — NO implementation in Phase 6
}
```

**UserDefaults persistence pattern** — no existing UserDefaults use in codebase; use standard Swift Codable pattern:
```swift
// Save
if let data = try? JSONEncoder().encode(style) {
    UserDefaults.standard.set(data, forKey: kVisualStyleKey)
}
// Load
static func load() -> ManzoVisualStyle {
    guard let data = UserDefaults.standard.data(forKey: kVisualStyleKey),
          let style = try? JSONDecoder().decode(ManzoVisualStyle.self, from: data)
    else { return .default }
    return style
}
```

---

### `ManzoApp/ManzoApp/ManzoRootView.swift` (component, request-response) — MODIFY

**Analog:** self (lines 1–108, already read)

**Insertion point — `cornerRadius` change** (ManzoRootView.swift line 51):
```swift
// BEFORE (Phase 5):
layer?.cornerRadius = 0   // D-07: rectangular in Phase 5; Phase 6 may add corner radius

// AFTER (Phase 6, D-01):
layer?.cornerRadius = 10  // D-01: glass-bubble look
layer?.masksToBounds = true
```

**Insertion point — `applyStyle` method** added after `setupPanels()` in `init`. Pattern copied from `setupPanels()` structure (ManzoRootView.swift lines 65–98):
```swift
// Phase 6: called from init after setupPanels(), and again when style changes.
// Removes existing neo-aero sublayers, inserts fresh ones per current style.
func applyStyle(_ style: ManzoVisualStyle) {
    // Remove old neo-aero layers (identified by a known name tag set by factory)
    // Insert new layers from factory
    // Conditionally wire CAReplicatorLayer if style.wetFloor
    NSLog("MANZO Phase 6: applyStyle — layout=%@, theme=%@, wetFloor=%d",
          "\(style.panelLayout)", "\(style.colorTheme)", style.wetFloor ? 1 : 0)
}
```

**NSLog style** (ManzoRootView.swift line 55 / line 97 / ManzoWindow.swift line 44):
All NSLog calls use `"MANZO Phase N: <context> — <details>"` format with `%@` or `%d` for interpolated values. Do NOT use Swift string interpolation inside NSLog format strings (use `%@` + trailing args).

---

### `ManzoApp/ManzoApp/AppDelegate.swift` (controller, request-response) — MODIFY

**Analog:** self (lines 1–247, already read)

**State property pattern** (AppDelegate.swift lines 7–28 — `private var` instance properties):
```swift
// Add after manzoWindow declaration (line 28):
private var visualStyle: ManzoVisualStyle = .default
```

**Wiring pattern** (AppDelegate.swift lines 81–90 — Phase 5 window setup block):
```swift
// BEFORE (Phase 5):
let window = ManzoWindow()
let rootView = ManzoRootView(frame: window.frame)
window.contentView = rootView

// AFTER (Phase 6) — add style initialization and application:
let window   = ManzoWindow()
let rootView = ManzoRootView(frame: window.frame)
visualStyle  = ManzoVisualStyle.load()      // load persisted style or default
rootView.applyStyle(visualStyle)            // apply Neo-Aero layers
window.contentView = rootView
```

**NSLog convention** (AppDelegate.swift line 90):
```swift
NSLog("MANZO Phase 6: ManzoVisualStyle loaded — layout=%@, theme=%@",
      "\(visualStyle.panelLayout)", "\(visualStyle.colorTheme)")
```

---

### `ManzoApp/project.yml` (config) — MODIFY

**Analog:** self (lines 1–81, already read)

**Sources pattern** (project.yml lines 43–46):
```yaml
sources:
  - path: ManzoApp
    excludes:
      - "*.yml"
```
The `path: ManzoApp` glob already picks up all `.swift` files recursively under `ManzoApp/ManzoApp/`. New files `NeoAeroLayer.swift` and `ManzoVisualStyle.swift` placed in `ManzoApp/ManzoApp/` are automatically included — **no explicit file list change required** to `project.yml` as long as files are placed in the existing `ManzoApp/` source path. Confirm by running `xcodegen generate` after adding files.

---

## Shared Patterns

### NSLog Diagnostic Format
**Source:** `ManzoApp/ManzoApp/ManzoRootView.swift` line 55, `ManzoApp/ManzoApp/ManzoWindow.swift` line 44, `ManzoApp/ManzoApp/AppDelegate.swift` lines 73, 90
**Apply to:** All new and modified Swift files (every significant code path)
```swift
NSLog("MANZO Phase 6: <ClassName>.<methodName> — <key>=<val>")
// For format args, use %@ / %d / %f — NOT Swift \() interpolation in format string
NSLog("MANZO Phase 6: NeoAeroLayerFactory.make — bounds=%@", NSStringFromRect(bounds))
```

### Import Convention
**Source:** All existing Swift files (ManzoRootView.swift line 1, ManzoWindow.swift line 1, AppDelegate.swift line 1)
**Apply to:** All new Swift files
```swift
import AppKit
// QuartzCore types (CALayer, CAGradientLayer, CAReplicatorLayer) available via AppKit import
// No need for: import QuartzCore, import CoreGraphics, import Foundation separately
```

### P3 Color Construction
**Source:** `.claude/skills/spike-findings-MANZO/references/neo-aero-visual-stack.md` (spike 010)
**Apply to:** `NeoAeroLayer.swift`, `ManzoVisualStyle.swift` (palette definitions)
**Constraint:** NEVER use `CGColor(red:green:blue:alpha:)` or `NSColor(calibratedRed:...)` for brand colors
```swift
let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
let color = CGColor(colorSpace: p3, components: [r, g, b, a])!
```

### No NIBs / No Storyboards
**Source:** `ManzoRootView.swift` line 58, `AppDelegate.swift` — no IB references anywhere
**Apply to:** All new files
```swift
required init?(coder: NSCoder) { fatalError("init(coder:) not used — code-only UI") }
```
All new `NSView` subclasses (if any) must include this fatalError init.

### Rasterization — Always Pair Scale
**Source:** `neo-aero-visual-stack.md` lines 43–44 / CONTEXT.md D-08 / CLAUDE.md critical constraints
**Apply to:** All CALayer instances with `shouldRasterize = true`
```swift
layer.shouldRasterize    = true
layer.rasterizationScale = 2.0   // Retina — NEVER omit; omission = blurry cached layer
```

### masksToBounds Off-Screen Cost Mitigation
**Source:** `neo-aero-visual-stack.md` Landmines / `window-glass-architecture.md`
**Apply to:** Any `CALayer` with `cornerRadius + masksToBounds = true`
```swift
// masksToBounds = true triggers off-screen render pass.
// Always pair with shouldRasterize to make it one-time, not per-frame.
container.masksToBounds      = true
container.shouldRasterize    = true
container.rasterizationScale = 2.0
```

---

## No Analog Found

No files are fully without analog. The spike reference files serve as the direct code source for `NeoAeroLayer.swift`. All patterns are validated.

| File | Role | Fallback Source |
|---|---|---|
| `NeoAeroLayer.swift` | utility/factory | Use spike 008/009 code verbatim from `neo-aero-visual-stack.md` |
| `ManzoVisualStyle.swift` | model | Use CONTEXT.md D-02/D-03/D-04 struct definitions directly |

---

## Metadata

**Analog search scope:** `ManzoApp/ManzoApp/` (4 Swift files), `.claude/skills/spike-findings-MANZO/references/` (4 reference files)
**Files read:** 8 (ManzoRootView.swift, AppDelegate.swift, ManzoWindow.swift, main.swift, project.yml, neo-aero-visual-stack.md, window-glass-architecture.md, SKILL.md)
**Pattern extraction date:** 2026-04-24

**Critical architecture constraints carried forward (from CLAUDE.md + spikes):**
- One `.behindWindow` NSVisualEffectView at window root ONLY — never nest
- All inner panels: CALayer-only, `isOpaque = false`, no nested NSVisualEffectView
- P3 colors everywhere via `CGColorSpace(name: CGColorSpace.displayP3)!`
- `shouldRasterize = true` ALWAYS requires `rasterizationScale = 2.0`
