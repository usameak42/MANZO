# MANZO Design System

MANZO is a macOS music player — a modern, P3-native re-interpretation of Winamp Classic's 2.x chrome. Everything here is extracted from the app's real source (`ManzoApp/`, Swift/AppKit) and the classic Winamp resource pack (`winamp/Src/Winamp/resource/`) it quotes. No invention; every token has a source.

## Product context

- **What it is.** Local-file MP3/FLAC/AAC player. Borderless `NSWindow`s snap to a grid, can be shaded to 14pt, and can be stacked like the original. Draws: main window (transport + LCD + marquee + spectrum), playlist editor, equalizer.
- **Who it's for.** People who keep their music in a folder, not a service. It is intentionally small, offline, and keyboard-driven.
- **What makes it "MANZO."** Three things:
  1. **Neo-Aero.** A faux-5-layer CALayer stack — base gradient + 3-stop specular band + lower glow + 1pt inset rim — rasterized at 2×. It's Frutiger Aero rendered in 2025 P3, not a skeuomorphic bitmap.
  2. **Bitmap-font soul.** Marquee + LCD keep the pixel character of `text.bmp` / `numbers.bmp`. The rest of the UI is SF Pro — the two voices sit on top of each other cleanly.
  3. **No chrome tax.** One 275×116pt window does the work. Playlist + EQ open only when you ask.

## Three themes

| Key             | Top                     | Bottom                  | Use                    |
|-----------------|-------------------------|-------------------------|------------------------|
| `winampClassic` | P3(.10 .10 .10) #1A1A1A | P3(.23 .23 .23) #3B3B3B | default — neutral charcoal, sampled from MAIN.BMP |
| `neoAero`       | P3(.05 .78 .82)         | P3(.02 .52 .60)         | tropical aqua, out-of-sRGB |
| `indigoTeal`    | P3(.04 .09 .20)         | P3(.10 .22 .28)         | OLED-night             |

Switching a theme calls `invalidateNeoAeroRasterization()` → CALayer redraws at the new `rasterizationScale` (2.0).

## What's here

```
colors_and_type.css        foundation tokens (CSS custom properties, authored in Display P3)
SKILL.md                   how Claude should build MANZO surfaces
README.md                  ← this file
assets/                    ICO / BMP / sprite sheets from the real app + Winamp source
preview/                   one HTML card per foundation & component
manzo_ui_kit.html          working mini-player mockup (main window + playlist + EQ)
```

### Card index

| Group      | Card                          | What it documents                                |
|------------|-------------------------------|--------------------------------------------------|
| Colors     | `colors-base-gradients`       | The three `ColorTheme` cases, top→bottom P3       |
| Colors     | `colors-text`                 | fg-1 / fg-2 / fg-3 / missing / subtle             |
| Colors     | `colors-accents`              | selection blue · spectrum green→yellow→red · LCD  |
| Colors     | `colors-specular-stack`       | 1/2/3/4-composed — the Neo-Aero layer factory     |
| Type       | `type-scale`                  | LCD · marquee · h2 · titlebar · body · mini       |
| Spacing    | `spacing-windows`             | 275×116 / 350×auto / 24pt rows                    |
| Spacing    | `spacing-radii-shadow`        | radius 10 · 1pt rim · NSWindow shadow · wet-floor |
| Components | `components-mainwindow`       | titlebar + LCD + marquee + seek + statusbar      |
| Components | `components-playlist`        | row / selected / missing / footer                 |
| Components | `components-spectrum`         | 75 × 16 analyzer w/ peak holds                    |
| Components | `components-transport`        | prev / play / pause / stop / next + eject         |
| Brand      | `brand-marks`                 | app icon · pixel wordmark · thin wordmark         |
| Brand      | `brand-voice`                 | copy tone — do/don't                              |

## Authoring rules

- **P3 everywhere.** Author in `color(display-p3 r g b / a)`. Hex is a fallback label only.
- **Never skeuo.** No stitched leather, no brushed metal. The rim + the 3-stop specular are the whole visual DNA.
- **Bitmap voice is reserved.** Use pixel fonts (VT323 in web land, sprites in native) ONLY for the LCD and marquee. Everything else is SF Pro.
- **Composition over ornament.** 14 / 88 / 14 titlebar-body-statusbar. Don't invent new bands.
- **One accent family per surface.** Selection blue and spectrum green coexist but never overlap — the spectrum sits inside the main window's body band; selection is a playlist-row affordance.
- **Rim is load-bearing.** Every bubble carries the 1pt inset highlight at α 0.45. Skipping it makes the surface look flat, not modern.

## Open questions / flags

- **Bitmap font extraction.** We substituted VT323 for `text.bmp` and `numbers.bmp`. For pixel-perfect web previews, extract glyphs from `winamp/Src/Winamp/resource/text.bmp` and ship a webfont — but only if these surfaces ever leave the app.
- **Pledit.bmp resample.** Text colors in `colors-text` are plausible defaults. Re-upload `Pledit.bmp` to pixel-sample the exact normal/current/background/selection colors from its palette row.
- **Wordmark fonts.** The primary lockup (`assets/manzo-logo.png`) is final. The *wordmark* type studies (`MANZO` / `マンゾウ`) are explicitly placeholder — typographic direction is TBD.
- **ManzoEQ.** The repo has `ManzoEqualizer.swift` but no window-level canvas in this export. EQ in this kit was rebuilt to Winamp 2.x spec (curve graph, ribbed square thumbs, yellow-boost / green-cut track fill, +12/0/−12 reference lines, LED buttons, PRESETS) — confirm band geometry against `Eqmain.bmp` before finalizing.
- **Shade mode.** The classic 14pt shade state is not yet documented — deferred until ManzoWindow exposes its shaded dimensions.

## Changelog (this session)

- `winampClassic` base regraded from indigo `#181829 → #39395A` to neutral charcoal `#1A1A1A → #3B3B3B` (MAIN.BMP sample).
- Specular-stack card base + shared `.neo` preview updated to match.
- Equalizer rebuilt end-to-end: EQ curve graph, colored-fill tracks, ribbed square thumbs, ruler ticks, dB reference lines, LED On/Auto buttons, PRESETS button, fully-visible PREAMP column, navy textured backdrop.
- Main window rebuilt: macOS traffic lights, spectrum analyzer in body, transport row (|◀◀ ▶ ❚❚ ■ ▶▶| ⏏) in beveled pixel-art style, horizontal volume slider, EQ/PL toggle buttons linking to their preview cards.
- Brand marks: logo locked, katakana corrected to **マンゾウ**, dock icon uncropped and set on matching paper texture, wordmark variants flagged *fonts TBD*.
