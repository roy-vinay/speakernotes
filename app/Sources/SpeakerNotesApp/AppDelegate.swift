import AppKit
import ApplicationServices
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var notes: NotesController!
    private var statusItem: NSStatusItem!
    private let hotKeys = HotKeys()
    private var keyMonitor: Any?

    private var showItem: NSMenuItem!
    private var editItem: NSMenuItem!
    private var scrollItem: NSMenuItem!
    private var clickThroughItem: NSMenuItem!
    private var shareItem: NSMenuItem!
    private var followItem: NSMenuItem!
    private var closeFileItem: NSMenuItem!

    static let releasesURL = URL(string: "https://github.com/roy-vinay/speakernotes/releases/latest")!

    func applicationDidFinishLaunching(_ notification: Notification) {
        notes = NotesController()
        notes.onStateChange = { [weak self] in self?.refreshMenu() }
        buildStatusMenu()
        registerHotKeys()
        if Settings.followSlideKeys { startFollowingSlideKeys(prompt: false) }
        notes.show()
        refreshMenu()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // Opened from Finder ("Open With") or by dropping a file on the app icon.
        if let url = urls.first { notes.open(url) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        notes.prepareToQuit()
    }

    // MARK: Global hotkeys (Control+Option)

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

    // MARK: Following your slide keys

    /// When on, pressing → or ← (and similar) in your slides app also moves the notes.
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
        refreshMenu()
    }

    private func startFollowingSlideKeys(prompt: Bool) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) && prompt {
            let alert = NSAlert()
            alert.messageText = "Allow SpeakerNotes to see your slide keys"
            alert.informativeText = """
                In System Settings > Privacy & Security > Accessibility, turn on SpeakerNotes. \
                Then your notes move when you press → or ← in your slides.

                SpeakerNotes only reacts to arrow keys, Page Up, Page Down and Space, and never records anything.
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

    // MARK: Menu bar

    private func buildStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "SpeakerNotes") {
            image.isTemplate = true
            statusItem.button?.image = image
        } else {
            statusItem.button?.title = "Notes"
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        func add(_ title: String, _ action: Selector, key: String = "", mods: NSEvent.ModifierFlags = [.control, .option],
                 target: AnyObject? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = key.isEmpty ? [] : mods
            item.target = target ?? (notes as AnyObject)
            menu.addItem(item)
            return item
        }
        func arrow(_ code: Int) -> String { String(Character(UnicodeScalar(code)!)) }

        showItem = add("Hide Notes", #selector(NotesController.toggleVisible), key: "n")
        editItem = add("Edit Notes", #selector(NotesController.toggleEditing), key: "e")
        _ = add("Open Notes File…", #selector(NotesController.openDocument), key: "o", mods: [.command])
        closeFileItem = add("Close File", #selector(NotesController.closeFile))
        menu.addItem(.separator())
        _ = add("Next Slide", #selector(NotesController.nextSlide), key: arrow(NSRightArrowFunctionKey))
        _ = add("Previous Slide", #selector(NotesController.previousSlide), key: arrow(NSLeftArrowFunctionKey))
        followItem = add("Move with My Slide Keys", #selector(toggleFollowSlideKeys), target: self)
        menu.addItem(.separator())
        scrollItem = add("Start Auto-Scroll", #selector(NotesController.toggleScrolling), key: " ")
        _ = add("Scroll Faster", #selector(NotesController.faster), key: arrow(NSUpArrowFunctionKey))
        _ = add("Scroll Slower", #selector(NotesController.slower), key: arrow(NSDownArrowFunctionKey))
        menu.addItem(.separator())
        clickThroughItem = add("Click-Through", #selector(NotesController.toggleClickThrough), key: "t")
        shareItem = add("Hide from Screen Share", #selector(NotesController.toggleShareHiding))
        _ = add("Bigger Text", #selector(NotesController.biggerText), key: "+", mods: [.command])
        _ = add("Smaller Text", #selector(NotesController.smallerText), key: "-", mods: [.command])
        _ = add("Less See-Through", #selector(NotesController.lessSeeThrough), key: "]", mods: [.command])
        _ = add("More See-Through", #selector(NotesController.moreSeeThrough), key: "[", mods: [.command])
        menu.addItem(.separator())
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let about = NSMenuItem(title: "SpeakerNotes \(version)", action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)
        _ = add("Check for Updates…", #selector(checkForUpdates), target: self)
        _ = add("Quit SpeakerNotes", #selector(NSApplication.terminate(_:)), key: "q", mods: [.command], target: NSApp)
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) { refreshMenu() }

    private func refreshMenu() {
        guard showItem != nil else { return }
        showItem.title = notes.panel.isVisible ? "Hide Notes" : "Show Notes"
        editItem.title = notes.editing ? "Present Notes" : "Edit Notes"
        scrollItem.title = notes.scrolling ? "Stop Auto-Scroll" : "Start Auto-Scroll"
        clickThroughItem.state = notes.clickThrough ? .on : .off
        shareItem.state = Settings.hiddenFromShare ? .on : .off
        followItem.state = Settings.followSlideKeys ? .on : .off
        closeFileItem.isEnabled = notes.fileURL != nil
        closeFileItem.title = notes.fileURL.map { "Close \($0.lastPathComponent)" } ?? "Close File"
    }

    @objc private func checkForUpdates() {
        NSWorkspace.shared.open(Self.releasesURL)
    }
}
