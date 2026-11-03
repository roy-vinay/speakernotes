// Prints the window number of the largest on-screen window owned by the named app.
import CoreGraphics
import Foundation

let name = CommandLine.arguments.dropFirst().first?.lowercased() ?? "speakernotes"
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
var best: (Int, CGFloat)?
for w in windows where (w[kCGWindowOwnerName as String] as? String)?.lowercased() == name {
    guard let n = w[kCGWindowNumber as String] as? Int,
          let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
    let area = (b["Width"] ?? 0) * (b["Height"] ?? 0)
    if area > (best?.1 ?? 0) { best = (n, area) }
}
if let best { print(best.0); exit(0) }
FileHandle.standardError.write(Data("No window found for \(name). Owners: \(Set(windows.compactMap { $0[kCGWindowOwnerName as String] as? String }))\n".utf8))
exit(1)
