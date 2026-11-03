import AppKit

/// Colors and type for the notes window. The window is always dark, like a presenter display.
enum Theme {
    static let accent = NSColor(calibratedRed: 1.0, green: 0.79, blue: 0.32, alpha: 1)
    static let text = NSColor(white: 0.96, alpha: 1)
    static let secondary = NSColor(white: 1, alpha: 0.58)
    static let tertiary = NSColor(white: 1, alpha: 0.30)
    static let hover = NSColor(white: 1, alpha: 0.10)
    static let fill = NSColor(white: 1, alpha: 0.07)
    static let hairline = NSColor(white: 1, alpha: 0.08)
    static let clickThrough = NSColor(calibratedRed: 1.0, green: 0.64, blue: 0.12, alpha: 1)
}

/// A borderless icon button with a soft rounded hover background.
final class IconButton: NSButton {
    private var trackingArea: NSTrackingArea?
    private var hovering = false { didSet { refreshLook() } }

    /// Shows the icon in the accent color, for toggles that are on.
    var isOn = false { didSet { refreshLook() } }

    init(_ symbol: String, tip: String, size: CGFloat = 13, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        isBordered = false
        imagePosition = .imageOnly
        wantsLayer = true
        layer?.cornerRadius = 7
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 30).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        self.target = target
        self.action = action
        setSymbol(symbol, tip: tip, size: size)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func setSymbol(_ symbol: String, tip: String, size: CGFloat = 13) {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?.withSymbolConfiguration(config)
        toolTip = tip
        setAccessibilityLabel(tip)
        refreshLook()
    }

    override var isEnabled: Bool { didSet { refreshLook() } }

    private func refreshLook() {
        layer?.backgroundColor = (hovering && isEnabled ? Theme.hover : .clear).cgColor
        contentTintColor = isOn ? Theme.accent : (hovering ? Theme.text : Theme.secondary)
        alphaValue = isEnabled ? 1 : 0.3
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
}

/// The slide counter in the header ("3 / 12 ⌄"). Clicking it lists every slide to jump to.
final class SlidePill: NSView {
    var onClick: ((NSView) -> Void)?
    private let label = NSTextField(labelWithString: "")
    private let chevron = NSImageView()
    private var trackingArea: NSTrackingArea?

    var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }
    var isClickable = true { didSet { chevron.isHidden = !isClickable } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = Theme.fill.cgColor
        translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        label.textColor = Theme.text
        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        chevron.contentTintColor = Theme.secondary
        let stack = NSStackView(views: [label, chevron])
        stack.spacing = 5
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 11, bottom: 0, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 24),
        ])
        toolTip = "Jump to a slide"
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        if isClickable { layer?.backgroundColor = Theme.hover.cgColor }
    }
    override func mouseExited(with event: NSEvent) { layer?.backgroundColor = Theme.fill.cgColor }
    override func mouseDown(with event: NSEvent) { if isClickable { onClick?(self) } }
    override var mouseDownCanMoveWindow: Bool { false }
}

/// A thin progress track through the slides. Click or drag on it to jump.
final class SlideProgress: NSView {
    var count = 1 { didSet { needsDisplay = true } }
    var index = 0 { didSet { needsDisplay = true } }
    var onSelect: ((Int) -> Void)?

    override var mouseDownCanMoveWindow: Bool { false }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 20) }

    override func draw(_ dirtyRect: NSRect) {
        let h: CGFloat = 4
        let track = NSRect(x: 0, y: (bounds.height - h) / 2, width: bounds.width, height: h)
        Theme.fill.setFill()
        NSBezierPath(roundedRect: track, xRadius: h / 2, yRadius: h / 2).fill()
        let fraction = count <= 1 ? 1 : CGFloat(index + 1) / CGFloat(count)
        var done = track
        done.size.width = max(h, track.width * fraction)
        Theme.accent.setFill()
        NSBezierPath(roundedRect: done, xRadius: h / 2, yRadius: h / 2).fill()
    }

    override func mouseDown(with event: NSEvent) { select(event) }
    override func mouseDragged(with event: NSEvent) { select(event) }

    private func select(_ event: NSEvent) {
        guard count > 1, bounds.width > 0 else { return }
        let x = convert(event.locationInWindow, from: nil).x
        let i = Int((x / bounds.width) * CGFloat(count))
        onSelect?(min(max(i, 0), count - 1))
    }
}

/// A small rounded message near the top of the notes ("Saved", "Text 24 pt").
final class Toast: NSView {
    private let label = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?
    private(set) var isPersistent = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.backgroundColor = NSColor(white: 0, alpha: 0.72).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = Theme.hairline.cgColor
        translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = Theme.text
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 26),
        ])
        alphaValue = 0
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Shows a message. A persistent one stays until `dismiss()`.
    func show(_ text: String, persistent: Bool = false) {
        label.stringValue = text
        isPersistent = persistent
        hideWork?.cancel()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; animator().alphaValue = 1 }
        guard !persistent else { return }
        let work = DispatchWorkItem { [weak self] in self?.fadeOut() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    func dismiss() {
        isPersistent = false
        fadeOut()
    }

    private func fadeOut() {
        NSAnimationContext.runAnimationGroup { $0.duration = 0.3; animator().alphaValue = 0 }
    }
}

/// What the window shows when no notes are open: a clear way to open or write some.
final class EmptyStateView: NSView {
    var onOpen: (() -> Void)?
    var onWrite: (() -> Void)?
    var onOpenRecent: ((URL) -> Void)?

    private let recentStack = NSStackView()
    private var recents: [URL] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 56).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 56).isActive = true

        let title = NSTextField(labelWithString: "Drop your speaker notes here")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = Theme.text

        let subtitle = NSTextField(wrappingLabelWithString:
            "A Markdown or text file. Put a line of --- between slides.")
        subtitle.font = .systemFont(ofSize: 12.5)
        subtitle.textColor = Theme.secondary
        subtitle.alignment = .center
        subtitle.preferredMaxLayoutWidth = 300

        let open = NSButton(title: "Open Notes…", target: self, action: #selector(openTapped))
        open.bezelStyle = .rounded
        open.bezelColor = Theme.accent
        open.keyEquivalent = "\r"
        open.controlSize = .large
        let write = NSButton(title: "Write Notes", target: self, action: #selector(writeTapped))
        write.bezelStyle = .rounded
        write.controlSize = .large
        let buttons = NSStackView(views: [open, write])
        buttons.spacing = 10

        recentStack.orientation = .vertical
        recentStack.alignment = .centerX
        recentStack.spacing = 2

        let stack = NSStackView(views: [icon, title, subtitle, buttons, recentStack])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.setCustomSpacing(14, after: icon)
        stack.setCustomSpacing(18, after: subtitle)
        stack.setCustomSpacing(22, after: buttons)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func setRecents(_ urls: [URL]) {
        recents = Array(urls.prefix(4))
        recentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !recents.isEmpty else { return }
        let header = NSTextField(labelWithString: "RECENT")
        header.font = .systemFont(ofSize: 10, weight: .semibold)
        header.textColor = Theme.tertiary
        recentStack.addArrangedSubview(header)
        recentStack.setCustomSpacing(6, after: header)
        for (i, url) in recents.enumerated() {
            let b = NSButton(title: url.lastPathComponent, target: self, action: #selector(recentTapped(_:)))
            b.isBordered = false
            b.tag = i
            b.contentTintColor = Theme.accent
            b.attributedTitle = NSAttributedString(string: url.lastPathComponent, attributes: [
                .foregroundColor: Theme.accent, .font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
            ])
            b.toolTip = url.path
            recentStack.addArrangedSubview(b)
        }
    }

    @objc private func openTapped() { onOpen?() }
    @objc private func writeTapped() { onWrite?() }
    @objc private func recentTapped(_ sender: NSButton) {
        guard recents.indices.contains(sender.tag) else { return }
        onOpenRecent?(recents[sender.tag])
    }
}
