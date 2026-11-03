import AppKit
import SpeakerNotesCore
import UniformTypeIdentifiers

/// Owns the notes window: the text, which slide is showing, editing, auto-scroll and the file.
final class NotesController: NSObject, NSTextViewDelegate {
    let panel: NotesPanel
    var onStateChange: (() -> Void)?

    private let editScroll: NSScrollView
    private let editView: NSTextView
    private let showScroll: NSScrollView
    private let showView: PresentTextView
    private let bar = NSView()
    private let counter = NSTextField(labelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private var prevButton: NSButton!
    private var nextButton: NSButton!
    private var playButton: NSButton!
    private var modeButton: NSButton!

    private(set) var text = ""
    private(set) var slides: [Slide] = []
    private(set) var index = 0
    private(set) var editing = false
    private(set) var scrolling = false
    private(set) var clickThrough = false
    private(set) var fileURL: URL?
    private var dirty = false
    private var scrollTimer: Timer?
    private var lastTick = Date()
    private var watcher: DispatchSourceFileSystemObject?
    private var lastOwnWrite = Date.distantPast

    private static let barHeight: CGFloat = 30
    private static let background = NSColor(white: 0.08, alpha: 1)

    override init() {
        panel = NotesPanel(
            contentRect: NSRect(x: 160, y: 160, width: 460, height: 320),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered, defer: false)
        editScroll = NSTextView.scrollableTextView()
        editView = editScroll.documentView as! NSTextView
        showScroll = NSScrollView(frame: .zero)
        let present = PresentTextView(frame: .zero)
        showView = present
        super.init()
        setUpPanel()
        setUpTextViews()
        setUpBar()
        loadInitialNotes()
    }

    // MARK: Setup

    private func setUpPanel() {
        panel.title = "SpeakerNotes"
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.backgroundColor = Self.background
        panel.level = .statusBar                                   // above normal and floating windows
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false                            // stays up while you click your slides
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 240, height: 140)
        panel.alphaValue = Settings.opacity
        panel.sharingType = Settings.hiddenFromShare ? .none : .readOnly
        panel.setFrameAutosaveName("SpeakerNotesWindow")           // remembers size and position
        panel.onCommandKey = { [weak self] key, shift in self?.commandKey(key, shift) ?? false }

        let root = DropView(frame: panel.contentRect(forFrameRect: panel.frame))
        root.onDrop = { [weak self] url in self?.open(url) }
        panel.contentView = root
    }

    private func setUpTextViews() {
        guard let root = panel.contentView else { return }
        let area = NSRect(x: 0, y: Self.barHeight, width: root.bounds.width,
                          height: root.bounds.height - Self.barHeight)

        // Presenting: a read-only text view inside its own scroll view.
        showScroll.frame = area
        showView.frame = NSRect(origin: .zero, size: showScroll.contentSize)
        showView.autoresizingMask = [.width]
        showView.isVerticallyResizable = true
        showView.isHorizontallyResizable = false
        showView.textContainer?.widthTracksTextView = true
        showView.textContainer?.containerSize = NSSize(width: showScroll.contentSize.width,
                                                        height: .greatestFiniteMagnitude)
        showView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        showView.isEditable = false
        showView.isSelectable = true
        showView.drawsBackground = true
        showView.backgroundColor = Self.background
        showView.textContainerInset = NSSize(width: 16, height: 14)
        showView.onKey = { [weak self] event in self?.presentKey(event) ?? false }
        showScroll.documentView = showView

        for (scroll, view) in [(showScroll, showView as NSTextView), (editScroll, editView)] {
            scroll.frame = area
            scroll.autoresizingMask = [.width, .height]
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
            scroll.drawsBackground = true
            scroll.backgroundColor = Self.background
            view.backgroundColor = Self.background
            root.addSubview(scroll)
        }

        // Editing: plain text, no smart punctuation, so Markdown stays as typed.
        editView.isRichText = false
        editView.allowsUndo = true
        editView.isAutomaticQuoteSubstitutionEnabled = false
        editView.isAutomaticDashSubstitutionEnabled = false
        editView.isAutomaticTextReplacementEnabled = false
        editView.isAutomaticSpellingCorrectionEnabled = false
        editView.textContainerInset = NSSize(width: 12, height: 12)
        editView.textColor = MarkdownRenderer.textColor
        editView.insertionPointColor = .white
        editView.delegate = self
        editScroll.isHidden = true
        applyFont()
    }

    private func setUpBar() {
        guard let root = panel.contentView else { return }
        bar.frame = NSRect(x: 0, y: 0, width: root.bounds.width, height: Self.barHeight)
        bar.autoresizingMask = [.width]
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(white: 0.13, alpha: 1).cgColor
        root.addSubview(bar)

        func button(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage()
            let b = NSButton(image: image, target: self, action: action)
            b.isBordered = false
            b.contentTintColor = NSColor(white: 0.85, alpha: 1)
            b.toolTip = tip
            b.setContentHuggingPriority(.required, for: .horizontal)
            return b
        }
        prevButton = button("chevron.left", "Previous slide (⌃⌥←)", #selector(previousSlide))
        nextButton = button("chevron.right", "Next slide (⌃⌥→)", #selector(nextSlide))
        playButton = button("play.fill", "Start or stop auto-scroll (⌃⌥Space)", #selector(toggleScrolling))
        modeButton = button("pencil", "Edit notes (⌘E)", #selector(toggleEditing))
        let slower = button("tortoise", "Slower (⌃⌥↓)", #selector(slower))
        let faster = button("hare", "Faster (⌃⌥↑)", #selector(faster))

        for label in [counter, status] {
            label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            label.textColor = NSColor(white: 0.75, alpha: 1)
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        status.textColor = MarkdownRenderer.accentColor

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [prevButton, counter, nextButton, status, spacer, slower, playButton, faster, modeButton])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        stack.frame = bar.bounds
        stack.autoresizingMask = [.width, .height]
        bar.addSubview(stack)
    }

    private func loadInitialNotes() {
        if let path = Settings.filePath, FileManager.default.fileExists(atPath: path) {
            open(URL(fileURLWithPath: path), restoreIndex: true)
        } else {
            setText(Settings.scratchNotes ?? welcomeNotes, keepIndex: Settings.slideIndex)
        }
    }

    // MARK: Showing slides

    private func setText(_ newText: String, keepIndex: Int) {
        text = newText
        slides = NotesParser.slides(in: text)
        index = min(max(keepIndex, 0), slides.count - 1)
        renderSlide()
    }

    private func renderSlide() {
        showView.textStorage?.setAttributedString(
            MarkdownRenderer.render(slides[index].text, fontSize: Settings.fontSize))
        showView.scroll(.zero)
        Settings.slideIndex = index
        refreshBar()
    }

    private func refreshBar() {
        counter.stringValue = editing ? "Editing" : "\(index + 1) / \(slides.count)"
        prevButton.isEnabled = !editing && index > 0
        nextButton.isEnabled = !editing && index < slides.count - 1
        playButton.image = NSImage(systemSymbolName: scrolling ? "pause.fill" : "play.fill",
                                   accessibilityDescription: "Auto-scroll")
        playButton.isEnabled = !editing
        modeButton.image = NSImage(systemSymbolName: editing ? "play.rectangle" : "pencil",
                                   accessibilityDescription: editing ? "Present" : "Edit")
        modeButton.toolTip = editing ? "Present (⌘E)" : "Edit notes (⌘E)"
        var notes: [String] = []
        if clickThrough { notes.append("Click-through on, ⌃⌥T to turn off") }
        if scrolling { notes.append("\(Int(Settings.scrollSpeed)) pt/s") }
        if dirty { notes.append("Edited") }
        status.stringValue = notes.joined(separator: " · ")
        var title = fileURL?.lastPathComponent ?? "SpeakerNotes"
        if !editing, !slides[index].title.isEmpty { title += "  ·  " + slides[index].title }
        panel.title = title
        onStateChange?()
    }

    @objc func nextSlide() { go(to: index + 1) }
    @objc func previousSlide() { go(to: index - 1) }

    func go(to newIndex: Int) {
        guard !editing else { return }
        let target = min(max(newIndex, 0), slides.count - 1)
        guard target != index else { return }
        index = target
        renderSlide()
    }

    private func presentKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option])
        guard flags.isEmpty else { return false }
        switch Int(event.keyCode) {
        case 124, 125, 121, 49: nextSlide()       // →, ↓, Page Down, Space
        case 123, 126, 116: previousSlide()       // ←, ↑, Page Up
        default: return false
        }
        return true
    }

    // MARK: Editing

    @objc func toggleEditing() {
        stopScrolling()
        if editing {
            // Back to presenting: show the slide the cursor is in.
            let cursor = editView.selectedRange().location
            let prefix = (editView.string as NSString).substring(to: min(cursor, (editView.string as NSString).length))
            let line = prefix.reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
            editing = false
            editScroll.isHidden = true
            showScroll.isHidden = false
            let newSlides = NotesParser.slides(in: editView.string)
            setText(editView.string, keepIndex: NotesParser.slideIndex(forLine: line, in: newSlides))
            if dirty { save() }
            panel.makeFirstResponder(showView)
        } else {
            editing = true
            editView.string = text
            editView.textColor = MarkdownRenderer.textColor
            editView.undoManager?.removeAllActions()
            showScroll.isHidden = true
            editScroll.isHidden = false
            // Put the cursor at the start of the current slide.
            let offset = characterOffset(ofLine: slides[index].startLine, in: text)
            editView.setSelectedRange(NSRange(location: offset, length: 0))
            editView.scrollRangeToVisible(NSRange(location: offset, length: 0))
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(editView)
            refreshBar()
        }
    }

    private func characterOffset(ofLine line: Int, in s: String) -> Int {
        var count = 0
        var offset = 0
        for unit in s.utf16 {
            if count == line { return offset }
            offset += 1
            if unit == 10 { count += 1 }
        }
        return count == line ? offset : (s as NSString).length
    }

    func textDidChange(_ notification: Notification) {
        if fileURL == nil {
            Settings.scratchNotes = editView.string
        } else if !dirty {
            dirty = true
            refreshBar()
        }
    }

    /// Saves to the open Markdown file, or to the app's own notes when no file is open.
    func save() {
        let current = editing ? editView.string : text
        guard let url = fileURL else {
            Settings.scratchNotes = current
            return
        }
        do {
            lastOwnWrite = Date()
            try current.write(to: url, atomically: true, encoding: .utf8)
            dirty = false
            watch(url) // an atomic save replaces the file, so watch the new one
        } catch {
            alert("Couldn't save \(url.lastPathComponent)", error.localizedDescription)
        }
        refreshBar()
    }

    // MARK: Files

    @objc func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["md", "markdown", "mdown", "txt"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.message = "Choose your speaker notes (Markdown or plain text)"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL, restoreIndex: Bool = false) {
        if editing { toggleEditing() }
        if dirty { save() }
        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            fileURL = url
            dirty = false
            Settings.filePath = url.path
            setText(contents, keepIndex: restoreIndex ? Settings.slideIndex : 0)
            watch(url)
            show()
        } catch {
            alert("Couldn't open \(url.lastPathComponent)", error.localizedDescription)
        }
    }

    @objc func closeFile() {
        if dirty { save() }
        watcher?.cancel()
        watcher = nil
        fileURL = nil
        Settings.filePath = nil
        if editing { toggleEditing() }
        setText(Settings.scratchNotes ?? welcomeNotes, keepIndex: 0)
    }

    /// Reloads the notes when the file changes on disk, for example when you edit it in another app.
    private func watch(_ url: URL) {
        watcher?.cancel()
        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            let replaced = !source.data.intersection([.delete, .rename]).isEmpty
            // Editors often save by replacing the file; give them a moment, then follow the new file.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.reloadFromDisk(rewatch: replaced) }
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        watcher = source
    }

    private func reloadFromDisk(rewatch: Bool) {
        guard let url = fileURL else { return }
        if rewatch { watch(url) }
        guard Date().timeIntervalSince(lastOwnWrite) > 1, !dirty, !editing,
              let contents = try? String(contentsOf: url, encoding: .utf8), contents != text else { return }
        setText(contents, keepIndex: index)
    }

    // MARK: Auto-scroll

    @objc func toggleScrolling() {
        scrolling ? stopScrolling() : startScrolling()
    }

    func startScrolling() {
        guard !editing, !scrolling else { return }
        scrolling = true
        lastTick = Date()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        scrollTimer = timer
        refreshBar()
    }

    func stopScrolling() {
        guard scrolling else { return }
        scrolling = false
        scrollTimer?.invalidate()
        scrollTimer = nil
        refreshBar()
    }

    private func tick() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        let clip = showScroll.contentView
        let maxY = max(0, showView.frame.height - clip.bounds.height)
        let y = min(clip.bounds.origin.y + CGFloat(Settings.scrollSpeed * dt), maxY)
        clip.scroll(to: NSPoint(x: 0, y: y))
        showScroll.reflectScrolledClipView(clip)
        if y >= maxY { stopScrolling() }
    }

    @objc func faster() { setSpeed(Settings.scrollSpeed * 1.25) }
    @objc func slower() { setSpeed(Settings.scrollSpeed / 1.25) }

    private func setSpeed(_ value: Double) {
        Settings.scrollSpeed = min(max(value, 5), 300)
        refreshBar()
    }

    // MARK: Window options

    func show() { panel.orderFrontRegardless() }

    @objc func toggleVisible() {
        if panel.isVisible { panel.orderOut(nil) } else { show() }
        onStateChange?()
    }

    @objc func toggleClickThrough() {
        clickThrough.toggle()
        if clickThrough && editing { toggleEditing() }
        panel.ignoresMouseEvents = clickThrough
        bar.layer?.backgroundColor = (clickThrough ? NSColor(calibratedRed: 0.32, green: 0.24, blue: 0.05, alpha: 1)
                                                   : NSColor(white: 0.13, alpha: 1)).cgColor
        show()
        refreshBar()
    }

    @objc func toggleShareHiding() {
        Settings.hiddenFromShare.toggle()
        panel.sharingType = Settings.hiddenFromShare ? .none : .readOnly
        onStateChange?()
    }

    @objc func biggerText() { setFont(Settings.fontSize + 2) }
    @objc func smallerText() { setFont(Settings.fontSize - 2) }
    @objc func lessSeeThrough() { setOpacity(Settings.opacity + 0.1) }
    @objc func moreSeeThrough() { setOpacity(Settings.opacity - 0.1) }

    private func setFont(_ size: CGFloat) {
        Settings.fontSize = min(max(size, 11), 80)
        applyFont()
        renderSlide()
    }

    private func applyFont() {
        editView.font = .monospacedSystemFont(ofSize: max(12, Settings.fontSize * 0.8), weight: .regular)
    }

    private func setOpacity(_ value: CGFloat) {
        Settings.opacity = min(max(value, 0.3), 1.0)
        panel.alphaValue = Settings.opacity
    }

    // MARK: Keys

    private func commandKey(_ key: String, _ shift: Bool) -> Bool {
        switch key {
        case "=", "+": biggerText()
        case "-": smallerText()
        case "]": lessSeeThrough()
        case "[": moreSeeThrough()
        case "e": toggleEditing()
        case "o": openDocument()
        case "s": save()
        case "w": panel.orderOut(nil); onStateChange?()
        case "q": NSApp.terminate(nil)
        default: return false
        }
        return true
    }

    func prepareToQuit() {
        if editing && fileURL == nil { Settings.scratchNotes = editView.string }
        if dirty { save() }
    }

    private func alert(_ title: String, _ message: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
