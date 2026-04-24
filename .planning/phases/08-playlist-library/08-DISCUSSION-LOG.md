# Phase 8: Playlist & Library - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-24
**Phase:** 08-playlist-library
**Areas discussed:** Window architecture, Track display format, Persistence format, Playlist model & AppDelegate wiring

---

## Window Architecture

### Pre-discussion research: Winamp hPLWindow dimensions
Checked `Winamp/Src/winamp/config.h:120-121` before discussing:
- `config_pe_width = 275` (same as main window)
- `config_pe_height = 116` (same as main window — users resize taller)
- Default position: `config_pe_wx = 26, config_pe_wy = 261` (below main window)
- `config_pe_open = 1` (playlist editor open by default in Winamp)

### Playlist window placement

| Option | Description | Selected |
|--------|-------------|----------|
| Separate NSPanel, docks below main | 275×116 pt panel, initial position below main, resizable, co-move | ✓ |
| Separate NSPanel, free-floating | Same but no default docking — user positions freely | |
| Main window expands downward | Main window grows vertically to reveal playlist below status bar | |

**User's choice:** Separate NSPanel docked below main window

### Toggle mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| Keyboard shortcut only (Alt+E) | Winamp default | |
| Button in main window chrome | PL button | |
| Both — shortcut + button | Alt+E keyboard + PL button in chrome | ✓ |

### Snap behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Fixed offset only | Opens at mainX, mainY+116, then independent | |
| Magnetic snap | Auto-aligns when dragged near main window | |
| Co-move (playlist follows main) | Panel moves with main window on drag | ✓ |

---

## Track Display Format

### Row information

| Option | Description | Selected |
|--------|-------------|----------|
| Winamp classic: #. Artist – Title [MM:SS] | ID3 tags via AVFoundation, filename fallback | ✓ |
| Filename + duration only | No ID3 tag lookup | |
| Filename only, no duration | Simplest approach | |

**User's choice:** Winamp classic format with ID3 fallback

### Active track marker

| Option | Description | Selected |
|--------|-------------|----------|
| Bold text + ▶ icon | Winamp-canonical, no background change | ✓ |
| Highlighted row background | Tinted background on active row | |
| Both bold + tinted row | Bold + icon + distinct background | |

---

## Persistence Format

### Save format

| Option | Description | Selected |
|--------|-------------|----------|
| JSON in Application Support | `~/Library/Application Support/Manzo/playlist.json` | ✓ |
| .m3u file | Extended M3U format, interoperable | |
| UserDefaults | Simple, no file management | |

**User's choice:** JSON with `{path, artist, title, duration}` schema (Phase 9 adds nullable `url`)

### Missing files policy

| Option | Description | Selected |
|--------|-------------|----------|
| Strikethrough, keep in list | User removes manually — no auto-pruning | ✓ |
| Silently remove missing tracks | Auto-filter on launch | |

---

## Playlist Model & AppDelegate Wiring

### Model location

| Option | Description | Selected |
|--------|-------------|----------|
| PlaylistManager class, owned by AppDelegate | Dedicated class, clean separation for Phase 9 | ✓ |
| AppDelegate directly | Inline state, simpler but grows AppDelegate | |

### Track removal

| Option | Description | Selected |
|--------|-------------|----------|
| Delete key only | Standard macOS | |
| Right-click context menu | More discoverable | |
| Both — Delete key + right-click | Power users + discoverability | ✓ |

**User notes:** Added a third method: visible [-] button in the bottom toolbar of the playlist
panel. All three methods call the same `PlaylistManager.remove(at:)`.

### Double-click behavior

| Option | Description | Selected |
|--------|-------------|----------|
| Jump to that track immediately | Close current, open + play clicked track | ✓ |
| Jump + spectrum flash | Same plus brief spectrum visual feedback | |

---

## Claude's Discretion

- `NSPanel` subclass vs plain `NSWindow` with `.nonactivatingPanel` behavior
- NSTableView cell rendering implementation (custom `NSTableCellView` vs attributed string)
- NSTableView drag-and-drop API version
- JSON autosave debounce strategy during rapid reorders
- Exact PL button placement in main window chrome (statusView vs titleView)
- Empty-state message in playlist panel when no tracks are loaded

## Deferred Ideas

- Magnetic snap (embwnd.cpp-style) — v2
- Non-MP3 file formats — v2 (ADVAUDIO-01)
- Transport control buttons in main chrome — separate phase concern
- Windowshade mode for playlist — v2
- Playlist sorting — backlog
- Drag from Finder into playlist panel — backlog
