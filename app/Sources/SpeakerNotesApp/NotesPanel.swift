import AppKit

/// A floating panel that can take typing without pulling focus away from your slides app,
/// and that stays visible when another app is in front.
final class NotesPanel: NSPanel {
    /// Handles ⌘ shortcuts that aren't text editing. Returns true when it handled the key.
    var onCommandKey: ((String, Bool) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // The app has no visible menu bar, so standard editing shortcuts are wired up here.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.type == .keyDown, flags.contains(.command), !flags.contains(.control),
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        let shift = flags.contains(.shift)
        let editing: [String: String] = ["x": "cut:", "c": "copy:", "v": "paste:", "a": "selectAll:"]
        if let selector = editing[key] {
            return NSApp.sendAction(Selector(selector), to: nil, from: self)
        }
        if key == "z" {
            return NSApp.sendAction(Selector(shift ? "redo:" : "undo:"), to: nil, from: self)
        }
        if let handler = onCommandKey, handler(key, shift) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// The presenting view: read-only, and arrow keys or space move between slides.
final class PresentTextView: NSTextView {
    var onKey: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if let onKey, onKey(event) { return }
        super.keyDown(with: event)
    }
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
