import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular) // a Dock icon, so it's always easy to find and relaunch
app.run()
