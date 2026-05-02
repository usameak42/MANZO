# SKILL.md — Building MANZO surfaces

Use this when the user asks you to design any MANZO UI: a new window, a redesign, marketing, about-panel, etc. Read `README.md` first; read `colors_and_type.css` for tokens.

## The checklist (in order)

1. **Pick a theme.** Default `winampClassic`. Use `neoAero` for marketing/hero shots, `indigoTeal` for OLED/night imagery. Never invent a new gradient pair.
2. **Start with the bubble.** Every surface is a rounded-10px container carrying the 5-layer Neo-Aero stack (`.neo-aero` in `colors_and_type.css`). The 1pt inset rim at α 0.45 is non-negotiable — the surface looks flat without it.
3. **Band the window.** Classic 14 / 88 / 14 titlebar + body + statusbar. Titlebar: 9pt caps, fg-3, +8% tracking. Statusbar: same type, darker base (α 0.25 black).
4. **Pixel voice ONLY for LCD + marquee.** VT323 (web) or `numbers.bmp`/`text.bmp` sprites (native). LCD digits get the dual-stop green glow. Everything else: SF Pro.
5. **Row = 24pt, radius-3 pill selection.** Active row uses `--accent-selection` P3(0.15,0.45,0.85 / .70) with white text. Missing files: strikethrough + fg-missing.
6. **Spectrum: 75 × 16, peak-falls 1.1/frame.** Use the three-stop gradient (green→yellow→red) + white peak dot. Never a single-color fill.
7. **Buttons are subtle gradients, not skeuo.** Inline gradient α .14 → .03, 1pt inset rim. On-state = selection blue. No beveled 3D lighting.
8. **Copy in MANZO voice.** Sparse, technical, a little referential. Sentence case for UI labels; ALL-CAPS reserved for titlebars + status chips. No emoji. See `preview/brand-voice`.

## What to reach for

- Need a working starting point? Copy `manzo_ui_kit.html`.
- Need tokens only? Import `colors_and_type.css`.
- Need a specific component spec? Open the matching `preview/*.html` — every card names its source Swift file.

## Hard rules

- **P3 always.** Author `color(display-p3 …)`. Hex is a fallback label.
- **One bubble per window.** No nested Neo-Aero containers — the rim stops being legible.
- **Never gradient-text or drop-shadow body copy.** Glow is for the LCD band ONLY.
- **Don't emoji.** Don't add stock icon libraries — use SVG transport glyphs like in `manzo_ui_kit.html` or the real `.ico` files in `assets/`.
- **Don't invent scales.** Sizes are 9 / 11 / 13 / 16 / 24. If you need another, ask.

## When you're unsure

Ask the user before inventing. The design system is deliberately narrow — its personality lives in the constraints.
