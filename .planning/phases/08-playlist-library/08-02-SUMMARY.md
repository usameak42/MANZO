---
phase: 08-playlist-library
plan: "02"
subsystem: playlist-ui
tags: [NSPanel, NSTableView, NeoAero, PlaylistRowView, PlaylistTrack, AppKit]
dependency_graph:
  requires:
    - 06-neo-aero (NeoAeroLayerFactory.make / makeSimplified)
    - 05-ui-shell (ManzoVisualStyle.load, ManzoWindow NSPanel pattern)
  provides:
    - ManzoPlaylistPanel (NSPanel subclass, NeoAero chrome, NSTableView shell)
    - PlaylistRowView (NSTableCellView subclass for 18pt rows)
    - ManzoPlaylistPanelDelegate (protocol for AppDelegate wiring in 08-03)
    - PlaylistTrack (Codable struct — also provided by 08-01, deduplicated on merge)
  affects:
    - 08-03 (AppDelegate wiring: creates ManzoPlaylistPanel, sets delegate, orders front)
tech_stack:
  added: []
  patterns:
    - NSPanel subclass with nonactivatingPanel + resizable styleMask
    - Single NSVisualEffectView at contentView root (CLAUDE.md one-vibrancy rule)
    - NeoAeroLayerFactory bodyFocus pattern (full on bodyView, simplified on titleView/toolbarView)
    - NSTableCellView subclass with configure(track:rowNum:isActive:) data method
    - NSTableRowView subclass for custom selection drawing
    - setEmptyStateVisible() toggling scrollView + tableView + emptyStateContainer
key_files:
  created:
    - ManzoApp/ManzoApp/ManzoPlaylistPanel.swift
    - ManzoApp/ManzoApp/PlaylistRowView.swift
    - ManzoApp/ManzoApp/PlaylistTrack.swift
  modified:
    - ManzoApp/ManzoApp.xcodeproj/project.pbxproj
decisions:
  - "NSPanel subclass (not plain NSWindow) for nonactivatingPanel behavior and co-move support"
  - "ManzoPlaylistPanelDelegate protocol decouples panel from AppDelegate — wired in 08-03"
  - "PlaylistTrack also created here (wave 1 parallel) to enable xcodebuild; deduplicated on merge"
  - "xcodegen run to regenerate xcodeproj after new Swift files added"
metrics:
  duration: ~27 minutes
  completed: 2026-04-24T11:57:58Z
  tasks_completed: 2
  tasks_total: 2
  files_created: 3
  files_modified: 1
---

# Phase 08 Plan 02: Playlist Panel UI Shell Summary

ManzoPlaylistPanel NSPanel subclass with NeoAero bodyFocus chrome (3-zone layout: 16pt titleView / bodyView / 16pt toolbarView), NSTableView 18pt rows, and PlaylistRowView NSTableCellView with normal/active/missing-file states in P3 colors.

## What Was Built

### ManzoPlaylistPanel.swift
- `NSPanel` subclass: `[.nonactivatingPanel, .resizable]` styleMask, 275pt fixed width, vertically resizable
- `isOpaque = false`, `backgroundColor = .clear` before `orderFront` (Phase 5 D-04 compositor pattern)
- `minSize = (275, 60)`, `maxSize = (275, .greatestFiniteMagnitude)` — width locked
- Single `.behindWindow` `NSVisualEffectView` at root (CLAUDE.md one-vibrancy constraint: count = 1)
- Three plain `NSView` zones (CLAUDE.md no-nested-vibrancy rule):
  - `titleView` (16pt): "PLAYLIST EDITOR" label, mouseDown drag region
  - `bodyView` (fills): NSScrollView + NSTableView + empty state overlay
  - `toolbarView` (16pt): [+] Add / [−] Remove buttons + "N tracks" count label
- `NeoAeroLayerFactory.make()` on `bodyView`, `makeSimplified()` on `titleView` and `toolbarView` (D-05 bodyFocus)
- `NSTableView`: 18pt row height, transparent background, `selectionHighlightStyle = .none`, no column header
- `setEmptyStateVisible(_ visible: Bool)`: hides `scrollView` + `tableView`, shows `emptyStateContainer`
- Empty state: "No tracks" (13pt P3(0.78,0.80,0.85,0.70)) + "Add tracks with + or drag files here." (11pt P3(0.78,0.80,0.85,0.45))
- `ManzoPlaylistPanelDelegate` protocol with `didRequestAdd`, `didRequestRemoveAt`, `didDoubleClickRow`
- `handleDoubleClick`: `guard row >= 0` (T-08-06 threat mitigation)

### PlaylistRowView.swift
- `NSTableCellView` subclass for 18pt playlist rows (Winamp canonical)
- `trackLabel` (NSTextField, 11pt system) + `durationLabel` (monospacedDigitSystemFont 11pt, right-aligned)
- `configure(track:rowNum:isActive:)` for three states:
  - **Normal**: P3(0.78,0.80,0.85,1.0) regular
  - **Active**: bold + `▶` prefix + P3(1.0,1.0,1.0,1.0) white (D-08)
  - **Missing file**: strikethroughStyle + P3(0.50,0.52,0.55,0.70) dim (D-10)
- 1pt `CALayer` separator at row bottom: P3(1.0,1.0,1.0,0.06) (UI-SPEC Row Separator)
- `ManzoPlaylistRowBackground: NSTableRowView` for custom selection: P3(0.20,0.40,0.65,0.40), cornerRadius=3

### PlaylistTrack.swift (wave 1 parallel copy)
- `Codable` struct: `path`, `artist?`, `title?`, `duration` (Double seconds)
- `isMissingFile`, `displayTitle`, `formattedDuration` computed properties
- Identical to 08-01 version — deduplicated by orchestrator on branch merge

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| `ManzoPlaylistPanelDelegate` protocol | Decouples panel from AppDelegate — AppDelegate wires in 08-03 without touching panel internals |
| `PlaylistTrack.swift` created in this worktree | Needed for xcodebuild; wave 1 parallel execution means 08-01 creates it on a separate branch; orchestrator deduplicates on merge |
| `xcodegen generate` run after adding files | project.yml sources glob `path: ManzoApp` auto-includes new `.swift` files; xcodeproj must be regenerated to reflect them |
| `setEmptyStateVisible`: both `scrollView.isHidden` + `tableView.isHidden` | Belt-and-suspenders: NSScrollView may not forward hide to document view on all AppKit versions |

## Deviations from Plan

### Deviation 1: Worktree path correction

**Found during:** Task 1 commit
**Issue:** Initial Write tool calls used `/Users/usameak42/Coding/MANZO/ManzoApp/ManzoApp/` (main repo checkout) instead of the worktree working directory `/Users/usameak42/Coding/MANZO/.claude/worktrees/agent-ad82777c690d5bd48/ManzoApp/ManzoApp/`. Task 1 commit accidentally landed on `main` branch.
**Fix:** Copied files to correct worktree path; committed all three files (PlaylistRowView, ManzoPlaylistPanel, PlaylistTrack) + regenerated xcodeproj to the correct worktree branch in Task 2 commit.
**Files modified:** All three new Swift files + project.pbxproj

### Deviation 2: PlaylistTrack.swift created in this plan

**Category:** Rule 3 (auto-fix blocking issue)
**Found during:** Task 2
**Issue:** `ManzoPlaylistPanel.swift` and `PlaylistRowView.swift` reference `PlaylistTrack` type. `PlaylistTrack.swift` is created by parallel wave 1 plan 08-01 on a separate worktree branch, so it doesn't exist in this worktree. Without it, xcodebuild fails.
**Fix:** Created `PlaylistTrack.swift` with identical content to 08-01's version. Orchestrator deduplicates on branch merge (no conflict: identical file content).
**Files added:** `ManzoApp/ManzoApp/PlaylistTrack.swift`

## xcodebuild Status

xcodebuild was attempted but blocked by the shell permission sandbox in the parallel worktree execution context. Static verification confirms:
- All required class declarations, method signatures, color patterns, and structural constraints are present
- NSVisualEffectView count = 1 (CLAUDE.md constraint)
- shouldRasterize not manually set (NeoAeroLayerFactory handles internally)
- No setFrameAutosaveName (correctly deferred to AppDelegate in 08-03)
- xcodegen successfully regenerated xcodeproj with all 3 new files (12 references in pbxproj)

xcodebuild will be verified by the orchestrator during the wave merge build.

## Known Stubs

| File | Line | Description |
|------|------|-------------|
| ManzoPlaylistPanel.swift | 91 | `root.material = .hudWindow` — TBD: replace with confirmed `.glass` case name when macOS 26 SDK name is confirmed. Carried from ManzoRootView.swift, not introduced by this plan. |

## Threat Flags

None. No new network endpoints, auth paths, or file access patterns introduced. The `guard row >= 0` mitigation for T-08-06 is implemented.

## Self-Check: PASSED

| Item | Status |
|------|--------|
| ManzoApp/ManzoApp/ManzoPlaylistPanel.swift | FOUND |
| ManzoApp/ManzoApp/PlaylistRowView.swift | FOUND |
| ManzoApp/ManzoApp/PlaylistTrack.swift | FOUND |
| Commit f12c4fb (Task 2) | FOUND |
| 08-02-SUMMARY.md | FOUND |
