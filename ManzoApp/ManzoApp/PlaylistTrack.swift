import Foundation

// PlaylistTrack — value type representing one playlist entry.
// Codable: encodes to/from JSON at ~/Library/Application Support/Manzo/playlist.json (D-09).
// artist and title are optional — nil encodes as absent JSON key (Phase 9 forward-compat: nullable url will be added).
// duration is in seconds (Double) — 0.0 means unknown (AVFoundation returned NaN or negative).
struct PlaylistTrack: Codable, Equatable {
    var path:     String
    var artist:   String?
    var title:    String?
    var duration: Double  // seconds; 0.0 = unknown
}

extension PlaylistTrack {

    // True when the file is no longer present on disk (D-10: keep in list, show strikethrough).
    var isMissingFile: Bool {
        !FileManager.default.fileExists(atPath: path)
    }

    // Filename without extension — used as title fallback (D-06).
    private var filenameNoExt: String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    // Winamp row format: "{Artist} – {Title}" or "{filename}" fallback (D-06).
    var displayTitle: String {
        if let a = artist, let t = title { return "\(a) – \(t)" }
        if let t = title  { return t }
        if let a = artist { return "\(a) – \(filenameNoExt)" }
        return filenameNoExt
    }

    // "[MM:SS]" formatted duration; "–:––" when unknown (D-07, UI-SPEC).
    var formattedDuration: String {
        guard duration > 0, duration.isFinite else { return "–:––" }
        let total = Int(duration)
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
