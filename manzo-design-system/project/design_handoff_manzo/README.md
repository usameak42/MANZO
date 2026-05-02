# Handoff: MANZO Design System → Swift/AppKit implementation

## Overview

MANZO is a macOS music player — a modern, P3-native re-interpretation of Winamp Classic's 2.x chrome. This bundle contains the **full visual design system** (tokens, component specs, and a working mini-player mockup) so a developer can lift it into the real `ManzoApp/` codebase (Rust DSP + Swift/AppKit UI).

## About the design files

The files in this bundle are **design references created in HTML** — prototypes showing intended look and behavior, not production code to copy directly. The goal is to **recreate these designs in the target codebase's existing Swift/AppKit environment** using `NSVisualEffectView`, `CAGradientLayer`, `CAShapeLayer`, and the `NeoAeroLayerFactory` pattern that already exists in `ManzoApp/ManzoApp/NeoAeroLayer.swift`. Tokens in `colors_and_type.css` translate 1:1 to `CGColor` constructed from Display P3 components.

## Fidelity

**High-fidelity.** Every color, gradient stop, border radius, drop shadow, LCD glow, and type size is a token with a source citation — either a line in the `ManzoApp/` Swift source or a pixel-sampled BMP from `winamp/Src/Winamp/resource/`. The developer should recreate the UI pixel-perfectly using the established native patterns (CALayer composition, rasterized at `rasterizationScale = 2.0`). No invention.

---

## Screens / views

### 1. Main window (`preview/components-mainwindow.html`)

- **Purpose.** Single primary window — transport, playhead, track info, spectrum, EQ/PL launchers.
- **Layout.** 480×auto (scales from the classic 275×116pt footprint). Four bands top-to-bottom: titlebar (22pt) · body (~48pt) · seek bar row (14pt) · transport row (28pt) · status bar (16pt).
- **Components:**
  - **Titlebar.** macOS traffic lights left (red `#F25956` / yellow `#FBC240` / green `#4DCC4D`, 11×11, `inset 0 1px 0 rgba(255,255,255,0.35)`). `MANZO` label centered, 10pt, letter-spacing 0.16em, `color(display-p3 .82 .84 .88)`.
  - **LCD digits.** VT323 26pt, color `color(display-p3 .18 .95 .42)`, text-shadow glow `0 0 6px color(display-p3 .18 .95 .42 / .65)`, on `rgba(0,0,0,0.5)` inset well.
  - **Marquee.** ui-monospace 11pt `color(display-p3 .92 .94 .98)` title + 9.5pt fg-3 metadata row (uppercase, letter-spacing 0.08em).
  - **Spectrum analyzer.** 20-bar (shipping spec is 75), gradient green→yellow→red, height 32pt, inside inset black well.
  - **Seek bar.** 5pt track, `rgba(0,0,0,0.5)` recess, fill `linear-gradient(to right, P3(.05 .78 .82), P3(.13 .85 .47))`, 10×13 white rect thumb.
  - **Transport buttons.** 26×20 beveled pixel-art buttons in a dark well: `|◀◀`, `▶`, `❚❚`, `■`, `▶▶|`, `⏏`. Button face: `linear-gradient(to bottom, P3(.58 .60 .66), P3(.28 .30 .36))`, with `inset 0 1px 0 rgba(255,255,255,0.45)` top highlight + `inset 0 -1px 0 rgba(0,0,0,0.45)` bottom shadow + `0 0 0 1px rgba(0,0,0,0.6)` outer hairline. Active state: gradient flipped. Glyphs drawn as SVG polygons in `color(display-p3 .10 .11 .14)`.
  - **Volume slider.** Horizontal, teal/green fill, `VOL` label 9pt uppercase.
  - **EQ / PL toggles.** 28×18, dark inactive / lit teal active. Clicking opens respective windows.
  - **Status bar.** 16pt, `rgba(0,0,0,0.40)`, 9pt uppercase copy: `▶ Playing` / `SHUFFLE · REPEAT`.

### 2. Equalizer (in `manzo_ui_kit.html`)

- **Purpose.** 10-band EQ with preamp. Winamp 2.x visual language.
- **Layout.** 480×auto. Body has **dark navy textured backdrop** — not flat black:
  ```
  background:
    linear-gradient(to bottom, P3(.04 .07 .14), P3(.06 .10 .18)),
    repeating-linear-gradient(0deg, rgba(255,255,255,0.02) 0 1px, transparent 1px 3px);
  ```
- **Top row** (44pt):
  - **LED buttons** `On` (lit), `Auto` (dark) — dark body, 7×7 square green LED in corner. Lit LED: `P3(.18 .95 .35)` + 4px green glow.
  - **EQ curve graph** — SVG spline through band values. Gold stroke `#F5C927 @ 1.2pt`, green gradient fill `P3(.176 .827 .352)` α 0.55 → 0.02.
  - **PRESETS button** top-right with active preset label below.
- **Slider grid** (128pt tall):
  - Left rail: `+12 db / +0 db / −12 db` labels, ui-monospace 8.5pt, lowercase.
  - **PREAMP column** — separate from bands, gap-separated, label `PRE` in orange caps below.
  - **10 band sliders** at 60 / 170 / 310 / 600 / 1k / 3k / 6k / 12k / 14k / 16k Hz.
  - **Slider track:** recessed groove with ruler tick marks every 1/16th.
  - **Reference lines:** dashed at top (+12) and bottom (−12), solid green at 0 dB.
  - **Colored fill:** yellow `P3(1 .90 .20 → .60 .45 .05)` when boosted; green `P3(.18 .85 .32 → .06 .30 .10)` when cut; 2pt green line at exact 0.
  - **Square ribbed thumb:** `11pt` tall, flat steel gradient, horizontal etched ribs via repeating 1pt black/white striping.

### 3. Playlist editor (`preview/components-playlist.html`)

- **Purpose.** Queue editor. 480×auto, sidebar toolbar, rows, footer.
- **Row = 24pt**, radius-3 pill selection. Active row uses `--accent-selection` `P3(0.15 0.45 0.85 / 0.70)` with white text. Missing files: strikethrough + fg-missing.
- Toolbar: + add · − rem · sort · save · `N tracks · MM:SS`.

---

## Design tokens

All canonical values live in `colors_and_type.css`. Highlights:

### Base gradients (per theme)
| Theme           | Top P3              | Bottom P3           |
|-----------------|---------------------|---------------------|
| `winampClassic` | .10 .10 .10         | .23 .23 .23         |
| `neoAero`       | .05 .78 .82         | .02 .52 .60         |
| `indigoTeal`    | .04 .09 .20         | .10 .22 .28         |

### Text
| Token          | Value                       |
|----------------|-----------------------------|
| `--fg-1`       | `P3(.92 .94 .98)`           |
| `--fg-2`       | `P3(.78 .80 .85)`           |
| `--fg-3`       | `P3(.58 .60 .65)`           |
| `--fg-missing` | `P3(.50 .52 .55 / .75)` + strikethrough |
| `--fg-subtle`  | `P3(.40 .42 .48)`           |

### Accents
- `--accent-selection`: `P3(.15 .45 .85 / .70)`
- `--accent-lcd`: `P3(.18 .95 .42)` with text-shadow `0 0 6px color(.18 .95 .42 / .65)`
- Spectrum gradient stops: `P3(.13 .85 .47)` → `P3(1 .85 .20)` → `P3(.95 .30 .25)`

### Typography scale
9 · 11 · 13 · 16 · 24 pt. Body = SF Pro. LCD/marquee = pixel sprite (native: `text.bmp`/`numbers.bmp`; web fallback: VT323). No other sizes permitted.

### Geometry
- Window radius 10
- 1pt inset rim at α 0.45 on every Neo-Aero container (non-negotiable)
- NSWindow shadow + "wet-floor" reflection — see `preview/spacing-radii-shadow.html`

---

## Interactions & behavior

- **Theme switch.** `ColorTheme` UserDefaults key. Changing invalidates `rasterizationScale = 2.0` on the Neo-Aero container; all sublayers redraw from scratch.
- **EQ curve.** Catmull–Rom spline through 10 band values. Updates live as sliders drag.
- **Slider drag.** `ns-resize` cursor. ±12 dB range, continuous, not stepped.
- **Window snap.** Borderless `NSWindow`s snap to a grid and stack (see `ManzoApp/ManzoRootView.swift`).
- **Shade mode.** 14pt titlebar-only state — deferred (not documented yet).

---

## Assets

Located in `assets/`:
- `WinampIcon.png` + `.ico` — original Winamp app icon
- `manzo-logo.png` — **MANZO primary lockup** (katakana **マンゾウ** + illustrated skin)
- `ICONS.GIF`, `ICON1.png`…`ICON13.png`, `TBICON1.png`…`TBICON5.png` — original Winamp icon set (PNG conversions of the original `.ico` files)
- `OSD-Sprite-Controls.png` — transport icon sprite reference
- `titlebar-font.png` — titlebar font reference

Wordmark fonts are **placeholder** (marked `FONTS TBD` in brand-marks card). Type direction is still open.

---

## Authoring rules

- **P3 everywhere.** Author in `color(display-p3 r g b / a)`. In Swift: `CGColor(colorSpace: CGColorSpace(name: .displayP3), components: [r,g,b,a])`.
- **Never skeuo.** No stitched leather, no brushed metal. The rim + the 3-stop specular are the whole visual DNA.
- **Bitmap voice is reserved.** Pixel fonts ONLY for LCD and marquee.
- **Composition over ornament.** 14 / 88 / 14 titlebar-body-statusbar. Don't invent new bands.
- **Rim is load-bearing.** 1pt inset α 0.45 on every bubble.

---

## Files in this bundle

```
README.md                     ← this file (handoff overview)
DESIGN_README.md              original design-system README with full context
SKILL.md                      rules for building new MANZO surfaces
colors_and_type.css           canonical tokens
manzo_ui_kit.html             working mini-player mockup (main + playlist + EQ)
preview/                      one HTML card per foundation & component
  ├─ _card.css                shared card styles (incl. `.neo` container)
  ├─ colors-base-gradients.html
  ├─ colors-text.html
  ├─ colors-accents.html
  ├─ colors-specular-stack.html
  ├─ type-scale.html
  ├─ spacing-windows.html
  ├─ spacing-radii-shadow.html
  ├─ components-mainwindow.html
  ├─ components-playlist.html
  ├─ components-spectrum.html
  ├─ components-transport.html
  ├─ brand-marks.html
  └─ brand-voice.html
assets/                       source bitmaps, icons, logo
REFERENCE_Swift/              the three native files this system codifies
  ├─ ManzoVisualStyle.swift   ColorTheme enum + UserDefaults wiring
  ├─ NeoAeroLayer.swift       5-layer CALayer factory (ground truth)
  └─ ManzoRootView.swift      NSVisualEffectView host
```

## Open questions / flags

- **Pledit.bmp resample.** `colors-text` values are plausible defaults, not pixel-sampled. Re-sample from the original palette row if available.
- **Wordmark fonts.** TBD. Logo lockup is final; wordmark variants are placeholders.
- **Shade mode.** Not yet documented.
- **ManzoEqualizer.swift.** Band geometry was rebuilt visually — confirm against Eqmain.bmp sprite before shipping native.
