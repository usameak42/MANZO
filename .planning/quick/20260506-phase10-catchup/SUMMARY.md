---
title: Phase 10.1 ad-hoc work catchup
status: complete
completed: 2026-05-06
commits:
  - 9cc0522  # feat(streaming): yt-dlp+ffmpeg→Rust pipeline, ManzoOnlineQueue, ONLINE tab
  - 2eb1418  # feat(streaming): manzo_open_url FFI — incremental curl stream
  - 49c9542  # fix(playlist): URL input UX, onRemoveTracks, canBecomeKey
---

# Summary

All Phase 10.1 ad-hoc work committed and GSD state updated.

## What Was Done

### Phase 10.1 Streaming Prototype (commit 9cc0522)
- yt-dlp `--get-url` → CDN URL → ffmpeg `pipe:1` → `/tmp/manzo_stream.mp3` → Rust pipeline
- 512 KB buffer threshold before calling `manzo_open()` + `manzo_play()`
- `ManzoOnlineQueue.swift` — source filter model, `MockOnlineSourceAdapter`, add/play/remove
- `ManzoPlaylistPanel.swift` rewritten with LOCAL + ONLINE tabs (540pt wide)
- `stripBinaryQuarantines()` extended to cover both yt-dlp and ffmpeg

**Known limitation at time of commit:** `manzo_open()` reads entire file into memory
(`std::fs::read`), so only ~30s plays before ENDED fires.

### manzo_open_url FFI (commit 2eb1418)
- New `manzo_open_url(url, ytdlp_path)` Rust FFI function
- Resolves CDN URL via yt-dlp synchronously, then streams via curl on background thread
- `StreamSource` enum gates seek behavior (no-op for URL handles)
- `stream_rx: Option<mpsc::Receiver<Vec<u8>>>` feeds mpg123 continuously
- Fixes the 512 KB truncation limitation

### Playlist Panel UX Fixes (commit 49c9542)
- `canBecomeKey = true` — URL text field now focusable and typeable
- `onRemoveTracks` bug fix — was always removing playing track; now removes selected row
  (`playlistPanel.currentIndex` instead of `playlistManager.currentIndex`)
- `CenteredTextFieldCell` — cursor and typed text vertically centered in input box
- ADD button label: `SUBMIT ↵` when clipboard URL ghost hint active, `ADD ↵` when URL in field
- Ghost hint: removed `⏎ paste` prefix, shows URL only, clipped to fieldRect (no overflow)
- Placeholder hidden when ghost hint visible (no overlap artifact)

## State Updates
- STATE.md: Phase 10.1 → "In Progress", last_updated → 2026-05-06, Last Activity updated
- ROADMAP.md: Phase 10.1 progress table → "In progress"
