import AppKit
import SpeakerNotesCore

/// Turns one slide's Markdown into styled text for presenting.
enum MarkdownRenderer {
    static let textColor = NSColor(white: 0.96, alpha: 1)
    static let dimColor = NSColor(white: 0.68, alpha: 1)
    static let accentColor = NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.36, alpha: 1)

    static func render(_ text: String, fontSize: CGFloat) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let blocks = NotesParser.blocks(in: text)
        let bulletWidth = fontSize * 1.2
        let indentStep = fontSize * 1.3

        for block in blocks {
            let para = NSMutableParagraphStyle()
            para.lineSpacing = fontSize * 0.18
            para.paragraphSpacing = fontSize * 0.45
            var font = NSFont.systemFont(ofSize: fontSize)
            var color = textColor
            var prefix = ""
            var content = ""
            var inline = true

            switch block {
            case .heading(let level, let t):
                let scale: CGFloat = level == 1 ? 1.35 : level == 2 ? 1.18 : 1.05
                font = .systemFont(ofSize: fontSize * scale, weight: .bold)
                color = level <= 2 ? accentColor : textColor
                para.paragraphSpacing = fontSize * 0.5
                content = t
            case .bullet(let indent, let t), .numbered(let indent, _, let t):
                if case .numbered(_, let number, _) = block { prefix = number + "\t" } else { prefix = "•\t" }
                let left = CGFloat(indent) * indentStep
                para.firstLineHeadIndent = left
                para.headIndent = left + bulletWidth
                para.tabStops = [NSTextTab(textAlignment: .left, location: left + bulletWidth)]
                para.paragraphSpacing = fontSize * 0.25
                content = t
            case .quote(let t):
                color = dimColor
                para.firstLineHeadIndent = indentStep * 0.6
                para.headIndent = indentStep * 0.6
                prefix = "│ "
                content = t
            case .code(let t):
                font = .monospacedSystemFont(ofSize: fontSize * 0.85, weight: .regular)
                color = dimColor
                content = t
                inline = false
            case .paragraph(let t):
                content = t
            case .blank:
                // Blank lines already show as paragraph spacing.
                continue
            }

            let line = NSMutableAttributedString(string: prefix, attributes: [.font: font, .foregroundColor: dimColor])
            line.append(inline ? inlineMarkdown(content, font: font, color: color)
                               : NSAttributedString(string: content, attributes: [.font: font, .foregroundColor: color]))
            line.append(NSAttributedString(string: "\n", attributes: [.font: font]))
            line.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: line.length))
            out.append(line)
        }
        if out.length == 0 {
            out.append(NSAttributedString(string: "No notes on this slide.", attributes: [
                .font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: dimColor,
            ]))
        }
        return out
    }

    /// Bold, italic, code, strikethrough and links inside one line.
    static func inlineMarkdown(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let parsed = try? AttributedString(markdown: text, options: options) else {
            return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        }
        let ns = NSMutableAttributedString(attributedString: NSAttributedString(parsed))
        let full = NSRange(location: 0, length: ns.length)
        ns.addAttributes([.font: font, .foregroundColor: color], range: full)
        ns.enumerateAttribute(.inlinePresentationIntent, in: full) { value, range, _ in
            let intent: InlinePresentationIntent
            if let i = value as? InlinePresentationIntent { intent = i }
            else if let n = value as? NSNumber { intent = InlinePresentationIntent(rawValue: n.uintValue) }
            else { return }
            var f = font
            if intent.contains(.code) {
                f = .monospacedSystemFont(ofSize: font.pointSize * 0.92, weight: .regular)
                ns.addAttribute(.foregroundColor, value: accentColor, range: range)
            }
            var traits = f.fontDescriptor.symbolicTraits
            if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
            if intent.contains(.emphasized) { traits.insert(.italic) }
            if traits != f.fontDescriptor.symbolicTraits {
                f = NSFont(descriptor: f.fontDescriptor.withSymbolicTraits(traits), size: f.pointSize) ?? f
            }
            ns.addAttribute(.font, value: f, range: range)
            if intent.contains(.strikethrough) {
                ns.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
        }
        ns.enumerateAttribute(.link, in: full) { value, range, _ in
            if value != nil { ns.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: range) }
        }
        return ns
    }
}
