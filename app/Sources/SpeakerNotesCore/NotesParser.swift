import Foundation

/// One slide's worth of notes.
public struct Slide: Equatable {
    /// Zero-based line in the whole document where this slide's text starts.
    public let startLine: Int
    /// The slide's notes, without the separator and without leading or trailing blank lines.
    public let text: String

    public init(startLine: Int, text: String) {
        self.startLine = startLine
        self.text = text
    }

    /// A short label: the first heading, or else the first line of text.
    public var title: String {
        for block in NotesParser.blocks(in: text) {
            switch block {
            case .heading(_, let t): return t
            case .blank: continue
            case .paragraph(let t), .bullet(_, let t), .numbered(_, _, let t), .quote(let t), .code(let t):
                return t.split(separator: "\n").first.map(String.init) ?? t
            }
        }
        return ""
    }
}

/// A line-level piece of Markdown, enough to show notes clearly.
public enum Block: Equatable {
    case heading(level: Int, text: String)
    case bullet(indent: Int, text: String)
    case numbered(indent: Int, number: String, text: String)
    case quote(text: String)
    case code(text: String)
    case paragraph(text: String)
    case blank
}

public enum NotesParser {
    /// Splits notes into slides.
    ///
    /// A line that is only `---`, `***` or `___` separates slides. If the notes have no separators,
    /// each `#` or `##` heading starts a new slide. Separators and headings inside code fences
    /// don't count. Empty slides are dropped, and notes with no text give one empty slide.
    public static func slides(in text: String) -> [Slide] {
        let lines = splitLines(text)
        var fence = false
        var separators: [Int] = []
        var headings: [Int] = []
        for (i, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if isFence(line) { fence.toggle(); continue }
            if fence { continue }
            if isSeparator(line) { separators.append(i) }
            if headingLevel(line).map({ $0 <= 2 }) == true { headings.append(i) }
        }

        // Ranges of lines, each one slide (half-open).
        var ranges: [Range<Int>] = []
        if !separators.isEmpty {
            var start = 0
            for s in separators {
                ranges.append(start..<s)
                start = s + 1
            }
            ranges.append(start..<lines.count)
        } else if headings.count > 1 {
            var start = 0
            for h in headings where h > 0 {
                ranges.append(start..<h)
                start = h
            }
            ranges.append(start..<lines.count)
        } else {
            ranges = [0..<lines.count]
        }

        var slides: [Slide] = []
        for range in ranges {
            var lo = range.lowerBound
            var hi = range.upperBound
            while lo < hi, isBlank(lines[lo]) { lo += 1 }
            while hi > lo, isBlank(lines[hi - 1]) { hi -= 1 }
            guard lo < hi else { continue }
            slides.append(Slide(startLine: lo, text: lines[lo..<hi].joined(separator: "\n")))
        }
        return slides.isEmpty ? [Slide(startLine: 0, text: "")] : slides
    }

    /// The slide that contains a given zero-based line of the document.
    public static func slideIndex(forLine line: Int, in slides: [Slide]) -> Int {
        var result = 0
        for (i, slide) in slides.enumerated() where slide.startLine <= line {
            result = i
        }
        return result
    }

    /// Reads a slide's notes as Markdown blocks.
    public static func blocks(in text: String) -> [Block] {
        var blocks: [Block] = []
        var fence: [String]? = nil
        var paragraph: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(text: paragraph.joined(separator: " ")))
                paragraph = []
            }
        }

        for raw in splitLines(text) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if isFence(line) {
                if let body = fence {
                    blocks.append(.code(text: body.joined(separator: "\n")))
                    fence = nil
                } else {
                    flushParagraph()
                    fence = []
                }
                continue
            }
            if fence != nil {
                fence!.append(raw)
                continue
            }
            if line.isEmpty {
                flushParagraph()
                if blocks.last != .blank && !blocks.isEmpty { blocks.append(.blank) }
                continue
            }
            if isSeparator(line) {
                flushParagraph()
                continue
            }
            if let level = headingLevel(line) {
                flushParagraph()
                let t = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: level, text: stripClosingHashes(t)))
                continue
            }
            let indent = indentLevel(raw)
            if let item = bulletText(line) {
                flushParagraph()
                blocks.append(.bullet(indent: indent, text: item))
                continue
            }
            if let (number, item) = numberedItem(line) {
                flushParagraph()
                blocks.append(.numbered(indent: indent, number: number, text: item))
                continue
            }
            if line.hasPrefix(">") {
                flushParagraph()
                let t = line.dropFirst().trimmingCharacters(in: .whitespaces)
                blocks.append(.quote(text: t))
                continue
            }
            paragraph.append(line)
        }
        if let body = fence { blocks.append(.code(text: body.joined(separator: "\n"))) }
        flushParagraph()
        while blocks.last == .blank { blocks.removeLast() }
        return blocks
    }

    // MARK: Line helpers

    static func splitLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    }

    static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    static func isFence(_ line: String) -> Bool {
        line.hasPrefix("```") || line.hasPrefix("~~~")
    }

    static func isSeparator(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.isEmpty || rest.first == " " else { return nil }
        return hashes
    }

    static func stripClosingHashes(_ s: String) -> String {
        var t = s
        while t.hasSuffix("#") { t.removeLast() }
        return t.trimmingCharacters(in: .whitespaces)
    }

    static func indentLevel(_ raw: String) -> Int {
        var spaces = 0
        for c in raw {
            if c == " " { spaces += 1 } else if c == "\t" { spaces += 4 } else { break }
        }
        return spaces / 2
    }

    static func bulletText(_ line: String) -> String? {
        guard let first = line.first, "-*+".contains(first) else { return nil }
        let rest = line.dropFirst()
        guard rest.first == " " else { return nil }
        var t = rest.trimmingCharacters(in: .whitespaces)
        // Task list items: show the box as a symbol.
        if t.hasPrefix("[ ] ") { t = "☐ " + t.dropFirst(4) }
        else if t.lowercased().hasPrefix("[x] ") { t = "☑ " + t.dropFirst(4) }
        return t
    }

    static func numberedItem(_ line: String) -> (String, String)? {
        let digits = line.prefix(while: { $0.isNumber })
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard let mark = rest.first, mark == "." || mark == ")", rest.dropFirst().first == " " else { return nil }
        return (digits + ".", rest.dropFirst(2).trimmingCharacters(in: .whitespaces))
    }
}
