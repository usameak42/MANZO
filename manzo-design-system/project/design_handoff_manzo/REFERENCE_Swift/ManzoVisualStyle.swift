import AppKit

// MARK: - UserDefaults Key (D-02, CONTEXT.md)
private let kVisualStyleKey = "ManzoVisualStyle"

// MARK: - PanelLayout (D-03)
// Controls how chrome layers are distributed across the 275×116 pt window.
enum PanelLayout: String, Codable {
    case unifiedSlab   // default — single glass slab spans full root view
    case threeBubbles  // three independent r=10 containers, one per panel
    case bodyFocus     // bodyView full 5-layer stack; titleView/statusView base+rim only
}

// MARK: - ColorTheme (D-04)
// Controls the gradient palette for the Neo-Aero stack.
// All P3 values defined in NeoAeroLayer.swift (factory).
enum ColorTheme: String, Codable {
    case winampClassic  // P3(0.09,0.09,0.16) top / P3(0.22,0.22,0.35) bottom / P3(0.74,0.81,0.84)@50% specular
    case neoAero        // P3(0.05,0.78,0.82) top / P3(0.02,0.52,0.60) bottom — outside sRGB
    case indigoTeal     // P3(0.04,0.09,0.20) top / P3(0.10,0.22,0.28) bottom — ice blue specular
    case wszSkin        // v2 placeholder — NO implementation in Phase 6
}

// MARK: - ManzoVisualStyle (D-02)
// Persist to UserDefaults via Codable. Three independent axes.
// Default: .unifiedSlab / .winampClassic / wetFloor=false (D-02).
struct ManzoVisualStyle: Codable {
    var panelLayout: PanelLayout
    var colorTheme:  ColorTheme
    var wetFloor:    Bool

    static let `default` = ManzoVisualStyle(
        panelLayout: .unifiedSlab,
        colorTheme:  .winampClassic,
        wetFloor:    false
    )

    // Load from UserDefaults; returns .default on missing or corrupt data.
    static func load() -> ManzoVisualStyle {
        guard let data  = UserDefaults.standard.data(forKey: kVisualStyleKey),
              let style = try? JSONDecoder().decode(ManzoVisualStyle.self, from: data)
        else {
            NSLog("MANZO Phase 6: ManzoVisualStyle.load — no persisted style, using default")
            return .default
        }
        NSLog("MANZO Phase 6: ManzoVisualStyle.load — layout=%@, theme=%@",
              style.panelLayout.rawValue, style.colorTheme.rawValue)
        return style
    }

    // Save to UserDefaults. Fails silently on encode error (should never happen for Codable).
    func save() {
        guard let data = try? JSONEncoder().encode(self) else {
            NSLog("MANZO Phase 6: ManzoVisualStyle.save — encode failed (unexpected)")
            return
        }
        UserDefaults.standard.set(data, forKey: kVisualStyleKey)
        NSLog("MANZO Phase 6: ManzoVisualStyle.save — layout=%@, theme=%@, wetFloor=%d",
              panelLayout.rawValue, colorTheme.rawValue, wetFloor ? 1 : 0)
    }
}
