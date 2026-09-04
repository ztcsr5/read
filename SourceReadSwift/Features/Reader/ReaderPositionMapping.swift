import Foundation

/// Pure position math shared by scroll, paged and cover readers.
///
/// Keeping this logic outside SwiftUI prevents mode switches and malformed
/// persisted values from producing jumps or out-of-range array access.
struct ReaderPositionMapping: Equatable, Sendable {
    let paragraphCount: Int
    let pageFirstParagraphs: [Int]

    init(paragraphCount: Int, pageFirstParagraphs: [Int] = []) {
        self.paragraphCount = max(paragraphCount, 0)
        self.pageFirstParagraphs = pageFirstParagraphs
            .filter { $0 >= 0 }
            .map { min($0, max(paragraphCount - 1, 0)) }
    }

    var maximumParagraphIndex: Int { max(paragraphCount - 1, 0) }
    var maximumPageIndex: Int { max(pageFirstParagraphs.count - 1, 0) }

    func clampParagraph(_ raw: Int?) -> Int {
        guard paragraphCount > 0 else { return 0 }
        return min(max(raw ?? 0, 0), maximumParagraphIndex)
    }

    func paragraph(forPage rawPage: Int?) -> Int {
        guard paragraphCount > 0, !pageFirstParagraphs.isEmpty else { return 0 }
        let page = min(max(rawPage ?? 0, 0), maximumPageIndex)
        return clampParagraph(pageFirstParagraphs[page])
    }

    func page(containingParagraph rawParagraph: Int?) -> Int {
        guard !pageFirstParagraphs.isEmpty else { return 0 }
        let paragraph = clampParagraph(rawParagraph)
        var result = 0
        for (index, firstParagraph) in pageFirstParagraphs.enumerated() {
            if firstParagraph <= paragraph { result = index } else { break }
        }
        return result
    }

    func target(for mode: ReaderMode, paragraph: Int?) -> Int {
        switch mode {
        case .scroll: return clampParagraph(paragraph)
        case .pageTurn, .cover: return page(containingParagraph: paragraph)
        }
    }

    func paragraph(for target: Int?, mode: ReaderMode) -> Int {
        switch mode {
        case .scroll: return clampParagraph(target)
        case .pageTurn, .cover: return paragraph(forPage: target)
        }
    }
}

/// One generation-safe session for reader automation. It intentionally has no
/// UIKit/SwiftUI dependencies, making lifecycle races deterministic in XCTest.
struct ReaderAutomationSession: Equatable, Sendable {
    private(set) var generation = 0
    private(set) var isAutoScrolling = false
    private(set) var isSpeaking = false

    mutating func startAutoScroll() -> Int {
        generation &+= 1
        isAutoScrolling = true
        isSpeaking = false
        return generation
    }

    mutating func startSpeaking() -> Int {
        generation &+= 1
        isAutoScrolling = false
        isSpeaking = true
        return generation
    }

    mutating func stop() {
        generation &+= 1
        isAutoScrolling = false
        isSpeaking = false
    }

    func acceptsAutoScroll(_ token: Int) -> Bool {
        isAutoScrolling && token == generation
    }

    func acceptsSpeech(_ token: Int) -> Bool {
        isSpeaking && token == generation
    }
}
