import Foundation
import AVFoundation

// StoredTrack — data model for one playlist entry (Codable, persisted to JSON).
// Named StoredTrack to avoid collision with ManzoPlaylistPanel's PlaylistTrack view-model.
struct StoredTrack: Codable, Equatable {
    var path:     String
    var artist:   String?
    var title:    String?
    var duration: Double  // seconds; 0.0 = unknown
}

extension StoredTrack {

    var isMissingFile: Bool {
        !FileManager.default.fileExists(atPath: path)
    }

    private var filenameNoExt: String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    var displayTitle: String {
        if let a = artist, let t = title { return "\(a) – \(t)" }
        if let t = title  { return t }
        if let a = artist { return "\(a) – \(filenameNoExt)" }
        return filenameNoExt
    }

    var formattedDuration: String {
        guard duration > 0, duration.isFinite else { return "–:––" }
        let total = Int(duration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// PlaylistManager — owned by AppDelegate.
// All mutations call save() automatically (D-11: autosave after every mutation).
// Thread model: all public methods called on main thread; add(urls:) dispatches internally to background.
final class PlaylistManager {

    // MARK: - Public State

    var tracks: [StoredTrack] = []
    var currentIndex: Int = 0

    // MARK: - Init

    init() {
        load()
    }

    // MARK: - CRUD

    func add(urls: [URL], onAdded: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var newTracks: [StoredTrack] = []
            for url in urls {
                let asset = AVURLAsset(url: url)
                var artist:   String? = nil
                var title:    String? = nil
                var duration: Double  = 0

                let rawDuration = asset.duration.seconds
                duration = rawDuration.isNaN || rawDuration < 0 ? 0 : rawDuration
                for item in asset.commonMetadata {
                    if item.commonKey == .commonKeyArtist, let v = item.stringValue { artist = v }
                    if item.commonKey == .commonKeyTitle,  let v = item.stringValue { title  = v }
                }
                let track = StoredTrack(path: url.path, artist: artist, title: title, duration: duration)
                newTracks.append(track)
                NSLog("MANZO Phase 8: PlaylistManager.add — loaded %@ (%@)", url.lastPathComponent, track.formattedDuration)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.tracks.append(contentsOf: newTracks)
                self.save()
                NSLog("MANZO Phase 8: PlaylistManager.add — appended %d tracks, total=%d", newTracks.count, self.tracks.count)
                onAdded?()
            }
        }
    }

    func remove(at index: Int) {
        guard index >= 0, index < tracks.count else { return }
        tracks.remove(at: index)
        if index < currentIndex {
            currentIndex -= 1
        } else if index == currentIndex, currentIndex >= tracks.count {
            currentIndex = max(0, tracks.count - 1)
        }
        save()
        NSLog("MANZO Phase 8: PlaylistManager.remove — removed index=%d, currentIndex=%d, total=%d", index, currentIndex, tracks.count)
    }

    func move(from: Int, to: Int) {
        guard from >= 0, from < tracks.count,
              to   >= 0, to   <= tracks.count,
              from != to else { return }
        let track = tracks.remove(at: from)
        let insertAt = to > from ? to - 1 : to
        tracks.insert(track, at: insertAt)
        if currentIndex == from {
            currentIndex = insertAt
        } else if from < currentIndex, to > currentIndex {
            currentIndex -= 1
        } else if from > currentIndex, insertAt < currentIndex {
            currentIndex += 1
        } else if from > currentIndex, insertAt == currentIndex {
            currentIndex += 1
        }
        save()
        NSLog("MANZO Phase 8: PlaylistManager.move — from=%d to=%d, currentIndex=%d", from, to, currentIndex)
    }

    func next() -> StoredTrack? {
        let nextIndex = currentIndex + 1
        guard nextIndex < tracks.count else {
            NSLog("MANZO Phase 8: PlaylistManager.next — playlist exhausted at index=%d", currentIndex)
            return nil
        }
        currentIndex = nextIndex
        NSLog("MANZO Phase 8: PlaylistManager.next — advanced to index=%d, path=%@", currentIndex, tracks[currentIndex].path)
        return tracks[currentIndex]
    }

    func prev() -> StoredTrack? {
        guard currentIndex > 0 else {
            NSLog("MANZO Phase 8.1: PlaylistManager.prev — already at index 0, staying")
            return trackAt(0)
        }
        currentIndex -= 1
        NSLog("MANZO Phase 8.1: PlaylistManager.prev — moved to index=%d, path=%@",
              currentIndex, tracks[currentIndex].path)
        return tracks[currentIndex]
    }

    func trackAt(_ index: Int) -> StoredTrack? {
        guard index >= 0, index < tracks.count else { return nil }
        return tracks[index]
    }

    // MARK: - Persistence (D-09, D-11)

    func save() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let data = try? JSONEncoder().encode(tracks) else {
            NSLog("MANZO Phase 8: PlaylistManager.save — encode failed (unexpected)")
            return
        }
        try? data.write(to: playlistURL, options: .atomic)
        NSLog("MANZO Phase 8: PlaylistManager.save — %d tracks written to %@", tracks.count, playlistURL.path)
    }

    func load() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let data  = try? Data(contentsOf: playlistURL),
              let list  = try? JSONDecoder().decode([StoredTrack].self, from: data)
        else {
            NSLog("MANZO Phase 8: PlaylistManager.load — no playlist found, starting empty")
            return
        }
        tracks = list
        if currentIndex >= tracks.count { currentIndex = max(0, tracks.count - 1) }
        NSLog("MANZO Phase 8: PlaylistManager.load — loaded %d tracks from %@", tracks.count, playlistURL.path)
    }

    // MARK: - Private

    private var playlistURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Manzo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("playlist.json")
    }
}
