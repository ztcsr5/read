import Foundation
import Combine

/// Deterministic decisions for automatic reader advancement.
/// Kept independent from SwiftUI so chapter-boundary behavior is testable on CI.
enum ReaderAdvanceDecision: Equatable {
    case advance(to: Int)
    case nextChapter
    case stop
}

struct ReaderAutomationPolicy {
    static func decision(
        currentTarget: Int,
        maximumTarget: Int,
        canAdvanceChapter: Bool
    ) -> ReaderAdvanceDecision {
        guard maximumTarget >= 0 else {
            return canAdvanceChapter ? .nextChapter : .stop
        }
        guard currentTarget < maximumTarget else {
            return canAdvanceChapter ? .nextChapter : .stop
        }
        return .advance(to: currentTarget + 1)
    }
}

/// The small, deterministic state machine shared by the reader's automation
/// controls.  Keeping the transitions outside SwiftUI prevents an old timer,
/// speech callback, or scene lifecycle event from reviving a newer session.
enum ReaderPlaybackMode: Equatable {
    case idle
    case autoScroll(generation: Int)
    case speech(generation: Int)
    case pausedSpeech(generation: Int)
}

struct ReaderPlaybackStateMachine: Equatable {
    private(set) var mode: ReaderPlaybackMode = .idle
    private(set) var generation: Int = 0

    mutating func beginAutoScroll() -> Int {
        generation &+= 1
        mode = .autoScroll(generation: generation)
        return generation
    }

    mutating func beginSpeech() -> Int {
        generation &+= 1
        mode = .speech(generation: generation)
        return generation
    }

    mutating func pauseSpeech() {
        if case .speech(let token) = mode {
            mode = .pausedSpeech(generation: token)
        }
    }

    mutating func resumeSpeech() {
        if case .pausedSpeech(let token) = mode {
            mode = .speech(generation: token)
        }
    }

    mutating func stop() {
        generation &+= 1
        mode = .idle
    }

    func accepts(_ token: Int, for expectedMode: ReaderPlaybackMode) -> Bool {
        guard token == generation else { return false }
        switch (mode, expectedMode) {
        case (.autoScroll(let active), .autoScroll):
            return active == token
        case (.speech(let active), .speech), (.pausedSpeech(let active), .pausedSpeech):
            return active == token
        default:
            return false
        }
    }
}

final class ReaderPlaybackCoordinator: ObservableObject {
    @Published private(set) var state = ReaderPlaybackStateMachine()

    var mode: ReaderPlaybackMode { state.mode }

    func beginAutoScroll() -> Int { state.beginAutoScroll() }
    func beginSpeech() -> Int { state.beginSpeech() }
    func pauseSpeech() { state.pauseSpeech() }
    func resumeSpeech() { state.resumeSpeech() }
    func stop() { state.stop() }

    func accepts(_ token: Int, for expectedMode: ReaderPlaybackMode) -> Bool {
        state.accepts(token, for: expectedMode)
    }
}

/// Deterministic segment queue used by the AVSpeech controller.
struct ReaderSpeechQueue: Equatable {
    private(set) var segments: [String] = []
    private(set) var paragraphIndexes: [Int] = []
    private(set) var nextIndex = 0

    var isFinished: Bool { nextIndex >= segments.count }

    mutating func reset(title: String, paragraphs: [String], startParagraphIndex: Int = 0) {
        segments = []
        paragraphIndexes = []
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeStart = min(max(startParagraphIndex, 0), max(paragraphs.count - 1, 0))
        // The chapter title is useful only when playback starts at the actual
        // chapter beginning. Starting TTS from a visible page must never jump
        // back to the title or earlier paragraphs.
        if safeStart == 0, !trimmedTitle.isEmpty {
            segments.append(trimmedTitle)
            paragraphIndexes.append(-1)
        }
        for (index, paragraph) in paragraphs.enumerated() where index >= safeStart {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            segments.append(trimmed)
            paragraphIndexes.append(index)
        }
        nextIndex = 0
    }

    mutating func dequeue() -> (index: Int, text: String)? {
        guard segments.indices.contains(nextIndex) else { return nil }
        let index = nextIndex
        nextIndex += 1
        return (paragraphIndexes[index], segments[index])
    }

    mutating func clear() {
        segments = []
        paragraphIndexes = []
        nextIndex = 0
    }
}
