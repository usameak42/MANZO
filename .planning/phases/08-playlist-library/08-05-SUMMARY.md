---
phase: 08-playlist-library
plan: "05"
subsystem: uat
tags: [uat, human-verify, playlist, LIB-01, LIB-02, LIB-03, LIB-04]
dependency_graph:
  requires:
    - 08-01 (PlaylistTrack model + PlaylistManager)
    - 08-02 (ManzoPlaylistPanel UI shell)
    - 08-03 (AppDelegate full integration)
    - 08-04 (Drag source + removal UX)
  provides:
    - Phase 8 UAT sign-off
    - 6 gap-closure fixes applied during UAT
key_files:
  created:
    - .planning/phases/08-playlist-library/08-05-BUILD-LOG.md
  modified:
    - ManzoApp/ManzoApp/AppDelegate.swift
    - ManzoApp/ManzoApp/ManzoPlaylistPanel.swift
    - ManzoApp/ManzoApp/ManzoRootView.swift
    - ManzoApp/ManzoApp/ManzoWindow.swift
    - ManzoApp/ManzoApp/PlaylistRowView.swift
metrics:
  completed: 2026-04-24
  tasks_completed: 2
  tasks_total: 2
---

# Phase 08 Plan 05: End-to-End UAT Summary

## Build Result

`** BUILD SUCCEEDED **` — clean build, zero errors, zero warnings.

All structural acceptance checks passed at Task 1:
- PlaylistTrack.swift, PlaylistManager.swift, ManzoPlaylistPanel.swift, PlaylistRowView.swift exist
- `trackQueue` — 0 live references in AppDelegate
- `var playlistManager` owned by AppDelegate — confirmed
- `applicationSupportDirectory` persistence path — confirmed
- Alt+E (`keyEquivalent: "e"` + `.option`) — confirmed
- `acceptDrop` drag-reorder handler — confirmed
- All three LIB-04 removal paths confirmed in source

## LIB Requirements — UAT Results

| Requirement | Description | Result |
|-------------|-------------|--------|
| LIB-01 | NSOpenPanel adds MP3 files to playlist | PASS |
| LIB-02 | Drag-reorder changes playback sequence | PASS |
| LIB-03 | Playlist restored on relaunch (JSON persistence) | PASS |
| LIB-04 | Three removal paths work without crash | PASS |

Human UAT sign-off: **approved**

## Gap-Closure Fixes Applied During UAT

Six issues surfaced during UAT rounds and fixed inline before approval:

| Fix | File | Change |
|-----|------|--------|
| manzo_stop() before track switch | AppDelegate.swift | Added `manzo_stop(handle)` before `manzo_close` in `jumpToTrack` — prevents second cpal stream overlapping on double-click |
| Co-move lag | ManzoWindow.swift, ManzoRootView.swift, AppDelegate.swift | Replaced `NSWindow.didMoveNotification` with `ManzoWindow.mouseDragged` + `onWindowMoved` closure; panel follows in real time |
| Row height not applying | AppDelegate.swift | `tableView(_:heightOfRow:)` delegate was returning 18 hardcoded, overriding `rowHeight = 24`; fixed to 24 |
| Selection highlight invisible | PlaylistRowView.swift | Replaced `drawSelection` (Core Graphics — occluded by cell view layers) with a `CALayer` sublayer (`selectionLayer`) on `ManzoPlaylistRowBackground` |
| Fn+Delete only for removal | ManzoPlaylistPanel.swift | Removed keyCode 51 (Backspace) — only keyCode 117 (Fn+Delete) now triggers row removal |
| Panel width too narrow | ManzoPlaylistPanel.swift | `kPanelWidth` 275→350 pt; propagates to contentRect, minSize, maxSize, column width |
| Marquee for active track | PlaylistRowView.swift | Added `marqueeContainer` clipping view + `CAKeyframeAnimation` scrolling active track title at 40 pt/sec with 1.5 s pause at each end |

## playlist.json Persistence

`~/Library/Application Support/Manzo/playlist.json` — valid JSON array written after adding tracks; restored on relaunch. Confirmed during LIB-03 UAT.

## Known Scope Note

UI redesign (transport buttons, LCD display, seek bar) deferred to Phase 8.1 (already planned) and a future Claude Design handoff.

## Self-Check: PASSED

| Item | Status |
|------|--------|
| BUILD SUCCEEDED | CONFIRMED |
| LIB-01 NSOpenPanel | PASS |
| LIB-02 drag-reorder | PASS |
| LIB-03 JSON persistence | PASS |
| LIB-04 three removal paths | PASS |
| Human UAT checkpoint | approved |
| 6 gap-closure fixes committed | CONFIRMED |
