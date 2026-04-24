import AppKit

// PlaylistRowView — NSTableCellView subclass for one playlist row.
// Row height: 18 pt (Winamp canonical from draw_pe.cpp — UI-SPEC.md).
// All colors P3 CGColor (CLAUDE.md constraint).
// wantsLayer = true + plain CALayer — no nested NSVisualEffectView (Phase 5 spike 007 rule).
final class PlaylistRowView: NSTableCellView {

    private let p3 = CGColorSpace(name: CGColorSpace.displayP3)!

    // Track label: "{N}. {Artist} – {Title}"
    let trackLabel = NSTextField(labelWithString: "")
    // Duration label: "[MM:SS]" — monospaced digits, right-aligned
    let durationLabel = NSTextField(labelWithString: "")
    // 1 pt separator at bottom (UI-SPEC: Row Separator section)
    private let separatorLayer = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        setupTextFields()
        setupSeparator()
        NSLog("MANZO Phase 8: PlaylistRowView.init — 18pt row cell created")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used — code-only UI") }

    private func setupTextFields() {
        // trackLabel: system font 11pt, left-aligned, P3 text color set in configure()
        trackLabel.font = NSFont.systemFont(ofSize: 11)
        trackLabel.isBezeled        = false
        trackLabel.isEditable       = false
        trackLabel.backgroundColor  = .clear
        trackLabel.drawsBackground  = false
        trackLabel.lineBreakMode    = .byTruncatingTail
        trackLabel.translatesAutoresizingMaskIntoConstraints = false

        // durationLabel: monospaced digit system font 11pt, right-aligned (UI-SPEC Typography)
        durationLabel.font          = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        durationLabel.isBezeled     = false
        durationLabel.isEditable    = false
        durationLabel.backgroundColor = .clear
        durationLabel.drawsBackground = false
        durationLabel.alignment     = .right
        durationLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(trackLabel)
        addSubview(durationLabel)

        // durationLabel: fixed 36 pt width, right-aligned with 8 pt right inset (UI-SPEC spacing)
        NSLayoutConstraint.activate([
            durationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            durationLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            durationLabel.widthAnchor.constraint(equalToConstant: 36),

            trackLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            trackLabel.trailingAnchor.constraint(equalTo: durationLabel.leadingAnchor, constant: -6),
            trackLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func setupSeparator() {
        // 1 pt CALayer divider at bottom of row — P3(1.0,1.0,1.0,0.06) (UI-SPEC Row Separator)
        separatorLayer.backgroundColor = CGColor(colorSpace: p3, components: [1.0, 1.0, 1.0, 0.06])
        layer?.addSublayer(separatorLayer)
    }

    override func layout() {
        super.layout()
        // Position separator at bottom of row, full width.
        separatorLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1)
    }

    // MARK: - Configuration

    /// Configure the row cell for a given track and playback state.
    /// Called by NSTableViewDelegate.tableView(_:viewFor:row:).
    func configure(track: PlaylistTrack, rowNum: Int, isActive: Bool) {
        let p3cs = CGColorSpace(name: CGColorSpace.displayP3)!

        if track.isMissingFile {
            // Missing file: strikethrough + dimmed P3(0.50,0.52,0.55,0.70) — D-10
            let dimColor = NSColor(cgColor: CGColor(colorSpace: p3cs, components: [0.50, 0.52, 0.55, 0.70])!)!
            let text = "\(rowNum). \(track.displayTitle)"
            let attrs: [NSAttributedString.Key: Any] = [
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: dimColor,
                .font: NSFont.systemFont(ofSize: 11),
            ]
            trackLabel.attributedStringValue = NSAttributedString(string: text, attributes: attrs)
            durationLabel.attributedStringValue = NSAttributedString(
                string: "[\(track.formattedDuration)]",
                attributes: [.foregroundColor: dimColor, .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)]
            )
        } else if isActive {
            // Active track: bold + ▶ prefix + pure white P3(1.0,1.0,1.0,1.0) — D-08
            let whiteColor = NSColor(cgColor: CGColor(colorSpace: p3cs, components: [1.0, 1.0, 1.0, 1.0])!)!
            let text = "▶ \(rowNum). \(track.displayTitle)"
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: whiteColor,
                .font: NSFont.boldSystemFont(ofSize: 11),
            ]
            trackLabel.attributedStringValue = NSAttributedString(string: text, attributes: attrs)
            durationLabel.attributedStringValue = NSAttributedString(
                string: "[\(track.formattedDuration)]",
                attributes: [.foregroundColor: whiteColor, .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)]
            )
        } else {
            // Normal row: P3(0.78,0.80,0.85,1.0), regular weight — UI-SPEC Row body
            let normalColor = NSColor(cgColor: CGColor(colorSpace: p3cs, components: [0.78, 0.80, 0.85, 1.0])!)!
            let text = "\(rowNum). \(track.displayTitle)"
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: normalColor,
                .font: NSFont.systemFont(ofSize: 11),
            ]
            trackLabel.attributedStringValue = NSAttributedString(string: text, attributes: attrs)
            durationLabel.attributedStringValue = NSAttributedString(
                string: "[\(track.formattedDuration)]",
                attributes: [.foregroundColor: normalColor, .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)]
            )
        }
    }
}

// ManzoPlaylistRowBackground — NSTableRowView subclass for custom selection drawing.
// NSTableView.selectionHighlightStyle = .none disables system default; we draw our own.
final class ManzoPlaylistRowBackground: NSTableRowView {

    private let p3 = CGColorSpace(name: CGColorSpace.displayP3)!

    // With selectionHighlightStyle = .none, AppKit may not trigger setNeedsDisplay
    // when isSelected changes — force redraw manually.
    override var isSelected: Bool { didSet { needsDisplay = true } }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        let selColor = NSColor(cgColor: CGColor(colorSpace: p3, components: [0.15, 0.45, 0.85, 0.70])!)!
        selColor.setFill()
        let selRect = bounds.insetBy(dx: 2, dy: 1)
        let path = NSBezierPath(roundedRect: selRect, xRadius: 3, yRadius: 3)
        path.fill()
    }
}
