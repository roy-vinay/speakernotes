import XCTest
@testable import SpeakerNotesCore

final class NotesParserTests: XCTestCase {
    func testSplitsOnSeparators() {
        let text = "# Intro\nHello\n\n---\n\n# Problem\n- one\n- two\n---\nLast"
        let slides = NotesParser.slides(in: text)
        XCTAssertEqual(slides.count, 3)
        XCTAssertEqual(slides[0].text, "# Intro\nHello")
        XCTAssertEqual(slides[1].text, "# Problem\n- one\n- two")
        XCTAssertEqual(slides[1].startLine, 5)
        XCTAssertEqual(slides[2].text, "Last")
        XCTAssertEqual(slides[1].title, "Problem")
        XCTAssertEqual(slides[2].title, "Last")
    }

    func testOtherSeparatorStyles() {
        XCTAssertEqual(NotesParser.slides(in: "a\n***\nb\n___\nc\n- - -\nd").count, 4)
    }

    func testDropsEmptySlides() {
        let slides = NotesParser.slides(in: "---\ntitle: x\n---\n\n---\nBody")
        XCTAssertEqual(slides.map(\.text), ["title: x", "Body"])
    }

    func testEmptyNotesGiveOneSlide() {
        XCTAssertEqual(NotesParser.slides(in: ""), [Slide(startLine: 0, text: "")])
        XCTAssertEqual(NotesParser.slides(in: "\n\n  \n").count, 1)
    }

    func testHeadingsSplitWhenThereAreNoSeparators() {
        let text = "Opening line\n# One\ntext\n## Two\nmore\n### Not a split\nx"
        let slides = NotesParser.slides(in: text)
        XCTAssertEqual(slides.map(\.title), ["Opening line", "One", "Two"])
        XCTAssertTrue(slides[2].text.contains("### Not a split"))
    }

    func testSingleHeadingIsOneSlide() {
        XCTAssertEqual(NotesParser.slides(in: "# Talk\nline one\nline two").count, 1)
    }

    func testSeparatorsInsideCodeFencesDontSplit() {
        let text = "Before\n```\n---\n# not a heading\n```\nAfter"
        XCTAssertEqual(NotesParser.slides(in: text).count, 1)
    }

    func testWindowsLineEndings() {
        let slides = NotesParser.slides(in: "a\r\n---\r\nb")
        XCTAssertEqual(slides.map(\.text), ["a", "b"])
    }

    func testSlideIndexForLine() {
        let slides = NotesParser.slides(in: "a\n---\nb\nb2\n---\nc")
        XCTAssertEqual(NotesParser.slideIndex(forLine: 0, in: slides), 0)
        XCTAssertEqual(NotesParser.slideIndex(forLine: 1, in: slides), 0)
        XCTAssertEqual(NotesParser.slideIndex(forLine: 3, in: slides), 1)
        XCTAssertEqual(NotesParser.slideIndex(forLine: 99, in: slides), 2)
    }

    func testBlocks() {
        let text = """
            ## Key point
            First line
            continues here

            - bullet **bold**
              - nested
            * star bullet
            1. first
            2) second
            > a quote
            - [ ] todo
            - [x] done
            ```
            code --- here
            ```
            """
        XCTAssertEqual(NotesParser.blocks(in: text), [
            .heading(level: 2, text: "Key point"),
            .paragraph(text: "First line continues here"),
            .blank,
            .bullet(indent: 0, text: "bullet **bold**"),
            .bullet(indent: 1, text: "nested"),
            .bullet(indent: 0, text: "star bullet"),
            .numbered(indent: 0, number: "1.", text: "first"),
            .numbered(indent: 0, number: "2.", text: "second"),
            .quote(text: "a quote"),
            .bullet(indent: 0, text: "☐ todo"),
            .bullet(indent: 0, text: "☑ done"),
            .code(text: "code --- here"),
        ])
    }

    func testNotHeadingsOrBullets() {
        XCTAssertEqual(NotesParser.blocks(in: "#hashtag\n-dash\n2024 was big"),
                       [.paragraph(text: "#hashtag -dash 2024 was big")])
    }

    func testUnclosedFenceStillShows() {
        XCTAssertEqual(NotesParser.blocks(in: "```\nlet x = 1"), [.code(text: "let x = 1")])
    }
}
