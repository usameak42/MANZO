---
phase: 08-playlist-library
plan: "04"
subsystem: playlist-ui
tags: [NSTableView, drag-reorder, keyDown, context-menu, NSDraggingSource, AppKit]
dependency_graph:
  requires:
    - 08-01 (PlaylistManager.remove(at:) / move(from:to:))
    - 08-02 (ManzoPlaylistPanel NSPanel shell, ManzoPlaylistPanelDelegate protocol)
    - 08-03 (AppDelegate validateDrop + acceptDrop — parallel plan, not modified here)
  provides:
    - ManzoPlaylistPanel drag source registration (registerForDraggedTypes + setDraggingSourceOperationMask)
    - Delete key removal handler (D-13 path 1)
    - Right-click "Remove from Playlist" context menu (D-13 path 2)
  affects:
    - 08-03 (AppDelegate acceptDrop completes the drag-reorder round trip with this plan's drag source)
    - 08-05 (UAT: drag-reorder and removal paths verified end-to-end)
tech_stack:
  added: []
  patterns:
    - tableView.registerForDraggedTypes([.string]) — NSPasteboardType.string encodes row index
    - tableView.setDraggingSourceOperationMask([.move], forLocal: true) — local-only move
    - NSPanel.keyDown override for Delete/Forward-Delete keyCodes 51/117
    - NSMenu + NSMenuItem with target=self for right-click context menu
    - guard clickedRow >= 0 (T-08-15 threat mitigation)
key_files:
  created: []
  modified:
    - ManzoApp/ManzoApp/ManzoPlaylistPanel.swift
decisions:
  - "setupContextMenu() called at end of setupTableView() — collocated with drag registration so all table interaction config is in one method"
  - "keyDown override on NSPanel subclass (not NSTableView) — panel intercepts key events before table; correct for Delete key which acts on the selection, not a cell editor"
  - "T-08-15: guard clickedRow >= 0 in contextMenuRemove prevents action when right-clicking table header area or empty space"
metrics:
  duration: ~8m
  completed: 2026-04-24T12:14:00Z
  tasks_completed: 2
  tasks_total: 2
  files_created: 0
  files_modified: 1
---

# Phase 08 Plan 04: Drag Source Registration + Removal UX Summary

NSTableView drag-reorder client-side setup (`registerForDraggedTypes`, `setDraggingSourceOperationMask`) plus Delete key and right-click context menu removal paths added to `ManzoPlaylistPanel.swift` — completing LIB-02 (client side) and LIB-04 (paths 1 and 2).

## What Was Built

### ManzoPlaylistPanel.swift — Task 1: Drag Source Registration

Added to `setupTableView()` after the `tableView.target = self` line:

- `tableView.registerForDraggedTypes([.string])` — registers the panel as a drag drop destination; NSPasteboardItem with `.string` type carries the source row index as a String (written by `pasteboardWriterForRow` in AppDelegate, Plan 08-03)
- `tableView.setDraggingSourceOperationMask([.move], forLocal: true)` — constrains drag to local move operations only; no copy or cross-app drag
- `setupContextMenu()` call wired at end of `setupTableView()` so all table interaction configuration is initialized in one place

The `validateDrop` + `acceptDrop` NSTableViewDataSource methods that complete the round trip live in AppDelegate (Plan 08-03) — this plan does not touch AppDelegate.

### ManzoPlaylistPanel.swift — Task 2: Delete Key + Right-Click Menu (D-13 paths 1 and 2)

**keyDown override (D-13 path 1):**
- `override func keyDown(with event: NSEvent)` on `ManzoPlaylistPanel` (NSPanel subclass)
- keyCodes 51 (Delete/Backspace) and 117 (Forward Delete) trigger removal
- `guard tableView.selectedRow >= 0` prevents spurious delegate calls when nothing is selected
- All other keys fall through to `super.keyDown(with: event)`

**Right-click context menu (D-13 path 2):**
- `setupContextMenu()`: builds `NSMenu` with single `NSMenuItem` titled "Remove from Playlist" (UI-SPEC Copywriting Contract)
- `removeItem.target = self` — menu item targets the panel directly, not first responder
- `tableView.menu = menu` — AppKit shows this menu automatically on right-click / control-click
- `contextMenuRemove(_:)`: reads `tableView.clickedRow`, guards `>= 0` (T-08-15 mitigation), calls `playlistDelegate?.playlistPanel(self, didRequestRemoveAt: row)`

**Three LIB-04 removal paths are now complete across plans:**
1. Delete key — this plan (08-04)
2. Right-click "Remove from Playlist" menu — this plan (08-04)
3. [−] toolbar button — Plan 08-02 (`removeButtonClicked`)

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| `keyDown` override on `NSPanel`, not `NSTableView` | NSPanel is the key event responder when the panel is key window. Overriding at the panel level intercepts Delete before it reaches any cell editor, which is the correct Winamp behavior (row-level delete, not cell editing). |
| `setupContextMenu()` called inside `setupTableView()` | Collocates all NSTableView interaction configuration in one method — drag registration and context menu are both table-interaction concerns. Avoids a separate `setupInteractions()` callsite. |
| `guard clickedRow >= 0` in `contextMenuRemove` | T-08-15 mitigation: `clickedRow` is -1 when user right-clicks the table header or an empty area below the last row. The guard prevents out-of-range `didRequestRemoveAt` delegate calls. AppDelegate.removeTrackAt also guards `index >= 0, index < tracks.count` (defense in depth). |

## Deviations from Plan

None — plan executed exactly as written.

## xcodebuild Status

`** BUILD SUCCEEDED **` — xcodebuild exited 0 with no errors or warnings attributable to this plan's changes.

## Known Stubs

None introduced by this plan. The pre-existing `root.material = .hudWindow` stub in ManzoPlaylistPanel (inherited from Plan 08-02) remains — tracked in 08-02-SUMMARY.md.

## Threat Flags

None. Changes are confined to ManzoPlaylistPanel.swift with no new network endpoints, auth paths, or file access patterns. T-08-15 mitigation (`guard clickedRow >= 0`) implemented per threat register.

## Self-Check: PASSED

| Item | Status |
|------|--------|
| ManzoApp/ManzoApp/ManzoPlaylistPanel.swift modified | FOUND |
| grep registerForDraggedTypes | FOUND (line 202) |
| grep setDraggingSourceOperationMask | FOUND (line 203) |
| grep "override func keyDown" | FOUND (line 376) |
| grep "keyCode.*51" | FOUND (line 378) |
| grep "Remove from Playlist" | FOUND (line 392) |
| grep "tableView.menu" | FOUND (line 398) |
| AppDelegate.swift unchanged | CONFIRMED (0 diff lines) |
| Commit c53c9af (Task 1) | FOUND |
| Commit edb7849 (Task 2) | FOUND |
| xcodebuild BUILD SUCCEEDED | CONFIRMED |
