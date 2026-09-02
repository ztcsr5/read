import Foundation

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

/// Deterministic segment queue used by the AVSpeech controller.
struct ReaderSpeechQueue: Equatable {
    private(set) var segments: [String] = []
    private(set) var paragraphIndexes: [Int] = []
    private(set) var nextIndex = 0

    var isFinished: Bool { nextIndex >= segments.count }

    mutating func reset(title: String, paragraphs: [String]) {
        segments = []
        paragraphIndexes = []
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            segments.append(trimmedTitle)
            paragraphIndexes.append(-1)
        }
        for (index, paragraph) in paragraphs.enumerated() {
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
