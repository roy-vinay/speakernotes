import AppKit

/// Preferences that survive relaunches. Each one can also be set for a single run with a launch argument,
/// for example `-filePath /path/notes.md -slideIndex 2` (the screenshot script uses this).
enum Settings {
    private static let defaults = UserDefaults.standard

    static var fontSize: CGFloat {
        get { CGFloat(double("fontSize", 22)) }
        set { defaults.set(Double(newValue), forKey: "fontSize") }
    }
    static var opacity: CGFloat {
        get { CGFloat(double("opacity", 0.96)) }
        set { defaults.set(Double(newValue), forKey: "opacity") }
    }
    static var typeface: Typeface {
        get { Typeface(rawValue: defaults.string(forKey: "typeface") ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: "typeface") }
    }
    /// Line spacing, 1.0 is normal.
    static var lineSpacing: CGFloat {
        get { CGFloat(double("lineSpacing", 1.25)) }
        set { defaults.set(Double(newValue), forKey: "lineSpacing") }
    }
    /// Auto-scroll speed in points per second. 30 is shown as 1.0×.
    static var scrollSpeed: Double {
        get { double("scrollSpeed", 30) }
        set { defaults.set(newValue, forKey: "scrollSpeed") }
    }
    static var hiddenFromShare: Bool {
        get { bool("hiddenFromShare", true) }
        set { defaults.set(newValue, forKey: "hiddenFromShare") }
    }
    static var followSlideKeys: Bool {
        get { bool("followSlideKeys", false) }
        set { defaults.set(newValue, forKey: "followSlideKeys") }
    }
    static var showMenuBarIcon: Bool {
        get { bool("showMenuBarIcon", true) }
        set { defaults.set(newValue, forKey: "showMenuBarIcon") }
    }
    static var slideIndex: Int {
        get { defaults.integer(forKey: "slideIndex") }
        set { defaults.set(newValue, forKey: "slideIndex") }
    }
    /// Notes typed into the app itself, used when no file is open.
    static var scratchNotes: String {
        get { defaults.string(forKey: "notes") ?? "" }
        set { defaults.set(newValue, forKey: "notes") }
    }
    /// The Markdown file that's open, so a relaunch comes back to it.
    static var filePath: String? {
        get { defaults.string(forKey: "filePath").flatMap { $0.isEmpty ? nil : $0 } }
        set { defaults.set(newValue ?? "", forKey: "filePath") }
    }
    /// Recently opened files, newest first, only those that still exist.
    static var recentFiles: [URL] {
        let paths = defaults.stringArray(forKey: "recentFiles") ?? []
        return paths.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    static func addRecent(_ url: URL) {
        var paths = defaults.stringArray(forKey: "recentFiles") ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        defaults.set(Array(paths.prefix(10)), forKey: "recentFiles")
    }

    static func clearRecents() { defaults.set([String](), forKey: "recentFiles") }

    private static func double(_ key: String, _ fallback: Double) -> Double {
        defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
    }
    private static func bool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }
}

let shortcutsHelp = """
While your slides are in front (any app):
⌃⌥→  ⌃⌥←    Next / previous slide
⌃⌥Space      Start or stop auto-scroll
⌃⌥↑  ⌃⌥↓    Scroll faster / slower
⌃⌥T          Click-through on or off
⌃⌥N          Show or hide the notes
⌃⌥E          Edit or present

After clicking in the notes:
→ ← Space    Next / previous slide
⌘O  ⌘S       Open a file / save
⌘E           Edit or present
⌘+  ⌘−       Text size
⌘]  ⌘[       Less / more see-through
"""
