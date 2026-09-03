import XCTest
@testable import SourceReadSwift

final class ReaderAutomationPolicyTests: XCTestCase {
    func testAdvancesWithinCurrentChapter() {
        XCTAssertEqual(
            ReaderAutomationPolicy.decision(currentTarget: 2, maximumTarget: 5, canAdvanceChapter: true),
            .advance(to: 3)
        )
    }

    func testMovesToNextChapterAtBoundary() {
        XCTAssertEqual(
            ReaderAutomationPolicy.decision(currentTarget: 5, maximumTarget: 5, canAdvanceChapter: true),
            .nextChapter
        )
    }

    func testStopsAtFinalChapter() {
        XCTAssertEqual(
            ReaderAutomationPolicy.decision(currentTarget: 5, maximumTarget: 5, canAdvanceChapter: false),
            .stop
        )
    }

    func testSpeechQueueFiltersEmptySegmentsAndPreservesIndexes() {
        var queue = ReaderSpeechQueue()
        queue.reset(title: " Title ", paragraphs: ["", "第一段", "  ", "第二段"])

        XCTAssertEqual(queue.dequeue()?.index, -1)
        XCTAssertEqual(queue.dequeue()?.text, "第一段")
        XCTAssertEqual(queue.dequeue()?.index, 3)
        XCTAssertNil(queue.dequeue())
        XCTAssertTrue(queue.isFinished)
    }

    func testSpeechQueueStartsAtVisibleParagraphWithoutReplayingChapterStart() {
        var queue = ReaderSpeechQueue()
        queue.reset(title: "标题", paragraphs: ["第一段", "第二段", "第三段"], startParagraphIndex: 1)

        XCTAssertEqual(queue.dequeue()?.index, 1)
        XCTAssertEqual(queue.dequeue()?.index, 2)
        XCTAssertNil(queue.dequeue())
    }

    @MainActor
    func testPlaybackStateRejectsStaleGenerationAfterStop() {
        let coordinator = ReaderPlaybackCoordinator()
        let token = coordinator.beginAutoScroll()
        XCTAssertTrue(coordinator.accepts(token, for: .autoScroll(generation: token)))
        coordinator.stop()
        XCTAssertFalse(coordinator.accepts(token, for: .autoScroll(generation: token)))
    }

    @MainActor
    func testPlaybackStateTransitionsSpeechPauseAndResume() {
        let coordinator = ReaderPlaybackCoordinator()
        let token = coordinator.beginSpeech()
        coordinator.pauseSpeech()
        XCTAssertEqual(coordinator.mode, .pausedSpeech(generation: token))
        coordinator.resumeSpeech()
        XCTAssertEqual(coordinator.mode, .speech(generation: token))
        XCTAssertTrue(coordinator.accepts(token, for: .speech(generation: token)))
    }
}
