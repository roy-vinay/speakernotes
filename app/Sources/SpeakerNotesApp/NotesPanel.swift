import AppKit

/// A floating panel that can take typing without pulling focus away from your slides app,
/// and that stays visible when another app is in front.
final class NotesPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // When the slides app is in front, our menu bar isn't, so send ⌘ shortcuts to our menus directly.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        if !NSApp.isActive, let menu = NSApp.mainMenu, menu.performKeyEquivalent(with: event) { return true }
        return false
    }
}

/// The presenting view: read-only; arrow keys or space move between slides, and right-click emphasizes.
final class PresentTextView: NSTextView {
    var onKey: ((NSEvent) -> Bool)?
    /// A phrase to emphasize with a style, or to un-emphasize when the style is nil.
    var onEmphasize: ((String, EmphasisStyle?) -> Void)?
    var onAskToEmphasize: (() -> Void)?
    private var menuSelection = ""

    override func keyDown(with event: NSEvent) {
        if let onKey, onKey(event) { return }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let range = selectedRange()
        menuSelection = range.length > 0
            ? (string as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        if !menuSelection.isEmpty {
            let short = menuSelection.count > 28 ? String(menuSelection.prefix(28)) + "…" : menuSelection
            let header = NSMenuItem(title: "\u{201C}\(short)\u{201D}", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for style in EmphasisStyle.allCases {
                let item = NSMenuItem(title: style.title, action: #selector(emphasizeSelection(_:)), keyEquivalent: "")
                item.image = NSImage(systemSymbolName: style.symbol, accessibilityDescription: nil)
                item.representedObject = style.rawValue
                item.target = self
                menu.addItem(item)
            }
            let remove = NSMenuItem(title: "Remove Emphasis", action: #selector(emphasizeSelection(_:)), keyEquivalent: "")
            remove.representedObject = ""
            remove.target = self
            menu.addItem(remove)
            menu.addItem(.separator())
            menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
            menu.addItem(.separator())
        }
        let ask = NSMenuItem(title: "Emphasize…", action: #selector(askToEmphasize), keyEquivalent: "")
        ask.image = NSImage(systemSymbolName: "highlighter", accessibilityDescription: nil)
        ask.target = self
        menu.addItem(ask)
        return menu
    }

    @objc private func emphasizeSelection(_ sender: NSMenuItem) {
        let raw = sender.representedObject as? String ?? ""
        onEmphasize?(menuSelection, EmphasisStyle(rawValue: raw))
    }

    @objc private func askToEmphasize() { onAskToEmphasize?() }
}

/// The window's content: accepts a Markdown file dropped onto it.
final class DropView: NSView {
    var onDrop: ((URL) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func fileURL(_ sender: NSDraggingInfo) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?.first
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURL(sender) == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = fileURL(sender) else { return false }
        onDrop?(url)
        return true
    }
}
