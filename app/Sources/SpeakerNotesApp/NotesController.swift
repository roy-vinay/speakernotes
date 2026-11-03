import AppKit
import SpeakerNotesCore
import UniformTypeIdentifiers

/// Owns the notes window: the text, which slide is showing, editing, auto-scroll and the file.
final class NotesController: NSObject, NSTextViewDelegate {
    let panel: NotesPanel
    /// Called whenever something the menus show changes.
    var onStateChange: (() -> Void)?
    /// Builds the "More" menu shown from the header's ••• button.
    var moreMenu: (() -> NSMenu)?

    // Views
    private let root = DropView(frame: NSRect(x: 0, y: 0, width: 520, height: 360))
    private let background = NSVisualEffectView()
    private let header = NSView()
    private let footer = NSView()
    private let pill = SlidePill(frame: .zero)
    private let fileLabel = NSTextField(labelWithString: "")
    private let editHint = NSTextField(labelWithString: "Put a line of --- between slides  ·  ⌘S saves  ·  ⌘E presents")
    private let progress = SlideProgress(frame: .zero)
    private let speedLabel = NSTextField(labelWithString: "1.0×")
    private let toast = Toast(frame: .zero)
    private let emptyState = EmptyStateView(frame: .zero)
    private let showScroll = NSScrollView()
    private let showView = PresentTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
    private let editScroll = NSTextView.scrollableTextView()
    private var editView: NSTextView { editScroll.documentView as! NSTextView }
    private var textButton: IconButton!
    private var emphasisButton: IconButton!
    private var openButton: IconButton!
    private var editButton: IconButton!
    private var moreButton: IconButton!
    private var prevButton: IconButton!
    private var nextButton: IconButton!
    private var playButton: IconButton!
    private var slowerButton: IconButton!
    private var fasterButton: IconButton!
    private var navGroup: NSStackView!
    private var scrollGroup: NSStackView!

    // State
    private(set) var text = ""
    private(set) var slides: [Slide] = [Slide(startLine: 0, text: "")]
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
    private(set) var rules: [EmphasisRule] = []
    private var assistantTask: Task<Void, Never>?
    private let textSettings = TextSettingsViewController()
    private let emphasisPanel = EmphasisViewController()
    private lazy var textPopover = makePopover(textSettings)
    private lazy var emphasisPopover = makePopover(emphasisPanel)

    /// True when there are no notes to show, so the window offers to open or write some.
    var isEmpty: Bool { fileURL == nil && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    override init() {
        panel = NotesPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        super.init()
        setUpPanel()
        setUpBackground()
        setUpHeader()
        setUpFooter()
        setUpContent()
        setUpPopovers()
        loadInitialNotes()
    }

    // MARK: - Setup

    private func setUpPanel() {
        panel.title = "SpeakerNotes"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(kind)?.isHidden = true
        }
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.level = .statusBar                                   // above normal and floating windows
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false                            // stays up while you click your slides
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 340, height: 200)
        panel.alphaValue = Settings.opacity
        panel.sharingType = Settings.hiddenFromShare ? .none : .readOnly
        panel.contentView = root
        root.onDrop = { [weak self] url in self?.open(url) }
        if !panel.setFrameUsingName("SpeakerNotesWindow") {
            if let screen = NSScreen.main?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: screen.maxX - 560, y: screen.minY + 60))
            }
        }
        panel.setFrameAutosaveName("SpeakerNotesWindow")           // remembers size and position
        keepOnScreen()
    }

    private func setUpBackground() {
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        pin(background, to: root)
    }

    private func setUpHeader() {
        header.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(header)

        pill.onClick = { [weak self] view in self?.showSlideMenu(from: view) }
        fileLabel.font = .systemFont(ofSize: 12, weight: .medium)
        fileLabel.textColor = Theme.secondary
        fileLabel.lineBreakMode = .byTruncatingMiddle
        fileLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        textButton = IconButton("textformat.size", tip: "Text size and typeface", target: self, action: #selector(showTextSettings(_:)))
        emphasisButton = IconButton("highlighter", tip: "Emphasize words and phrases", target: self, action: #selector(showEmphasis(_:)))
        openButton = IconButton("folder", tip: "Open notes (⌘O)", target: self, action: #selector(openDocument))
        editButton = IconButton("square.and.pencil", tip: "Edit notes (⌘E)", target: self, action: #selector(toggleEditing))
        moreButton = IconButton("ellipsis", tip: "More", size: 14, target: self, action: #selector(showMoreMenu(_:)))

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let stack = NSStackView(views: [pill, fileLabel, spacer, textButton, emphasisButton, openButton, editButton, moreButton])
        stack.spacing = 8
        for b in [textButton!, emphasisButton!, openButton!, editButton!] { stack.setCustomSpacing(2, after: b) }
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(stack)

        let line = hairline()
        header.addSubview(line)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: background.topAnchor),
            header.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 44),
            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            line.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            line.bottomAnchor.constraint(equalTo: header.bottomAnchor),
        ])
    }

    private func setUpFooter() {
        footer.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(footer)

        prevButton = IconButton("chevron.left", tip: "Previous slide (⌃⌥←)", target: self, action: #selector(previousSlide))
        nextButton = IconButton("chevron.right", tip: "Next slide (⌃⌥→)", target: self, action: #selector(nextSlide))
        navGroup = NSStackView(views: [prevButton, nextButton])
        navGroup.spacing = 0

        progress.onSelect = { [weak self] i in self?.go(to: i) }
        progress.setContentHuggingPriority(.init(1), for: .horizontal)

        playButton = IconButton("play.fill", tip: "Start auto-scroll (⌃⌥Space)", target: self, action: #selector(toggleScrolling))
        slowerButton = IconButton("minus", tip: "Scroll slower (⌃⌥↓)", size: 11, target: self, action: #selector(slower))
        fasterButton = IconButton("plus", tip: "Scroll faster (⌃⌥↑)", size: 11, target: self, action: #selector(faster))
        speedLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        speedLabel.textColor = Theme.secondary
        speedLabel.alignment = .center
        speedLabel.widthAnchor.constraint(equalToConstant: 34).isActive = true
        let speedGroup = NSStackView(views: [slowerButton, speedLabel, fasterButton])
        speedGroup.spacing = 0
        speedGroup.wantsLayer = true
        speedGroup.layer?.cornerRadius = 8
        speedGroup.layer?.backgroundColor = Theme.fill.cgColor
        scrollGroup = NSStackView(views: [playButton, speedGroup])
        scrollGroup.spacing = 4

        editHint.font = .systemFont(ofSize: 11.5, weight: .medium)
        editHint.textColor = Theme.secondary
        editHint.lineBreakMode = .byTruncatingTail
        editHint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        editHint.isHidden = true

        let stack = NSStackView(views: [navGroup, progress, editHint, scrollGroup])
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(stack)

        let line = hairline()
        footer.addSubview(line)
        NSLayoutConstraint.activate([
            footer.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            footer.heightAnchor.constraint(equalToConstant: 44),
            stack.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            line.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            line.topAnchor.constraint(equalTo: footer.topAnchor),
        ])
    }

    private func setUpContent() {
        // Presenting: read-only rich text.
        showView.autoresizingMask = [.width]
        showView.isVerticallyResizable = true
        showView.isHorizontallyResizable = false
        showView.textContainer?.widthTracksTextView = true
        showView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        showView.isEditable = false
        showView.isSelectable = true
        showView.drawsBackground = false
        showView.textContainerInset = NSSize(width: 22, height: 18)
        showView.selectedTextAttributes = [.backgroundColor: NSColor(white: 1, alpha: 0.18)]
        showView.onKey = { [weak self] event in self?.presentKey(event) ?? false }
        showView.onEmphasize = { [weak self] phrase, style in self?.emphasize(phrase, style) }
        showView.onAskToEmphasize = { [weak self] in
            guard let self else { return }
            self.showEmphasis(self.emphasisButton)
        }
        showScroll.documentView = showView

        // Editing: plain text, no smart punctuation, so Markdown stays exactly as typed.
        let editor = editView
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: 18, height: 16)
        editor.insertionPointColor = Theme.accent
        editor.selectedTextAttributes = [.backgroundColor: NSColor(white: 1, alpha: 0.18)]
        editor.delegate = self

        for scroll in [showScroll, editScroll] {
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
            scroll.scrollerStyle = .overlay
            scroll.scrollerKnobStyle = .light
            scroll.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(scroll)
            NSLayoutConstraint.activate([
                scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
                scroll.bottomAnchor.constraint(equalTo: footer.topAnchor),
                scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            ])
        }
        editScroll.isHidden = true

        emptyState.onOpen = { [weak self] in self?.openDocument() }
        emptyState.onWrite = { [weak self] in self?.writeNotes() }
        emptyState.onOpenRecent = { [weak self] url in self?.open(url) }
        background.addSubview(emptyState)
        background.addSubview(toast)
        NSLayoutConstraint.activate([
            emptyState.topAnchor.constraint(equalTo: header.bottomAnchor),
            emptyState.bottomAnchor.constraint(equalTo: footer.topAnchor),
            emptyState.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            toast.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            toast.centerXAnchor.constraint(equalTo: background.centerXAnchor),
        ])
    }

    private func hairline() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = Theme.hairline.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }

    private func pin(_ view: NSView, to parent: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: parent.topAnchor),
            view.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
        ])
    }

    private func loadInitialNotes() {
        if let path = Settings.filePath, FileManager.default.fileExists(atPath: path) {
            open(URL(fileURLWithPath: path), restoreIndex: true, showWindow: false)
        } else {
            Settings.filePath = nil
            rules = EmphasisStore.rules(for: nil)
            setText(Settings.scratchNotes, keepIndex: Settings.slideIndex)
        }
        if UserDefaults.standard.bool(forKey: "startEditing") { toggleEditing() }
    }

    // MARK: - Showing slides

    private func setText(_ newText: String, keepIndex: Int) {
        text = newText
        slides = NotesParser.slides(in: text)
        index = min(max(keepIndex, 0), slides.count - 1)
        renderSlide()
    }

    private func renderSlide() {
        showView.textStorage?.setAttributedString(
            MarkdownRenderer.render(slides[index].text, style: .current, emphasis: rules))
        showView.scroll(.zero)
        Settings.slideIndex = index
        refresh()
    }

    /// Brings every control in line with the current state.
    private func refresh() {
        let empty = isEmpty && !editing
        emptyState.isHidden = !empty
        if empty { emptyState.setRecents(Settings.recentFiles) }
        showScroll.isHidden = editing || empty
        editScroll.isHidden = !editing

        pill.text = editing ? "Editing" : empty ? "No notes" : "\(index + 1) / \(slides.count)"
        pill.isClickable = !editing && !empty && slides.count > 1
        var name = fileURL?.deletingPathExtension().lastPathComponent ?? (empty ? "" : "My Notes")
        if dirty { name += " · Edited" }
        fileLabel.stringValue = name
        fileLabel.toolTip = fileURL?.path

        editButton.setSymbol(editing ? "checkmark" : "square.and.pencil",
                             tip: editing ? "Done editing (⌘E)" : "Edit notes (⌘E)")
        editButton.isOn = editing
        editButton.isEnabled = !clickThrough
        textButton.isEnabled = !clickThrough
        emphasisButton.isEnabled = !clickThrough && !editing && !empty
        emphasisButton.isOn = !rules.isEmpty

        let presenting = !editing && !empty
        navGroup.isHidden = !presenting
        progress.isHidden = !presenting
        scrollGroup.isHidden = !presenting
        editHint.isHidden = !editing
        prevButton.isEnabled = presenting && index > 0
        nextButton.isEnabled = presenting && index < slides.count - 1
        progress.count = slides.count
        progress.index = index
        progress.alphaValue = presenting ? 1 : 0.4
        playButton.isEnabled = presenting
        playButton.setSymbol(scrolling ? "pause.fill" : "play.fill",
                             tip: scrolling ? "Stop auto-scroll (⌃⌥Space)" : "Start auto-scroll (⌃⌥Space)")
        playButton.isOn = scrolling
        speedLabel.stringValue = String(format: "%.1f×", Settings.scrollSpeed / 30)

        background.layer?.borderWidth = clickThrough ? 2 : 0
        background.layer?.borderColor = Theme.clickThrough.cgColor
        onStateChange?()
    }

    @objc func nextSlide() { go(to: index + 1) }
    @objc func previousSlide() { go(to: index - 1) }
    @objc func firstSlide() { go(to: 0) }

    func go(to newIndex: Int) {
        guard !editing else { return }
        let target = min(max(newIndex, 0), slides.count - 1)
        guard target != index else { return }
        stopScrolling()
        index = target
        renderSlide()
    }

    private func showSlideMenu(from view: NSView) {
        let menu = NSMenu()
        for (i, slide) in slides.enumerated() {
            let title = slide.title.isEmpty ? "Slide \(i + 1)" : slide.title
            let item = NSMenuItem(title: "\(i + 1)   \(title)", action: #selector(jumpToSlide(_:)), keyEquivalent: "")
            item.tag = i
            item.target = self
            item.state = i == index ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: menu.item(at: index), at: NSPoint(x: 0, y: view.bounds.height), in: view)
    }

    @objc private func jumpToSlide(_ sender: NSMenuItem) { go(to: sender.tag) }

    @objc private func showMoreMenu(_ sender: NSButton) {
        guard let menu = moreMenu?() else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
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

    // MARK: - Editing

    @objc func toggleEditing() {
        stopScrolling()
        if editing { finishEditing() } else { startEditing() }
    }

    private func startEditing() {
        guard !clickThrough else { toast.show("Turn off click-through first (⌃⌥T)"); return }
        editing = true
        editView.string = text
        highlightEditor()
        editView.undoManager?.removeAllActions()
        // Put the cursor at the start of the slide that was showing.
        let offset = characterOffset(ofLine: slides[index].startLine, in: text)
        editView.setSelectedRange(NSRange(location: offset, length: 0))
        editView.scrollRangeToVisible(NSRange(location: offset, length: 0))
        show()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(editView)
        refresh()
    }

    private func finishEditing() {
        // Back to presenting: show the slide the cursor is in.
        let ns = editView.string as NSString
        let cursor = min(editView.selectedRange().location, ns.length)
        let line = ns.substring(to: cursor).reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
        editing = false
        let newSlides = NotesParser.slides(in: editView.string)
        setText(editView.string, keepIndex: NotesParser.slideIndex(forLine: line, in: newSlides))
        if dirty { save() }
        if fileURL == nil { Settings.scratchNotes = text }
        panel.makeFirstResponder(isEmpty ? nil : showView)
    }

    /// Starts notes typed into the app itself (kept between launches).
    @objc func writeNotes() {
        if fileURL != nil { closeFile() }
        if !editing { startEditing() }
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
        highlightEditor()
        if fileURL == nil {
            Settings.scratchNotes = editView.string
        } else if !dirty {
            dirty = true
            refresh()
        }
    }

    /// Light Markdown coloring while editing: headings stand out and slide breaks are clear.
    private func highlightEditor() {
        guard let storage = editView.textStorage else { return }
        let size = max(12, Settings.fontSize * 0.72)
        let base = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let bold = NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
        let ns = storage.string as NSString
        storage.beginEditing()
        storage.setAttributes([.font: base, .foregroundColor: Theme.text], range: NSRange(location: 0, length: ns.length))
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { line, range, _, _ in
            guard let line = line?.trimmingCharacters(in: .whitespaces) else { return }
            if line.count >= 3, let first = line.first, "-*_".contains(first),
               line.replacingOccurrences(of: " ", with: "").allSatisfy({ $0 == first }) {
                storage.addAttributes([.foregroundColor: Theme.accent, .font: bold], range: range)
            } else if line.hasPrefix("#") {
                storage.addAttributes([.foregroundColor: Theme.accent, .font: bold], range: range)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix(">") {
                storage.addAttribute(.foregroundColor, value: NSColor(white: 0.88, alpha: 1), range: range)
            }
        }
        storage.endEditing()
        editView.typingAttributes = [.font: base, .foregroundColor: Theme.text]
    }

    /// Saves to the open file, or keeps the notes in the app when no file is open.
    @objc func save() {
        let current = editing ? editView.string : text
        guard let url = fileURL else {
            Settings.scratchNotes = current
            toast.show("Saved")
            return
        }
        do {
            lastOwnWrite = Date()
            try current.write(to: url, atomically: true, encoding: .utf8)
            dirty = false
            watch(url) // an atomic save replaces the file, so watch the new one
            toast.show("Saved")
        } catch {
            alert("Couldn't save \(url.lastPathComponent)", error.localizedDescription)
        }
        refresh()
    }

    // MARK: - Files

    @objc func openDocument() {
        let dialog = NSOpenPanel()
        dialog.allowedContentTypes = ["md", "markdown", "mdown", "txt", "text"].compactMap { UTType(filenameExtension: $0) }
        dialog.allowsMultipleSelection = false
        dialog.message = "Choose your speaker notes"
        dialog.prompt = "Open Notes"
        NSApp.activate(ignoringOtherApps: true)
        if dialog.runModal() == .OK, let url = dialog.url { open(url) }
    }

    @objc func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        open(url)
    }

    func open(_ url: URL, restoreIndex: Bool = false, showWindow: Bool = true) {
        if editing { finishEditing() }
        if dirty { save() }
        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            fileURL = url
            dirty = false
            rules = EmphasisStore.rules(for: url)
            Settings.filePath = url.path
            Settings.addRecent(url)
            setText(contents, keepIndex: restoreIndex ? Settings.slideIndex : 0)
            watch(url)
            if showWindow {
                show()
                toast.show("\(slides.count) slide\(slides.count == 1 ? "" : "s")")
            }
        } catch {
            alert("Couldn't open \(url.lastPathComponent)", error.localizedDescription)
        }
    }

    @objc func closeFile() {
        if editing { finishEditing() }
        if dirty { save() }
        watcher?.cancel()
        watcher = nil
        fileURL = nil
        Settings.filePath = nil
        rules = EmphasisStore.rules(for: nil)
        setText(Settings.scratchNotes, keepIndex: 0)
    }

    /// Reloads the notes when the file changes on disk, for example when it's edited in another app.
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
        toast.show("Updated from \(url.lastPathComponent)")
    }

    // MARK: - Auto-scroll

    @objc func toggleScrolling() {
        scrolling ? stopScrolling() : startScrolling()
    }

    func startScrolling() {
        guard !editing, !isEmpty, !scrolling else { return }
        scrolling = true
        lastTick = Date()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        scrollTimer = timer
        refresh()
    }

    func stopScrolling() {
        guard scrolling else { return }
        scrolling = false
        scrollTimer?.invalidate()
        scrollTimer = nil
        refresh()
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
        Settings.scrollSpeed = min(max(value, 6), 300)
        refresh()
        toast.show(String(format: "Scroll speed %.1f×", Settings.scrollSpeed / 30))
    }

    // MARK: - Window

    @objc func show() {
        keepOnScreen()
        panel.orderFrontRegardless()
        onStateChange?()
    }

    @objc func toggleVisible() {
        if panel.isVisible { panel.orderOut(nil) } else { show() }
        onStateChange?()
    }

    /// If the window ended up off every screen (say a display was unplugged), bring it back.
    func keepOnScreen() {
        let frame = panel.frame
        let visible = NSScreen.screens.contains { $0.visibleFrame.intersection(frame).width >= 80 &&
                                                  $0.visibleFrame.intersection(frame).height >= 60 }
        if !visible { resetPosition() }
    }

    @objc func resetPosition() {
        guard let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return }
        let size = NSSize(width: min(max(panel.frame.width, 340), screen.width - 40),
                          height: min(max(panel.frame.height, 200), screen.height - 40))
        panel.setFrame(NSRect(x: screen.maxX - size.width - 24, y: screen.minY + 24,
                              width: size.width, height: size.height), display: true)
    }

    @objc func toggleClickThrough() {
        clickThrough.toggle()
        if clickThrough && editing { finishEditing() }
        panel.ignoresMouseEvents = clickThrough
        if clickThrough {
            toast.show("Click-through on  ·  ⌃⌥T to turn off", persistent: true)
        } else {
            toast.dismiss()
            toast.show("Click-through off")
        }
        show()
        refresh()
    }

    @objc func toggleShareHiding() {
        Settings.hiddenFromShare.toggle()
        panel.sharingType = Settings.hiddenFromShare ? .none : .readOnly
        toast.show(Settings.hiddenFromShare ? "Hidden from screen share" : "Visible in screen share")
        onStateChange?()
    }

    @objc func biggerText() { setFont(Settings.fontSize + 2) }
    @objc func smallerText() { setFont(Settings.fontSize - 2) }
    @objc func lessSeeThrough() { setOpacity(Settings.opacity + 0.1) }
    @objc func moreSeeThrough() { setOpacity(Settings.opacity - 0.1) }

    private func setFont(_ size: CGFloat) {
        Settings.fontSize = min(max(size, 12), 64)
        textChanged()
        if textPopover.isShown { textSettings.refresh() }
        toast.show("Text \(Int(Settings.fontSize)) pt")
    }

    private func textChanged() {
        if editing { highlightEditor() } else { renderSlide() }
    }

    // MARK: - Text settings and emphasis

    private func makePopover(_ controller: NSViewController) -> NSPopover {
        let p = NSPopover()
        p.contentViewController = controller
        p.behavior = .transient
        p.appearance = NSAppearance(named: .darkAqua)
        return p
    }

    private func setUpPopovers() {
        textSettings.onChange = { [weak self] in self?.textChanged() }
        emphasisPanel.onRun = { [weak self] instruction, all in self?.runInstruction(instruction, allSlides: all) }
        emphasisPanel.onCancel = { [weak self] in self?.assistantTask?.cancel() }
        emphasisPanel.onRemove = { [weak self] id in
            guard let self else { return }
            self.setRules(self.rules.filter { $0.id != id })
        }
        emphasisPanel.onChangeStyle = { [weak self] id, style in
            guard let self else { return }
            self.setRules(self.rules.map { var r = $0; if r.id == id { r.style = style }; return r })
        }
        emphasisPanel.onClearAll = { [weak self] in self?.setRules([]) }
    }

    @objc func showTextSettings(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        textSettings.refresh()
        textPopover.show(relativeTo: textButton.bounds, of: textButton, preferredEdge: .maxY)
    }

    @objc func showEmphasis(_ sender: Any?) {
        guard !isEmpty else { return }
        if editing { finishEditing() }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKey()
        _ = emphasisPanel.view
        refreshEmphasisList()
        emphasisPopover.show(relativeTo: emphasisButton.bounds, of: emphasisButton, preferredEdge: .maxY)
    }

    private func setRules(_ newRules: [EmphasisRule]) {
        rules = newRules
        EmphasisStore.save(rules, for: fileURL)
        renderSlide()
        refreshEmphasisList()
    }

    private func refreshEmphasisList() {
        guard emphasisPanel.isViewLoaded else { return }
        var counts: [UUID: Int] = [:]
        for rule in rules { counts[rule.id] = EmphasisPainter.count(rule, in: text) }
        emphasisPanel.setRules(rules, counts: counts)
    }

    /// Emphasizes a phrase chosen by hand, or removes its emphasis when style is nil.
    func emphasize(_ phrase: String, _ style: EmphasisStyle?) {
        let p = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return }
        if let style {
            setRules(rules + [EmphasisRule(label: p, phrases: [p], style: style)])
        } else {
            let kept = rules.compactMap { rule -> EmphasisRule? in
                var r = rule
                r.phrases.removeAll { $0.caseInsensitiveCompare(p) == .orderedSame }
                return r.phrases.isEmpty ? nil : r
            }
            setRules(kept)
        }
    }

    private func runInstruction(_ instruction: String, allSlides: Bool) {
        let style = EmphasisStyle.guess(from: instruction)
        guard Assistant.isAvailable else {
            // Without the on-device model, what you type is the phrase to emphasize.
            let n = EmphasisPainter.matches(of: instruction, in: text).count
            guard n > 0 else {
                emphasisPanel.setStatus("\u{201C}\(instruction)\u{201D} isn't in these notes.")
                return
            }
            setRules(rules + [EmphasisRule(label: instruction, phrases: [instruction], style: style)])
            emphasisPanel.clearField()
            emphasisPanel.setStatus("Emphasized \(n) place\(n == 1 ? "" : "s").")
            return
        }
        let passages = allSlides ? slides.map(\.text) : [slides[index].text]
        let total = passages.count
        emphasisPanel.setStatus("Reading your notes…", busy: true)
        assistantTask = Task { [weak self] in
            do {
                let phrases = try await Assistant.findPhrases(instruction, in: passages) { i in
                    DispatchQueue.main.async {
                        guard let self, self.emphasisPanel.isRunning else { return }
                        self.emphasisPanel.setStatus(total > 1 ? "Reading slide \(min(i + 1, total)) of \(total)…"
                                                               : "Reading this slide…", busy: true)
                    }
                }
                await MainActor.run { self?.finishInstruction(instruction, phrases, style) }
            } catch is CancellationError {
                await MainActor.run { self?.emphasisPanel.setStatus("Stopped.") }
            } catch {
                await MainActor.run { self?.emphasisPanel.setStatus("Couldn't finish: \(error.localizedDescription)") }
            }
        }
    }

    private func finishInstruction(_ instruction: String, _ phrases: [String], _ style: EmphasisStyle) {
        guard !phrases.isEmpty else {
            emphasisPanel.setStatus("Nothing matched. Try naming what to look for, like \u{201C}the engine names\u{201D}.")
            return
        }
        setRules(rules + [EmphasisRule(label: instruction, phrases: phrases, style: style)])
        emphasisPanel.clearField()
        let shown = phrases.prefix(6).joined(separator: ", ")
        emphasisPanel.setStatus("Found \(phrases.count): \(shown)\(phrases.count > 6 ? ", …" : "").")
    }

    private func setOpacity(_ value: CGFloat) {
        Settings.opacity = min(max(value, 0.35), 1.0)
        panel.alphaValue = Settings.opacity
        toast.show("Opacity \(Int((Settings.opacity * 100).rounded()))%")
    }

    @objc func hideWindow() {
        panel.orderOut(nil)
        onStateChange?()
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
