# Phase 6: Neo-Aero Visual Stack - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-24
**Phase:** 06-neo-aero-visual-stack
**Areas discussed:** Corner radius, Thin panel treatment, Wet-floor scope, Brand P3 palette

---

## Corner Radius

| Option | Description | Selected |
|--------|-------------|----------|
| Rectangular (r=0) | Matches classic Winamp exactly. hasShadow provides soft depth. | |
| Slightly rounded (r=4) | Subtle macOS polish without departing from Winamp's angular look. | |
| Glass bubble (r=10) | Spike 008 default. Full Frutiger Aero feel. | ✓ |

**User's choice:** Glass bubble (r=10)
**Notes:** Applied to all Neo-Aero container layers and the root NSVisualEffectView cornerRadius.

---

## Thin Panel Treatment

| Option | Description | Selected |
|--------|-------------|----------|
| Full stack on all 3 panels | Each panel is an independent r=10 pill. Visible gaps between panels. | |
| One unified container | 5-layer stack spans full 116pt root as one glass slab. | ✓ |
| Body only + thin-panel rim | bodyView gets full stack; titleView/statusView get base+rim only. | |

**User's choice:** One unified container (default)
**Notes:** User requested all 3 panel layouts be available at runtime via a `ManzoVisualStyle` struct:
- `PanelLayout.unifiedSlab` — default
- `PanelLayout.threeBubbles`
- `PanelLayout.bodyFocus`
Persisted in UserDefaults.

---

## Wet-Floor Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Below the window | One CAReplicatorLayer on root view, reflecting full 116pt slab. | ✓ |
| Inset within bodyView | Frosted-glass bar at bottom of body zone, stays within window bounds. | |

**User's choice:** Below the window
**Notes:** `wetFloor: Bool` added to `ManzoVisualStyle`, default `false`. CAReplicatorLayer is
created/removed (not just hidden) when toggled to keep compositor tree clean.

---

## Brand P3 Palette

**Pre-research:** Sampled `Winamp/Src/Winamp/resource/MAIN.BMP` (275×116, 8bpp) and
`CBUTTONS.BMP` to find actual Winamp chrome colors. Finding: classic Winamp chrome is
**dark navy-indigo** (#181829 to #39395A), NOT aqua/teal. The spike's aqua/teal was an
artistic reinterpretation.

| Option | Description | Selected |
|--------|-------------|----------|
| Faithful Winamp (dark indigo) | #181829→#39395A base, #BDCED6 specular, white rim. | ✓ |
| Neo-Aero aqua/teal (spike) | P3(0.05, 0.78, 0.82) top to P3(0.02, 0.52, 0.60) bottom. Vivid. | |
| Indigo + teal accent | Dark indigo tinted toward teal/cyan. Splits the difference. | |

**User's choice:** Faithful Winamp (dark indigo) as default
**Notes:** All 3 palettes (plus `.wszSkin` v2 placeholder) available as `ColorTheme` enum cases
in `ManzoVisualStyle`. Default: `.winampClassic`. When `.wsz` skin is loaded in v2, its bitmap
colors override the active theme. Sample `.wsz` file at:
`/Users/usameak42/Coding/MANZO/Neon Genesis Evangelion - Ode To Joy Kaworu.wsz`
(noted for v2 reference — no parser implementation in Phase 6).

---

## Claude's Discretion

- Whether `ManzoThemeController` is a standalone class or merged into `AppDelegate`
- UserDefaults key naming for `ManzoVisualStyle` persistence
- Whether each `ColorTheme` stores values inline or via a `NeoAeroPalette` helper struct
- Development-only runtime toggle mechanism (hidden key combo, not user-visible in v1)

## Deferred Ideas

- `.wsz` skin parser — v2 feature. Reserve `ColorTheme.wszSkin` enum case only.
- User-visible theme picker UI — post-v1
- `.withinWindow` NSVisualEffectView for dropdown menus — later phase
- Double-size (2×) window mode — still deferred
