import AppKit

// PlaylistRowView — NSTableCellView subclass for one playlist row.
// Row height: 24 pt (UAT-adjusted).
// All colors P3 CGColor (CLAUDE.md constraint).
// wantsLayer = true + plain CALayer — no nested NSVisualEffectView (Phase 5 spike 007 rule).
//
// Marquee: trackLabel lives inside marqueeContainer (masksToBounds clip). Frame-based positioning
// avoids AutoLayout/CAAnimation conflicts. CAKeyframeAnimation scrolls text for active track.
final class PlaylistRowView: NSTableCellView {

    private let p3 = CGColorSpace(name: CGColorSpace.displayP3)!

    // Track label — frame-based inside marqueeContainer (no AutoLayout in the container).
    let trackLabel    = NSTextField(labelWithString: "")
    // Duration label — AutoLayout in PlaylistRowView.
    let durationLabel = NSTextField(labelWithString: "")
    // Clips marquee overflow; trackLabel translates inside.
    private let marqueeContainer = NSView()
    // 1 pt separator at bottom (UI-SPEC: Row Separator section).
    private let separatorLayer = CALayer()
    // Preserved between configure() and the next layout pass that starts/stops marquee.
    private var isActiveTrack = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupTextFields()
        setupSeparator()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used — code-only UI") }

    // MARK: - Setup

    private func setupTextFields() {
        // marqueeContainer: clips the scrolling trackLabel.
        marqueeContainer.wantsLayer = true
        marqueeContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(marqueeContainer)

        // trackLabel: frame-based inside marqueeContainer; AutoLayout stays out of the container.
        trackLabel.font            = NSFont.systemFont(ofSize: 11)
        trackLabel.isBezeled       = false
        trackLabel.isEditable      = false
        trackLabel.backgroundColor = .clear
        trackLabel.drawsBackground = false
        trackLabel.lineBreakMode   = .byClipping  // marquee handles overflow; no ellipsis
        trackLabel.wantsLayer      = true
        marqueeContainer.addSubview(trackLabel)

        // durationLabel: fixed 36 pt, AutoLayout in PlaylistRowView (not in container).
        durationLabel.font            = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        durationLabel.isBezeled       = false
        durationLabel.isEditable      = false
        durationLabel.backgroundColor = .clear
        durationLabel.drawsBackground = false
        durationLabel.alignment       = .right
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(durationLabel)

        NSLayoutConstraint.activate([
            durationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            durationLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            durationLabel.widthAnchor.constraint(equalToConstant: 36),

            marqueeContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            marqueeContainer.trailingAnchor.constraint(equalTo: durationLabel.leadingAnchor, constant: -6),
            marqueeContainer.topAnchor.constraint(equalTo: topAnchor),
            marqueeContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func setupSeparator() {
        separatorLayer.backgroundColor = CGColor(colorSpace: p3, components: [1.0, 1.0, 1.0, 0.06])
        layer?.addSublayer(separatorLayer)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // masksToBounds realized after the layer is created.
        marqueeContainer.layer?.masksToBounds = true
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        separatorLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1)
        updateTrackLabelFrame()
        updateMarquee()
    }

    private func updateTrackLabelFrame() {
        let h = trackLabel.intrinsicContentSize.height
        let y = max(0, (marqueeContainer.bounds.height - h) / 2)
        // +4 pt avoids edge clipping artefact on last glyph.
        let textWidth = trackLabel.attributedStringValue.size().width + 4
        trackLabel.frame = CGRect(
            x: 0, y: y,
            width: max(textWidth, marqueeContainer.bounds.width),
            height: h
        )
    }

    private func updateMarquee() {
        let containerWidth = marqueeContainer.bounds.width
        guard containerWidth > 0 else { return }
        let overflow = trackLabel.frame.width - containerWidth
        if isActiveTrack && overflow > 4 {
            startMarquee(overflow: overflow)
        } else {
            stopMarquee()
        }
    }

    // MARK: - Marquee

    private func startMarquee(overflow: CGFloat) {
        // Skip if the same animation is already running with identical overflow.
        if let existing = trackLabel.layer?.animation(forKey: "marquee") as? CAKeyframeAnimation,
           abs((existing.values?.last as? CGFloat ?? 0) - (-overflow)) < 1 { return }

        trackLabel.layer?.removeAnimation(forKey: "marquee")
        let speed: Double  = 40    // pt / sec
        let pause: Double  = 1.5   // seconds at each end before scrolling
        let scroll = Double(overflow) / speed
        let total  = scroll + pause * 2

        let anim = CAKeyframeAnimation(keyPath: "transform.translation.x")
        anim.values   = [0, 0, -overflow, -overflow]
        anim.keyTimes = [0,
                         NSNumber(value: pause / total),
                         NSNumber(value: (pause + scroll) / total),
                         1.0]
        anim.duration         = total
        anim.repeatCount      = .infinity
        anim.calculationMode  = .linear
        anim.isRemovedOnCompletion = false
        trackLabel.layer?.add(anim, forKey: "marquee")
    }

    private func stopMarquee() {
        guard trackLabel.layer?.animation(forKey: "marquee") != nil else { return }
        trackLabel.layer?.removeAnimation(forKey: "marquee")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLabel.layer?.transform = CATransform3DIdentity
        CATransaction.commit()
    }

    // MARK: - Configuration

    func configure(track: PlaylistTrack, rowNum: Int, isActive: Bool) {
        isActiveTrack = isActive
        let p3cs = CGColorSpace(name: CGColorSpace.displayP3)!

        if track.isMissingFile {
            let dimColor = NSColor(cgColor: CGColor(colorSpace: p3cs,
                components: [0.50, 0.52, 0.55, 0.70])!)!
            let attrs: [NSAttributedString.Key: Any] = [
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor:    dimColor,
                .font:               NSFont.systemFont(ofSize: 11),
            ]
            trackLabel.attributedStringValue = NSAttributedString(
                string: "\(rowNum). \(track.displayTitle)", attributes: attrs)
            durationLabel.attributedStringValue = NSAttributedString(
                string: "[\(track.formattedDuration)]",
                attributes: [.foregroundColor: dimColor,
                             .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)])

        } else if isActive {
            let white = NSColor(cgColor: CGColor(colorSpace: p3cs,
                components: [1.0, 1.0, 1.0, 1.0])!)!
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: white,
                .font:            NSFont.boldSystemFont(ofSize: 11),
            ]
            trackLabel.attributedStringValue = NSAttributedString(
                string: "▶ \(rowNum). \(track.displayTitle)", attributes: attrs)
            durationLabel.attributedStringValue = NSAttributedString(
                string: "[\(track.formattedDuration)]",
                attributes: [.foregroundColor: white,
                             .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)])

        } else {
            let normal = NSColor(cgColor: CGColor(colorSpace: p3cs,
                components: [0.78, 0.80, 0.85, 1.0])!)!
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: normal,
                .font:            NSFont.systemFont(ofSize: 11),
            ]
            trackLabel.attributedStringValue = NSAttributedString(
                string: "\(rowNum). \(track.displayTitle)", attributes: attrs)
            durationLabel.attributedStringValue = NSAttributedString(
                string: "[\(track.formattedDuration)]",
                attributes: [.foregroundColor: normal,
                             .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)])
        }

        // Trigger layout pass → updateTrackLabelFrame() → updateMarquee().
        needsLayout = true
    }
}

// ManzoPlaylistRowBackground — NSTableRowView with CALayer-based selection highlight.
// Uses a sublayer instead of drawSelection() because drawSelection (Core Graphics) is
// occluded by cell view layers when the table is layer-backed (wantsLayer on cell views).
final class ManzoPlaylistRowBackground: NSTableRowView {

    private let selectionLayer = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        selectionLayer.backgroundColor = CGColor(colorSpace: p3,
            components: [0.15, 0.45, 0.85, 0.70])
        selectionLayer.cornerRadius = 3
        selectionLayer.isHidden = true
        layer?.addSublayer(selectionLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override var isSelected: Bool {
        didSet { selectionLayer.isHidden = !isSelected }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        selectionLayer.frame = bounds.insetBy(dx: 2, dy: 1)
        CATransaction.commit()
    }

    // Suppress default CG drawing — selection is handled by selectionLayer.
    override func drawSelection(in dirtyRect: NSRect) {}
}
