import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var notes: NotesController!
    private var statusItem: NSStatusItem?
    private let hotKeys = HotKeys()
    private var keyMonitor: Any?
    private var pendingURLs: [URL] = []

    static let releasesURL = URL(string: "https://github.com/roy-vinay/speakernotes/releases/latest")!
    static let homeURL = URL(string: "https://github.com/roy-vinay/speakernotes#readme")!

    func applicationDidFinishLaunching(_ notification: Notification) {
        notes = NotesController()
        notes.onStateChange = { [weak self] in self?.refreshStatusIcon() }
        notes.moreMenu = { [weak self] in self?.makeQuickMenu(includeQuit: false) ?? NSMenu() }
        NSApp.mainMenu = makeMainMenu()
        updateStatusItem()
        registerHotKeys()
        if Settings.followSlideKeys { startFollowingSlideKeys(prompt: false) }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.notes.keepOnScreen() // a display was unplugged or rearranged
        }
        if let url = pendingURLs.last { notes.open(url) }
        pendingURLs = []
        notes.show()
        // Used by the screenshot script: -openPopover text|emphasis
        if let which = UserDefaults.standard.string(forKey: "openPopover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                if which == "text" { self?.notes.showTextSettings(nil) } else { self?.notes.showEmphasis(nil) }
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // Opened from Finder ("Open With"), or a file dropped on the Dock icon.
        guard let url = urls.first else { return }
        if notes == nil { pendingURLs.append(url) } else { notes.open(url) }
    }

    /// Clicking the Dock icon always brings the notes back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        notes.show()
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        add(menu, "Show Notes", #selector(NotesController.show), target: notes)
        add(menu, "Open Notes…", #selector(NotesController.openDocument), target: notes)
        let recents = Settings.recentFiles.prefix(5)
        if !recents.isEmpty {
            menu.addItem(.separator())
            for url in recents {
                let item = add(menu, url.lastPathComponent, #selector(NotesController.openRecent(_:)), target: notes)
                item.representedObject = url
            }
        }
        return menu
    }

    func applicationWillTerminate(_ notification: Notification) {
        notes.prepareToQuit()
    }

    // MARK: - Global hotkeys (Control+Option)

    private func registerHotKeys() {
        hotKeys.register(kVK_RightArrow) { [weak self] in self?.notes.nextSlide() }
        hotKeys.register(kVK_LeftArrow) { [weak self] in self?.notes.previousSlide() }
        hotKeys.register(kVK_Space) { [weak self] in self?.notes.toggleScrolling() }
        hotKeys.register(kVK_UpArrow) { [weak self] in self?.notes.faster() }
        hotKeys.register(kVK_DownArrow) { [weak self] in self?.notes.slower() }
        hotKeys.register(kVK_ANSI_T) { [weak self] in self?.notes.toggleClickThrough() }
        hotKeys.register(kVK_ANSI_N) { [weak self] in self?.notes.toggleVisible() }
        hotKeys.register(kVK_ANSI_E) { [weak self] in self?.notes.toggleEditing() }
    }

    // MARK: - Following your slide keys

    /// When on, pressing → or ← in your slides app also moves the notes.
    /// Seeing keys sent to other apps needs Accessibility permission.
    @objc private func toggleFollowSlideKeys() {
        if Settings.followSlideKeys {
            Settings.followSlideKeys = false
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        } else {
            Settings.followSlideKeys = true
            startFollowingSlideKeys(prompt: true)
        }
    }

    private func startFollowingSlideKeys(prompt: Bool) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) && prompt {
            let alert = NSAlert()
            alert.messageText = "Let SpeakerNotes follow your slide keys"
            alert.informativeText = """
                In System Settings > Privacy & Security > Accessibility, turn on SpeakerNotes. \
                Then your notes move when you press → or ← in your slides.

                SpeakerNotes only reacts to the arrow keys, Page Up, Page Down and Space, and never records anything.
                """
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
            guard flags.isEmpty, !self.notes.editing else { return }
            switch Int(event.keyCode) {
            case kVK_RightArrow, kVK_DownArrow, kVK_PageDown, kVK_Space: self.notes.nextSlide()
            case kVK_LeftArrow, kVK_UpArrow, kVK_PageUp: self.notes.previousSlide()
            default: break
            }
        }
    }

    // MARK: - Open at login

    private var opensAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    @objc private func toggleOpenAtLogin() {
        do {
            if opensAtLogin { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Open at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nYou can add SpeakerNotes in System Settings > General > Login Items."
            alert.runModal()
        }
    }

    // MARK: - Menu bar icon

    @objc private func toggleMenuBarIcon() {
        Settings.showMenuBarIcon.toggle()
        updateStatusItem()
    }

    private func updateStatusItem() {
        if Settings.showMenuBarIcon, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.menu = makeQuickMenu(includeQuit: true)
            statusItem = item
            refreshStatusIcon()
        } else if !Settings.showMenuBarIcon, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func refreshStatusIcon() {
        let symbol = notes?.clickThrough == true ? "cursorarrow.motionlines" : "text.bubble"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "SpeakerNotes")
        image?.isTemplate = true
        statusItem?.button?.image = image
    }

    // MARK: - Menus

    /// The short menu shown from the ••• button and the menu bar icon.
    private func makeQuickMenu(includeQuit: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        menu.identifier = NSUserInterfaceItemIdentifier("quick")
        add(menu, "Open Notes…", #selector(NotesController.openDocument), key: "o", mods: [.command], target: notes)
        menu.addItem(recentMenuItem())
        add(menu, "Write Notes Here", #selector(NotesController.writeNotes), target: notes)
        add(menu, "Close File", #selector(NotesController.closeFile), target: notes).identifier = .init("closeFile")
        menu.addItem(.separator())
        add(menu, "Text Size and Typeface…", #selector(NotesController.showTextSettings(_:)), target: notes)
        add(menu, "Emphasize…", #selector(NotesController.showEmphasis(_:)), target: notes)
        menu.addItem(.separator())
        add(menu, "Move with My Slide Keys", #selector(toggleFollowSlideKeys), target: self).identifier = .init("follow")
        add(menu, "Click-Through", #selector(NotesController.toggleClickThrough), key: "t", target: notes)
            .identifier = .init("clickThrough")
        add(menu, "Hide from Screen Share", #selector(NotesController.toggleShareHiding), target: notes)
            .identifier = .init("share")
        add(menu, "Reset Window Position", #selector(NotesController.resetPosition), target: notes)
        menu.addItem(.separator())
        add(menu, "Keyboard Shortcuts", #selector(showShortcuts), target: self)
        if includeQuit {
            add(menu, "Show Notes", #selector(NotesController.show), key: "n", target: notes)
            menu.addItem(.separator())
            add(menu, "Quit SpeakerNotes", #selector(NSApplication.terminate(_:)), key: "q", mods: [.command], target: NSApp)
        }
        return menu
    }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

        let app = submenu(main, "SpeakerNotes")
        add(app, "About SpeakerNotes \(version)", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), target: NSApp)
        add(app, "Check for Updates…", #selector(checkForUpdates), target: self)
        app.addItem(.separator())
        add(app, "Open at Login", #selector(toggleOpenAtLogin), target: self).identifier = .init("login")
        add(app, "Show Menu Bar Icon", #selector(toggleMenuBarIcon), target: self).identifier = .init("menubar")
        app.addItem(.separator())
        add(app, "Hide SpeakerNotes", #selector(NSApplication.hide(_:)), key: "h", mods: [.command], target: NSApp)
        add(app, "Quit SpeakerNotes", #selector(NSApplication.terminate(_:)), key: "q", mods: [.command], target: NSApp)

        let file = submenu(main, "File")
        add(file, "Open Notes…", #selector(NotesController.openDocument), key: "o", mods: [.command], target: notes)
        file.addItem(recentMenuItem())
        add(file, "Write Notes Here", #selector(NotesController.writeNotes), key: "n", mods: [.command], target: notes)
        file.addItem(.separator())
        add(file, "Save", #selector(NotesController.save), key: "s", mods: [.command], target: notes)
        add(file, "Close File", #selector(NotesController.closeFile), target: notes).identifier = .init("closeFile")
        add(file, "Hide Notes Window", #selector(NotesController.hideWindow), key: "w", mods: [.command], target: notes)

        let edit = submenu(main, "Edit")
        add(edit, "Undo", Selector(("undo:")), key: "z", mods: [.command])
        add(edit, "Redo", Selector(("redo:")), key: "z", mods: [.command, .shift])
        edit.addItem(.separator())
        add(edit, "Cut", #selector(NSText.cut(_:)), key: "x", mods: [.command])
        add(edit, "Copy", #selector(NSText.copy(_:)), key: "c", mods: [.command])
        add(edit, "Paste", #selector(NSText.paste(_:)), key: "v", mods: [.command])
        add(edit, "Select All", #selector(NSText.selectAll(_:)), key: "a", mods: [.command])
        edit.addItem(.separator())
        add(edit, "Edit Notes", #selector(NotesController.toggleEditing), key: "e", mods: [.command], target: notes)
            .identifier = .init("edit")
        add(edit, "Emphasize…", #selector(NotesController.showEmphasis(_:)), target: notes)

        let view = submenu(main, "View")
        add(view, "Text Size and Typeface…", #selector(NotesController.showTextSettings(_:)), key: "t", mods: [.command], target: notes)
        add(view, "Bigger Text", #selector(NotesController.biggerText), key: "+", mods: [.command], target: notes)
        add(view, "Smaller Text", #selector(NotesController.smallerText), key: "-", mods: [.command], target: notes)
        view.addItem(.separator())
        add(view, "Less See-Through", #selector(NotesController.lessSeeThrough), key: "]", mods: [.command], target: notes)
        add(view, "More See-Through", #selector(NotesController.moreSeeThrough), key: "[", mods: [.command], target: notes)
        view.addItem(.separator())
        add(view, "Click-Through", #selector(NotesController.toggleClickThrough), key: "t", target: notes)
            .identifier = .init("clickThrough")
        add(view, "Hide from Screen Share", #selector(NotesController.toggleShareHiding), target: notes)
            .identifier = .init("share")
        add(view, "Reset Window Position", #selector(NotesController.resetPosition), target: notes)

        let slides = submenu(main, "Slides")
        add(slides, "Next Slide", #selector(NotesController.nextSlide), key: arrow(NSRightArrowFunctionKey), target: notes)
        add(slides, "Previous Slide", #selector(NotesController.previousSlide), key: arrow(NSLeftArrowFunctionKey), target: notes)
        add(slides, "First Slide", #selector(NotesController.firstSlide), target: notes)
        add(slides, "Move with My Slide Keys", #selector(toggleFollowSlideKeys), target: self).identifier = .init("follow")
        slides.addItem(.separator())
        add(slides, "Start Auto-Scroll", #selector(NotesController.toggleScrolling), key: " ", target: notes)
            .identifier = .init("scroll")
        add(slides, "Scroll Faster", #selector(NotesController.faster), key: arrow(NSUpArrowFunctionKey), target: notes)
        add(slides, "Scroll Slower", #selector(NotesController.slower), key: arrow(NSDownArrowFunctionKey), target: notes)

        let window = submenu(main, "Window")
        add(window, "Show Notes", #selector(NotesController.show), key: "n", target: notes)
        NSApp.windowsMenu = window

        let help = submenu(main, "Help")
        add(help, "Keyboard Shortcuts", #selector(showShortcuts), target: self)
        add(help, "SpeakerNotes on GitHub", #selector(openHome), target: self)
        NSApp.helpMenu = help

        for item in main.items { item.submenu?.delegate = self }
        return main
    }

    private func recentMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let sub = NSMenu(title: "Open Recent")
        sub.identifier = NSUserInterfaceItemIdentifier("recent")
        sub.delegate = self
        item.submenu = sub
        return item
    }

    /// Menus show the current state each time they open.
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu.identifier?.rawValue == "recent" {
            menu.removeAllItems()
            let recents = Settings.recentFiles
            for url in recents {
                let item = add(menu, url.lastPathComponent, #selector(NotesController.openRecent(_:)), target: notes)
                item.representedObject = url
                item.toolTip = url.path
            }
            if recents.isEmpty {
                let none = NSMenuItem(title: "No Recent Notes", action: nil, keyEquivalent: "")
                none.isEnabled = false
                menu.addItem(none)
            } else {
                menu.addItem(.separator())
                add(menu, "Clear Menu", #selector(clearRecents), target: self)
            }
            return
        }
        for item in menu.items {
            switch item.identifier?.rawValue {
            case "closeFile":
                item.isEnabled = notes.fileURL != nil
                item.title = notes.fileURL.map { "Close \($0.lastPathComponent)" } ?? "Close File"
            case "follow": item.state = Settings.followSlideKeys ? .on : .off
            case "clickThrough": item.state = notes.clickThrough ? .on : .off
            case "share": item.state = Settings.hiddenFromShare ? .on : .off
            case "login": item.state = opensAtLogin ? .on : .off
            case "menubar": item.state = Settings.showMenuBarIcon ? .on : .off
            case "edit": item.title = notes.editing ? "Present Notes" : "Edit Notes"
            case "scroll": item.title = notes.scrolling ? "Stop Auto-Scroll" : "Start Auto-Scroll"
            default: break
            }
        }
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector?, key: String = "",
                     mods: NSEvent.ModifierFlags = [.control, .option], target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : mods
        item.target = target
        menu.addItem(item)
        return item
    }

    private func submenu(_ main: NSMenu, _ title: String) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        item.submenu = menu
        main.addItem(item)
        return menu
    }

    private func arrow(_ code: Int) -> String { String(Character(UnicodeScalar(code)!)) }

    @objc private func clearRecents() { Settings.clearRecents() }
    @objc private func checkForUpdates() { NSWorkspace.shared.open(Self.releasesURL) }
    @objc private func openHome() { NSWorkspace.shared.open(Self.homeURL) }

    @objc private func showShortcuts() {
        let alert = NSAlert()
        alert.messageText = "Keyboard Shortcuts"
        alert.informativeText = shortcutsHelp
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
