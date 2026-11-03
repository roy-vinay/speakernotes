import AppKit
import SpeakerNotesCore

/// Turns one slide's Markdown into styled text for presenting.
enum MarkdownRenderer {
    static let textColor = Theme.text
    static let dimColor = NSColor(white: 1, alpha: 0.62)

    static func render(_ text: String, style: TextStyle, emphasis: [EmphasisRule] = []) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let size = style.size
        let bulletWidth = size * 1.15
        let indentStep = size * 1.3

        for block in NotesParser.blocks(in: text) {
            let para = NSMutableParagraphStyle()
            para.lineHeightMultiple = style.lineSpacing
            para.paragraphSpacing = size * 0.55
            var font = style.font()
            var color = textColor
            var prefix = ""
            var content = ""
            var inline = true

            switch block {
            case .heading(let level, let t):
                let scale: CGFloat = level == 1 ? 1.32 : level == 2 ? 1.16 : 1.04
                font = style.font(scale, .bold)
                color = level <= 2 ? Theme.accent : textColor
                para.lineHeightMultiple = 1.05
                para.paragraphSpacing = size * 0.45
                content = t
            case .bullet(let indent, let t), .numbered(let indent, _, let t):
                if case .numbered(_, let number, _) = block { prefix = number + "\t" } else { prefix = "•\t" }
                let left = CGFloat(indent) * indentStep
                para.firstLineHeadIndent = left
                para.headIndent = left + bulletWidth
                para.tabStops = [NSTextTab(textAlignment: .left, location: left + bulletWidth)]
                para.paragraphSpacing = size * 0.3
                content = t
            case .quote(let t):
                color = dimColor
                para.firstLineHeadIndent = indentStep * 0.6
                para.headIndent = indentStep * 0.6
                prefix = "┃ "
                content = t
            case .code(let t):
                font = .monospacedSystemFont(ofSize: size * 0.82, weight: .regular)
                color = dimColor
                content = t
                inline = false
            case .paragraph(let t):
                content = t
            case .blank:
                continue // blank lines already show as paragraph spacing
            }

            let line = NSMutableAttributedString(string: prefix, attributes: [.font: font, .foregroundColor: Theme.accent])
            line.append(inline ? inlineMarkdown(content, font: font, color: color)
                               : NSAttributedString(string: content, attributes: [.font: font, .foregroundColor: color]))
            line.append(NSAttributedString(string: "\n", attributes: [.font: font]))
            line.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: line.length))
            out.append(line)
        }
        if out.length == 0 {
            out.append(NSAttributedString(string: "No notes on this slide.", attributes: [
                .font: style.font(), .foregroundColor: dimColor,
            ]))
        }
        EmphasisPainter.apply(emphasis, to: out)
        return out
    }

    /// Bold, italic, code, strikethrough, links and ==highlights== inside one line.
    static func inlineMarkdown(_ text: String, font: NSFont, color: NSColor) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let ns: NSMutableAttributedString
        if let parsed = try? AttributedString(markdown: text, options: options) {
            ns = NSMutableAttributedString(attributedString: NSAttributedString(parsed))
        } else {
            ns = NSMutableAttributedString(string: text)
        }
        let full = NSRange(location: 0, length: ns.length)
        ns.addAttributes([.font: font, .foregroundColor: color], range: full)
        ns.enumerateAttribute(.inlinePresentationIntent, in: full) { value, range, _ in
            let intent: InlinePresentationIntent
            if let i = value as? InlinePresentationIntent { intent = i }
            else if let n = value as? NSNumber { intent = InlinePresentationIntent(rawValue: n.uintValue) }
            else { return }
            var f = font
            if intent.contains(.code) {
                f = .monospacedSystemFont(ofSize: font.pointSize * 0.9, weight: .medium)
                ns.addAttribute(.foregroundColor, value: Theme.accent, range: range)
            }
            if intent.contains(.stronglyEmphasized) {
                f = NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask)
                ns.addAttribute(.foregroundColor, value: NSColor.white, range: range)
            }
            if intent.contains(.emphasized) { f = NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask) }
            ns.addAttribute(.font, value: f, range: range)
            if intent.contains(.strikethrough) {
                ns.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
        }
        ns.enumerateAttribute(.link, in: full) { value, range, _ in
            if value != nil { ns.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: range) }
        }
        applyHighlightMarks(ns)
        return ns
    }

    /// `==text==` shows as highlighted text, without the equals signs.
    static func applyHighlightMarks(_ ns: NSMutableAttributedString) {
        guard let regex = try? NSRegularExpression(pattern: "==(?=\\S)(.+?)(?<=\\S)==") else { return }
        let matches = regex.matches(in: ns.string, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            let inner = match.range(at: 1)
            EmphasisPainter.apply(.highlight, to: ns, range: inner)
            ns.deleteCharacters(in: NSRange(location: inner.upperBound, length: 2))
            ns.deleteCharacters(in: NSRange(location: match.range.location, length: 2))
        }
    }
}
