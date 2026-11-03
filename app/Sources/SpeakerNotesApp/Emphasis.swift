import AppKit

// MARK: - Text style

/// The typeface choices in the Aa panel.
enum Typeface: String, CaseIterable {
    case system, rounded, serif, mono

    var title: String {
        switch self {
        case .system: return "System"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .mono: return "Mono"
        }
    }

    func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let design: NSFontDescriptor.SystemDesign
        switch self {
        case .system: return base
        case .rounded: design = .rounded
        case .serif: design = .serif
        case .mono: design = .monospaced
        }
        guard let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }
}

/// How the notes are set: size, typeface and line spacing.
struct TextStyle {
    var size: CGFloat
    var typeface: Typeface
    var lineSpacing: CGFloat // 1.0 is normal

    static var current: TextStyle {
        TextStyle(size: Settings.fontSize, typeface: Settings.typeface, lineSpacing: Settings.lineSpacing)
    }

    func font(_ scale: CGFloat = 1, _ weight: NSFont.Weight = .regular) -> NSFont {
        typeface.font(size * scale, weight)
    }
}

// MARK: - Emphasis

/// How an emphasized phrase looks.
enum EmphasisStyle: String, Codable, CaseIterable {
    case highlight, bold, color, underline

    var title: String {
        switch self {
        case .highlight: return "Highlight"
        case .bold: return "Bold"
        case .color: return "Color"
        case .underline: return "Underline"
        }
    }

    var symbol: String {
        switch self {
        case .highlight: return "highlighter"
        case .bold: return "bold"
        case .color: return "paintpalette"
        case .underline: return "underline"
        }
    }

    /// Picks a style from what someone typed ("make the names bold" → bold).
    static func guess(from instruction: String) -> EmphasisStyle {
        let s = instruction.lowercased()
        if s.contains("bold") { return .bold }
        if s.contains("underline") { return .underline }
        if s.contains("color") || s.contains("colour") || s.contains("red") || s.contains("orange") { return .color }
        return .highlight
    }
}

/// A set of phrases shown with one emphasis style, for example "engine names" → highlighted.
struct EmphasisRule: Codable, Equatable, Identifiable {
    var id = UUID()
    var label: String
    var phrases: [String]
    var style: EmphasisStyle
}

/// Emphasis is kept per notes file, beside the file's path, so the file itself stays unchanged.
enum EmphasisStore {
    private static func key(for url: URL?) -> String { "emphasis:" + (url?.path ?? "scratch") }

    static func rules(for url: URL?) -> [EmphasisRule] {
        guard let data = UserDefaults.standard.data(forKey: key(for: url)),
              let rules = try? JSONDecoder().decode([EmphasisRule].self, from: data) else { return [] }
        return rules
    }

    static func save(_ rules: [EmphasisRule], for url: URL?) {
        let data = try? JSONEncoder().encode(rules)
        UserDefaults.standard.set(data, forKey: key(for: url))
    }
}

enum EmphasisPainter {
    static let highlightColor = NSColor(calibratedRed: 1.0, green: 0.80, blue: 0.20, alpha: 0.34)

    /// Applies one style to a range of rendered notes.
    static func apply(_ style: EmphasisStyle, to text: NSMutableAttributedString, range: NSRange) {
        switch style {
        case .highlight:
            text.addAttribute(.backgroundColor, value: highlightColor, range: range)
            text.addAttribute(.foregroundColor, value: NSColor.white, range: range)
        case .bold:
            text.enumerateAttribute(.font, in: range) { value, sub, _ in
                guard let font = value as? NSFont else { return }
                let bold = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                text.addAttribute(.font, value: bold, range: sub)
            }
            text.addAttribute(.foregroundColor, value: NSColor.white, range: range)
        case .color:
            text.addAttribute(.foregroundColor, value: Theme.accent, range: range)
        case .underline:
            text.addAttribute(.underlineStyle, value: NSUnderlineStyle.thick.rawValue, range: range)
            text.addAttribute(.underlineColor, value: Theme.accent, range: range)
        }
    }

    /// Every place a phrase appears, ignoring case, on whole words.
    static func matches(of phrase: String, in string: String) -> [NSRange] {
        guard !phrase.isEmpty else { return [] }
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        // Word boundaries only where the phrase starts or ends with a letter or digit.
        let start = phrase.first.map { $0.isLetter || $0.isNumber } == true ? "(?<![\\p{L}\\p{N}])" : ""
        let end = phrase.last.map { $0.isLetter || $0.isNumber } == true ? "(?![\\p{L}\\p{N}])" : ""
        guard let regex = try? NSRegularExpression(pattern: start + escaped + end, options: [.caseInsensitive])
        else { return [] }
        return regex.matches(in: string, range: NSRange(location: 0, length: (string as NSString).length)).map(\.range)
    }

    /// Emphasizes every place a rule's phrases appear.
    static func apply(_ rules: [EmphasisRule], to text: NSMutableAttributedString) {
        for rule in rules {
            for phrase in rule.phrases {
                for range in matches(of: phrase, in: text.string) { apply(rule.style, to: text, range: range) }
            }
        }
    }

    /// How many times a rule's phrases appear in some notes.
    static func count(_ rule: EmphasisRule, in notes: String) -> Int {
        rule.phrases.reduce(0) { $0 + matches(of: $1, in: notes).count }
    }
}
