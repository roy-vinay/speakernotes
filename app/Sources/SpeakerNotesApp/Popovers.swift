import AppKit

private func label(_ text: String, size: CGFloat = 11, weight: NSFont.Weight = .semibold,
                   color: NSColor = Theme.secondary) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = .systemFont(ofSize: size, weight: weight)
    l.textColor = color
    return l
}

private func section(_ title: String, _ control: NSView) -> NSStackView {
    let s = NSStackView(views: [label(title.uppercased(), size: 10), control])
    s.orientation = .vertical
    s.alignment = .leading
    s.spacing = 6
    return s
}

// MARK: - Text (Aa)

/// Size, typeface and line spacing, applied as you change them.
final class TextSettingsViewController: NSViewController {
    var onChange: (() -> Void)?

    private let sizeSlider = NSSlider(value: 22, minValue: 12, maxValue: 64, target: nil, action: nil)
    private let sizeValue = label("22 pt", size: 12, weight: .medium, color: Theme.text)
    private let typeface = NSSegmentedControl(labels: Typeface.allCases.map(\.title), trackingMode: .selectOne,
                                              target: nil, action: nil)
    private let spacingSlider = NSSlider(value: 1.25, minValue: 1.0, maxValue: 2.0, target: nil, action: nil)
    private let spacingValue = label("1.25", size: 12, weight: .medium, color: Theme.text)

    override func loadView() {
        sizeSlider.target = self
        sizeSlider.action = #selector(changed)
        sizeSlider.isContinuous = true
        spacingSlider.target = self
        spacingSlider.action = #selector(changed)
        spacingSlider.isContinuous = true
        typeface.target = self
        typeface.action = #selector(changed)
        typeface.segmentStyle = .rounded

        for slider in [sizeSlider, spacingSlider] {
            slider.widthAnchor.constraint(equalToConstant: 200).isActive = true
        }
        sizeValue.widthAnchor.constraint(equalToConstant: 46).isActive = true
        spacingValue.widthAnchor.constraint(equalToConstant: 46).isActive = true

        let small = NSImageView(image: NSImage(systemSymbolName: "textformat.size.smaller", accessibilityDescription: nil)!)
        let big = NSImageView(image: NSImage(systemSymbolName: "textformat.size.larger", accessibilityDescription: nil)!)
        [small, big].forEach { $0.contentTintColor = Theme.secondary }
        let sizeRow = NSStackView(views: [small, sizeSlider, big, sizeValue])
        sizeRow.spacing = 8
        let spacingRow = NSStackView(views: [spacingSlider, spacingValue])
        spacingRow.spacing = 8

        let title = label("Text", size: 13, weight: .semibold, color: Theme.text)
        let stack = NSStackView(views: [title, section("Size", sizeRow), section("Typeface", typeface),
                                        section("Line spacing", spacingRow)])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        view = stack
        refresh()
    }

    func refresh() {
        sizeSlider.doubleValue = Double(Settings.fontSize)
        sizeValue.stringValue = "\(Int(Settings.fontSize)) pt"
        typeface.selectedSegment = Typeface.allCases.firstIndex(of: Settings.typeface) ?? 0
        spacingSlider.doubleValue = Double(Settings.lineSpacing)
        spacingValue.stringValue = String(format: "%.2f", Settings.lineSpacing)
    }

    @objc private func changed() {
        Settings.fontSize = CGFloat(sizeSlider.doubleValue.rounded())
        Settings.typeface = Typeface.allCases[max(0, typeface.selectedSegment)]
        Settings.lineSpacing = CGFloat((spacingSlider.doubleValue * 20).rounded() / 20)
        refresh()
        onChange?()
    }
}

// MARK: - Emphasis (✨)

/// Tell it what to emphasize in plain words; see and remove what's emphasized.
final class EmphasisViewController: NSViewController, NSTextFieldDelegate {
    /// Runs an instruction. The Bool is true for all slides, false for the current slide.
    var onRun: ((String, Bool) -> Void)?
    var onCancel: (() -> Void)?
    var onRemove: ((UUID) -> Void)?
    var onChangeStyle: ((UUID, EmphasisStyle) -> Void)?
    var onClearAll: (() -> Void)?

    private let field = NSTextField()
    private let scope = NSSegmentedControl(labels: ["All slides", "This slide"], trackingMode: .selectOne,
                                           target: nil, action: nil)
    private let runButton = NSButton(title: "Emphasize", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")
    private let spinner = NSProgressIndicator()
    private let rulesStack = NSStackView()
    private let clearButton = NSButton(title: "Clear All", target: nil, action: nil)
    private let rulesHeader = label("EMPHASIZED", size: 10)
    private(set) var isRunning = false

    override func loadView() {
        field.placeholderString = Assistant.isAvailable
            ? "e.g. Highlight the names of the engines"
            : "Type a word or phrase to highlight"
        field.font = .systemFont(ofSize: 13)
        field.bezelStyle = .roundedBezel
        field.delegate = self
        field.target = self
        field.action = #selector(run)
        field.widthAnchor.constraint(equalToConstant: 300).isActive = true

        scope.selectedSegment = 0
        scope.segmentStyle = .rounded
        scope.controlSize = .small
        runButton.target = self
        runButton.action = #selector(run)
        runButton.bezelStyle = .rounded
        runButton.bezelColor = Theme.accent
        let controls = NSStackView(views: [scope, NSView(), runButton])
        controls.widthAnchor.constraint(equalToConstant: 300).isActive = true

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        status.font = .systemFont(ofSize: 11.5)
        status.textColor = Theme.secondary
        status.preferredMaxLayoutWidth = 276
        let statusRow = NSStackView(views: [spinner, status])
        statusRow.spacing = 6
        statusRow.alignment = .top

        rulesStack.orientation = .vertical
        rulesStack.alignment = .leading
        rulesStack.spacing = 4
        clearButton.target = self
        clearButton.action = #selector(clearAll)
        clearButton.isBordered = false
        clearButton.contentTintColor = Theme.secondary
        clearButton.font = .systemFont(ofSize: 11)

        let title = label("Emphasize", size: 13, weight: .semibold, color: Theme.text)
        let hint = label(Assistant.isAvailable
                         ? "Describe what to emphasize. Apple Intelligence reads your notes on this Mac."
                         : "Or select text in your notes and right-click. You can also write ==text== in your notes.",
                         size: 11.5, weight: .regular)
        hint.lineBreakMode = .byWordWrapping
        hint.preferredMaxLayoutWidth = 300
        hint.maximumNumberOfLines = 3

        let header = NSStackView(views: [rulesHeader, NSView(), clearButton])
        header.widthAnchor.constraint(equalToConstant: 300).isActive = true

        let stack = NSStackView(views: [title, hint, field, controls, statusRow, header, rulesStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(4, after: title)
        stack.setCustomSpacing(16, after: statusRow)
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        view = stack
        setStatus(Assistant.unavailableReason ?? "")
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(field)
    }

    func setStatus(_ text: String, busy: Bool = false) {
        status.stringValue = text
        status.isHidden = text.isEmpty
        busy ? spinner.startAnimation(nil) : spinner.stopAnimation(nil)
        isRunning = busy
        runButton.title = busy ? "Stop" : "Emphasize"
        field.isEnabled = !busy
    }

    /// Lists what's emphasized now, with how often each appears in the notes.
    func setRules(_ rules: [EmphasisRule], counts: [UUID: Int]) {
        rulesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        rulesHeader.isHidden = rules.isEmpty
        clearButton.isHidden = rules.isEmpty
        for rule in rules {
            let style = NSPopUpButton(frame: .zero, pullsDown: false)
            style.controlSize = .small
            style.isBordered = false
            for s in EmphasisStyle.allCases {
                style.addItem(withTitle: s.title)
                style.lastItem?.image = NSImage(systemSymbolName: s.symbol, accessibilityDescription: nil)
                style.lastItem?.representedObject = s.rawValue
            }
            style.selectItem(at: EmphasisStyle.allCases.firstIndex(of: rule.style) ?? 0)
            style.identifier = NSUserInterfaceItemIdentifier(rule.id.uuidString)
            style.target = self
            style.action = #selector(styleChanged(_:))

            let name = label(rule.label, size: 12, weight: .medium, color: Theme.text)
            name.lineBreakMode = .byTruncatingTail
            name.toolTip = rule.phrases.joined(separator: ", ")
            name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let count = label("\(counts[rule.id] ?? 0)×", size: 11, weight: .medium)
            let remove = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove")!,
                                  target: self, action: #selector(removeRule(_:)))
            remove.isBordered = false
            remove.contentTintColor = Theme.tertiary
            remove.identifier = NSUserInterfaceItemIdentifier(rule.id.uuidString)
            remove.toolTip = "Remove"

            let row = NSStackView(views: [style, name, count, remove])
            row.spacing = 6
            row.widthAnchor.constraint(equalToConstant: 300).isActive = true
            rulesStack.addArrangedSubview(row)
        }
    }

    @objc private func run() {
        if isRunning { onCancel?(); return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onRun?(text, scope.selectedSegment == 0)
    }

    func clearField() { field.stringValue = "" }

    @objc private func removeRule(_ sender: NSButton) {
        guard let id = sender.identifier.flatMap({ UUID(uuidString: $0.rawValue) }) else { return }
        onRemove?(id)
    }

    @objc private func styleChanged(_ sender: NSPopUpButton) {
        guard let id = sender.identifier.flatMap({ UUID(uuidString: $0.rawValue) }),
              let raw = sender.selectedItem?.representedObject as? String,
              let style = EmphasisStyle(rawValue: raw) else { return }
        onChangeStyle?(id, style)
    }

    @objc private func clearAll() { onClearAll?() }
}
