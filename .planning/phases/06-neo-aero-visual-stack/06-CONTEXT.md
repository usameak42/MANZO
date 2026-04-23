# Phase 6: Neo-Aero Visual Stack - Context

**Gathered:** 2026-04-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Apply the 5-layer Neo-Aero CALayer specular chrome to the three structural panels delivered by
Phase 5 (`titleView`, `bodyView`, `statusView`). No new NSViews are added — Phase 6 inserts
`CAGradientLayer` sublayers into the existing layer trees. Lock the P3 brand palette. Wire
`CAReplicatorLayer` wet-floor reflection. Enable rasterization for static panels.

**In scope:**
- 5-layer Neo-Aero stack (base gradient → specular band → lower glow → rim → container w/ masksToBounds)
- `ManzoVisualStyle` struct — panel layout, color theme, wet-floor toggle — stored in UserDefaults
- Wet-floor `CAReplicatorLayer` below the full window (VIS-02)
- All brand colors as `CGColor(colorSpace: .displayP3)` (VIS-03)
- `shouldRasterize = true` + `rasterizationScale = 2.0` for static panels (VIS-04)
- Root `NSVisualEffectView` `cornerRadius` updated from 0 → 10

**Out of scope:**
- Transport button layout or interactive controls — later phases
- Spectrum analyzer MTKView — Phase 7
- `.wsz` skin parser — v2 feature (placeholder enum case reserved, no implementation)
- EQ slider UI — Phase 8

</domain>

<decisions>
## Implementation Decisions

### Corner Radius
- **D-01:** All Neo-Aero container layers use `cornerRadius = 10` (r=10, glass-bubble look).
  The root `NSVisualEffectView.layer?.cornerRadius` is updated from 0 to 10 in Phase 6.
  The container `CALayer` inside each neo-aero stack also uses `cornerRadius = 10` with
  `masksToBounds = true` (spike 008 pattern — `shouldRasterize = true` mitigates the
  off-screen rendering cost of `masksToBounds`).

### ManzoVisualStyle — Panel Layout
- **D-02:** Introduce a `ManzoVisualStyle` struct (not a monolithic enum — separate axes):

  ```swift
  struct ManzoVisualStyle {
      var panelLayout: PanelLayout  // controls how chrome layers are distributed
      var colorTheme:  ColorTheme   // controls the gradient palette
      var wetFloor:    Bool         // controls CAReplicatorLayer below window

      static let `default` = ManzoVisualStyle(
          panelLayout: .unifiedSlab,
          colorTheme:  .winampClassic,
          wetFloor:    false
      )
  }
  ```

  Persist to UserDefaults. Changing any field rebuilds the affected layer(s) — no full
  teardown required.

- **D-03:** `PanelLayout` enum — three options, default `.unifiedSlab`:

  | Case | Description |
  |------|-------------|
  | `.unifiedSlab` | 5-layer stack spans full 116pt root NSVisualEffectView as one glass slab. `titleView`, `bodyView`, `statusView` remain as layout zones; chrome is one continuous element underneath. |
  | `.threeBubbles` | Each panel is an independent r=10 Neo-Aero container (3 separate layer stacks, visible gaps between panels). |
  | `.bodyFocus` | `bodyView` gets full 5-layer stack (r=10). `titleView` and `statusView` get base gradient + rim only (2 layers, r=0). |

  **Default: `.unifiedSlab`** — closest to Winamp's undivided chrome, avoids the panel-gap
  visual artifact on 14pt thin panels.

### ManzoVisualStyle — Color Theme
- **D-04:** `ColorTheme` enum — four cases, default `.winampClassic`:

  | Case | Base Top (P3) | Base Bottom (P3) | Specular | Rim |
  |------|--------------|-----------------|----------|-----|
  | `.winampClassic` | P3(0.09, 0.09, 0.16) `#181829` | P3(0.22, 0.22, 0.35) `#39395A` | P3(0.74, 0.81, 0.84) `#BDCED6` @ 50% | white @ 45% |
  | `.neoAero` | P3(0.05, 0.78, 0.82) aqua-teal | P3(0.02, 0.52, 0.60) deep teal | white @ 50% | white @ 45% |
  | `.indigoTeal` | P3(0.04, 0.09, 0.20) deep navy-teal | P3(0.10, 0.22, 0.28) teal-indigo | P3(0.74, 0.87, 0.90) ice blue @ 50% | white @ 45% |
  | `.wszSkin` | **v2 placeholder — NO implementation in Phase 6.** When a `.wsz` skin is loaded (v2), this case overrides all built-in palettes with colors extracted from the skin's bitmap. Reserve the enum case only. |

  **Canonical P3 values derived from:** actual MAIN.BMP pixel sampling (275×116, 8-bit palette).
  `.winampClassic` base colors are the two most dominant non-black, non-white clusters in the
  main chrome area of the original Winamp skin bitmap.

- **D-05:** All P3 color construction uses:
  ```swift
  let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
  CGColor(colorSpace: p3, components: [r, g, b, a])
  ```
  Never use `NSColor(calibratedRed:...)` or sRGB `CGColor(red:green:blue:alpha:)` for brand
  colors. Core Animation render server handles P3 output automatically on P3 displays; on
  non-P3 displays it tone-maps gracefully.

### ManzoVisualStyle — Wet-Floor
- **D-06:** Wet-floor reflection placement: **one `CAReplicatorLayer` below the full window**,
  attached to the root `NSVisualEffectView`'s layer. Reflects the whole 116pt window as a
  single surface. Y-flip transform + `instanceAlphaOffset = -0.5` (50% opacity) + gradient
  fade mask (spike 009 validated pattern).
- **D-07:** `wetFloor: Bool` defaults to `false`. The `CAReplicatorLayer` is created/removed
  when this toggle changes (not just hidden) to avoid contributing to the compositor tree when
  off. `shouldRasterize = true` on the reflected layer is free for static panels.

### Rasterization
- **D-08:** All static Neo-Aero layers set `shouldRasterize = true`, `rasterizationScale = 2.0`.
  Invalidate (set `shouldRasterize = false` then `true`) only on actual visual state changes
  (theme switch, layout switch, drag-end) — not per-frame. GPU compositing for 30+ static
  elements stays under 0.8 ms on M-series (spike 008 perf gate).

### Layer Architecture
- **D-09:** A `NeoAeroLayerFactory` (static struct or free functions in `NeoAeroLayer.swift`)
  builds layer stacks for each `PanelLayout` case. Returns a root `CALayer` to be inserted as
  a sublayer into the target view's `layer`. This keeps `ManzoRootView.swift` clean — Phase 6
  adds a single `neoAeroLayer = NeoAeroLayerFactory.make(style:, bounds:)` insertion call.
- **D-10:** `ManzoVisualStyle` is owned by `AppDelegate` (or a new `ManzoThemeController`)
  and passed into `ManzoRootView` via a `applyStyle(_ style: ManzoVisualStyle)` method.
  Changing style calls `applyStyle` which removes old neo-aero layers and inserts fresh ones.

### Claude's Discretion
- Whether `ManzoThemeController` is a standalone class or merged into `AppDelegate`
- Exact UserDefaults key naming for `ManzoVisualStyle` persistence
- Whether each `ColorTheme` case stores its values inline or via a `NeoAeroPalette` helper struct
- Runtime toggle mechanism (hidden key combo, menu item, or debug panel) for switching styles
  during development — not user-visible in v1

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Spike Findings (primary implementation reference)
- `.claude/skills/spike-findings-MANZO/references/neo-aero-visual-stack.md` — Full 5-layer
  CALayer stack code (spike 008), CAReplicatorLayer wet-floor pattern (spike 009), P3 color
  construction for CALayer and MTKView (spike 010). Contains exact Swift code — use directly.
- `.claude/skills/spike-findings-MANZO/references/window-glass-architecture.md` — Landmines
  relevant to Phase 6: `masksToBounds` off-screen rendering, `rasterizationScale = 2.0`
  requirement on Retina, `shouldRasterize` invalidation on state change.

### Phase 5 Context (insertion points)
- `.planning/phases/05-ui-shell/05-CONTEXT.md` — D-08/D-09: `titleView`, `bodyView`,
  `statusView` layer trees are EMPTY in Phase 5. `cornerRadius = 0` on root view (Phase 6
  changes this to 10 per D-01).

### Existing Swift Code (integration points)
- `ManzoApp/ManzoApp/ManzoRootView.swift` — Root view with three panels. Phase 6 modifies
  `layer?.cornerRadius` here and adds `NeoAeroLayerFactory` call. Read before writing any code.
- `ManzoApp/ManzoApp/ManzoWindow.swift` — Window setup (no changes expected in Phase 6).
- `ManzoApp/ManzoApp/AppDelegate.swift` — Wiring point for `ManzoVisualStyle` initialization
  and `ManzoThemeController`.

### Winamp Skin (palette derivation)
- `Winamp/Src/Winamp/resource/MAIN.BMP` — 275×116 px 8-bit indexed BMP. Sampled to derive
  `.winampClassic` P3 palette. Dominant chrome colors: `#181829` (base top), `#39395A`
  (base bottom), `#BDCED6` (specular highlights).
- `Winamp/Src/Winamp/resource/CBUTTONS.BMP` — Button bitmap. Accent color reference:
  `#7B8C9C` (mid-tone), `#BDCED6` (highlight), `#EFFFFF` (near-white cyan tint).

### Project Planning
- `.planning/REQUIREMENTS.md` — VIS-01 (5-layer stack), VIS-02 (wet-floor), VIS-03 (P3 colors),
  VIS-04 (rasterization)
- `.planning/ROADMAP.md` — Phase 6 success criteria (4 items)
- `.planning/PROJECT.md` — P3 colors mandatory, no nested NSVisualEffectView, no bitmaps in chrome

### v2 Reference (do NOT implement in Phase 6)
- `/Users/usameak42/Coding/MANZO/Neon Genesis Evangelion - Ode To Joy Kaworu.wsz` — Sample
  `.wsz` skin file for future v2 `.wsz` parser analysis. Reserve `ColorTheme.wszSkin` enum
  case but write zero parser code in Phase 6.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ManzoRootView.titleView`, `.bodyView`, `.statusView` — Three `NSView` instances with empty
  `CALayer` trees. These are the insertion points for Phase 6 neo-aero sublayers.
- `AppDelegate.applicationDidFinishLaunching` — Wiring point for new `ManzoVisualStyle`
  initialization and style application.

### Established Patterns
- `NSLog(...)` for all diagnostic output (Phases 1–5 convention)
- No NIBs/storyboards — all UI constructed in code
- `wantsLayer = true` + `isOpaque = false` already set on all three panels (Phase 5)
- `cornerRadius = 0` on root view layer (Phase 5) — Phase 6 changes this to 10

### Integration Points
- `ManzoRootView.setupPanels()` (Phase 5): Phase 6 adds neo-aero layer insertion here, or via
  a separate `applyStyle()` method called after `setupPanels()`.
- `ManzoWindow.init()`: `hasShadow = true` is already set — complements the glass-bubble
  aesthetic without any change.
- `xcodegen project.yml`: Any new Swift files (`NeoAeroLayer.swift`, `ManzoThemeController.swift`)
  must be listed here to be included in the build.

</code_context>

<specifics>
## Specific Ideas

- **Winamp palette derivation:** `.winampClassic` colors come from pixel-sampling the actual
  `MAIN.BMP` (275×116, 8bpp). Top chrome cluster: `#181829` (24, 24, 41). Body cluster:
  `#39395A` (57, 57, 90). Specular highlight from CBUTTONS: `#BDCED6` (189, 206, 214).
  These are within sRGB gamut; their P3 component values are numerically equivalent to the
  sRGB values (P3 does not re-encode intra-gamut colors).

- **ManzoVisualStyle enum roadmap:**
  ```
  PanelLayout:  .unifiedSlab (default), .threeBubbles, .bodyFocus
  ColorTheme:   .winampClassic (default), .neoAero, .indigoTeal, .wszSkin (v2 placeholder)
  wetFloor:     Bool, default false
  ```

- **Wet-floor CAReplicatorLayer:** `instanceCount = 2`, Y-flip transform (m22 = -1), offset =
  `panelHeight * 2` below panel, `instanceAlphaOffset = -0.5`. Fade mask via `CAGradientLayer`
  (black→clear, top-to-bottom). Exact code in spike 009 reference.

- **specular band frame:** `CGRect(x:0, y:0, width:bounds.width, height:bounds.height * 0.52)` —
  covers top 52% of slab for `.unifiedSlab`. For `.threeBubbles` on 14pt panels: specular at
  52% = 7.3 px, still renders (just tighter). For `.bodyFocus`: specular on bodyView 88pt only.

- **rasterizationScale:** Always set alongside `shouldRasterize = true`:
  ```swift
  layer.shouldRasterize = true
  layer.rasterizationScale = 2.0  // Retina — never omit this
  ```

</specifics>

<deferred>
## Deferred Ideas

- `.wsz` skin parser (ZIP + BMP sheets + `region.txt`) — v2. Path noted:
  `/Users/usameak42/Coding/MANZO/Neon Genesis Evangelion - Ode To Joy Kaworu.wsz`
  Reference source when implementing: `Winamp/Src/Winamp/Set.cpp`,
  `Winamp/Src/Winamp/SkinBitmapElement.cpp` (from Phase 5 CONTEXT deferred ideas).
- Runtime style switcher UI (user-visible theme picker) — deferred post-v1; Phase 6 builds
  the enum infrastructure but the toggle mechanism is development-only (hidden key combo).
- `.withinWindow` NSVisualEffectView for dropdown menus/tooltips — Phase 6+ (still deferred;
  no dropdown UI in Phase 6).
- Double-size (2×) mode (`config_dsize`) — still deferred; Phase 6 hardcodes 275×116.
- `CAGradientLayer` radial type for off-axis specular orb — cannot do asymmetric radial natively.
  If needed, use a 32×32 PNG or approximate with `type = .radial` + adjusted start/end points.
  Not needed for Phase 6's linear specular band.

</deferred>

---

*Phase: 06-neo-aero-visual-stack*
*Context gathered: 2026-04-24*
