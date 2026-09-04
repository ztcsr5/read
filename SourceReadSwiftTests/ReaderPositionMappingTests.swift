import XCTest
@testable import SourceReadSwift

final class ReaderPositionMappingTests: XCTestCase {
    func testEmptyContentAlwaysResolvesToZero() {
        let mapping = ReaderPositionMapping(paragraphCount: 0, pageFirstParagraphs: [])
        XCTAssertEqual(mapping.clampParagraph(-20), 0)
        XCTAssertEqual(mapping.page(containingParagraph: 99), 0)
        XCTAssertEqual(mapping.paragraph(forPage: 4), 0)
    }

    func testParagraphAndPageMappingClampsAndPreservesLocation() {
        let mapping = ReaderPositionMapping(paragraphCount: 10, pageFirstParagraphs: [0, 3, 7])
        XCTAssertEqual(mapping.page(containingParagraph: 0), 0)
        XCTAssertEqual(mapping.page(containingParagraph: 2), 0)
        XCTAssertEqual(mapping.page(containingParagraph: 3), 1)
        XCTAssertEqual(mapping.page(containingParagraph: 9), 2)
        XCTAssertEqual(mapping.page(containingParagraph: 999), 2)
        XCTAssertEqual(mapping.paragraph(forPage: 1), 3)
        XCTAssertEqual(mapping.paragraph(forPage: -1), 0)
        XCTAssertEqual(mapping.paragraph(forPage: 99), 7)
    }

    func testModeSwitchUsesOneParagraphPosition() {
        let mapping = ReaderPositionMapping(paragraphCount: 12, pageFirstParagraphs: [0, 4, 8])
        let paragraph = 6
        let page = mapping.target(for: .pageTurn, paragraph: paragraph)
        XCTAssertEqual(page, 1)
        XCTAssertEqual(mapping.paragraph(for: page, mode: .pageTurn), 4)
        XCTAssertEqual(mapping.target(for: .scroll, paragraph: paragraph), paragraph)
    }

    func testAutomationSessionRejectsOldGenerationAfterRestart() {
        var session = ReaderAutomationSession()
        let first = session.startAutoScroll()
        XCTAssertTrue(session.acceptsAutoScroll(first))
        let second = session.startSpeaking()
        XCTAssertFalse(session.acceptsAutoScroll(first))
        XCTAssertTrue(session.acceptsSpeech(second))
        session.stop()
        XCTAssertFalse(session.acceptsSpeech(second))
    }
}
