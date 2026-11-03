import AppKit

/// Preferences that survive relaunches.
struct Settings {
    private static let defaults = UserDefaults.standard

    static var fontSize: CGFloat {
        get { CGFloat(double("fontSize", 22)) }
        set { defaults.set(Double(newValue), forKey: "fontSize") }
    }
    static var opacity: CGFloat {
        get { CGFloat(double("opacity", 0.92)) }
        set { defaults.set(Double(newValue), forKey: "opacity") }
    }
    /// Auto-scroll speed in points per second.
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
    static var slideIndex: Int {
        get { defaults.integer(forKey: "slideIndex") }
        set { defaults.set(newValue, forKey: "slideIndex") }
    }
    /// Notes typed into the app when no file is open.
    static var scratchNotes: String? {
        get { defaults.string(forKey: "notes") }
        set { defaults.set(newValue, forKey: "notes") }
    }
    /// The Markdown file last opened, if any.
    static var filePath: String? {
        get { defaults.string(forKey: "filePath") }
        set { defaults.set(newValue, forKey: "filePath") }
    }

    private static func double(_ key: String, _ fallback: Double) -> Double {
        defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
    }
    private static func bool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }
}

let welcomeNotes = """
# Welcome to SpeakerNotes

This window floats over your slides and stays out of your screen share.
Click your slides to change them. These notes stay put.

---

## Slides

- Separate slides with a line of `---`
- **⌃⌥→** next slide, **⌃⌥←** previous
- Works from any app, even while your slides are focused

---

## Teleprompter

- **⌃⌥Space** starts or stops auto-scroll
- **⌃⌥↑** faster, **⌃⌥↓** slower

---

## Click-through

**⌃⌥T** lets clicks pass through this window to whatever is under it.
Press it again to use the window.

---

## Your own notes

- **⌘O** opens a Markdown file, or drop one on this window
- **⌘E** edits the notes, **⌘E** again to present
- **⌘+ / ⌘−** text size, **⌘] / ⌘[** see-through

Test once before a real call: share your full screen and record it.
"""
