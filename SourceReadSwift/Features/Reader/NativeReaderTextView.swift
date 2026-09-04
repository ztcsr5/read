import SwiftUI
import UIKit

/// A TextKit-backed reader surface. SwiftUI remains responsible for the
/// surrounding chrome, while UIKit owns the long-form text layout and scroll
/// physics so paragraph updates do not rebuild a LazyVStack every frame.
struct NativeReaderTextView: UIViewRepresentable {
    let title: String
    var subtitle: String? = nil
    let paragraphs: [String]
    /// A caller-provided revision lets the native surface detect edits to a
    /// paragraph in the middle of a long chapter without hashing that chapter
    /// during every SwiftUI body evaluation. It is optional for existing call sites.
    var contentFingerprint: String? = nil
    let fontSize: Double
    let lineSpacing: Double
    let pagePadding: Double
    let letterSpacing: Double
    let paragraphSpacing: Double
    let paragraphIndent: Double
    let titleSpacing: Double
    let footerHeight: Double
    let textColor: UIColor
    let highlightColor: UIColor
    let currentParagraphIndex: Int
    let scrollTarget: Int?
    let scrollRequestKey: String?
    let animatedScrollDuration: Double
    let textSelectionEnabled: Bool
    let onVisibleParagraph: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onVisibleParagraph: onVisibleParagraph)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = textSelectionEnabled
        textView.isScrollEnabled = true
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        textView.alwaysBounceVertical = true
        textView.delaysContentTouches = false
        textView.canCancelContentTouches = true
        textView.textContainer.lineFragmentPadding = 0
        textView.contentInsetAdjustmentBehavior = .never
        textView.setContentHuggingPriority(.defaultLow, for: .vertical)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        context.coordinator.attach(textView)
        context.coordinator.update(textView: textView, configuration: configuration, scrollTarget: scrollTarget, scrollRequestKey: scrollRequestKey)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.update(textView: textView, configuration: configuration, scrollTarget: scrollTarget, scrollRequestKey: scrollRequestKey)
        context.coordinator.updateHighlight(currentParagraphIndex, in: textView, color: highlightColor)
        textView.isSelectable = textSelectionEnabled
    }

    private var configuration: Configuration {
        Configuration(
            title: title,
            subtitle: subtitle,
            paragraphs: paragraphs,
            contentFingerprint: contentFingerprint?.nilIfEmpty
                ?? [title, subtitle ?? "", String(paragraphs.count), String(paragraphs.first?.hashValue ?? 0), String(paragraphs.last?.hashValue ?? 0)].joined(separator: "|"),
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            pagePadding: pagePadding,
            letterSpacing: letterSpacing,
            paragraphSpacing: paragraphSpacing,
            paragraphIndent: paragraphIndent,
            titleSpacing: titleSpacing,
            footerHeight: footerHeight,
            textColor: textColor,
            highlightColor: highlightColor,
            animatedScrollDuration: animatedScrollDuration
        )
    }

    struct Configuration: Equatable {
        let title: String
        let subtitle: String?
        let paragraphs: [String]
        let contentFingerprint: String
        let fontSize: Double
        let lineSpacing: Double
        let pagePadding: Double
        let letterSpacing: Double
        let paragraphSpacing: Double
        let paragraphIndent: Double
        let titleSpacing: Double
        let footerHeight: Double
        let textColor: UIColor
        let highlightColor: UIColor
        let animatedScrollDuration: Double

        static func == (lhs: Configuration, rhs: Configuration) -> Bool {
            lhs.contentFingerprint == rhs.contentFingerprint
                && lhs.fontSize == rhs.fontSize
                && lhs.lineSpacing == rhs.lineSpacing
                && lhs.pagePadding == rhs.pagePadding
                && lhs.letterSpacing == rhs.letterSpacing
                && lhs.paragraphSpacing == rhs.paragraphSpacing
                && lhs.paragraphIndent == rhs.paragraphIndent
                && lhs.titleSpacing == rhs.titleSpacing
                && lhs.footerHeight == rhs.footerHeight
                && lhs.textColor.isEqual(rhs.textColor)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIScrollViewDelegate {
        private weak var textView: UITextView?
        private let visibleParagraphCallback: (Int) -> Void
        private var configuration: Configuration?
        private var paragraphRanges: [NSRange] = []
        private var lastHighlightedParagraph = -1
        private var lastHighlightColor: UIColor?
        private var lastScrollRequestKey: String?
        private var lastVisibleParagraph = -1
        private var lastVisibleUpdateAt = Date.distantPast

        init(onVisibleParagraph: @escaping (Int) -> Void) {
            visibleParagraphCallback = onVisibleParagraph
        }

        func attach(_ textView: UITextView) {
            self.textView = textView
            textView.delegate = self
            textView.scrollsToTop = true
        }

        func update(textView: UITextView, configuration newConfiguration: Configuration, scrollTarget: Int?, scrollRequestKey: String?) {
            attach(textView)
            let contentChanged = configuration?.contentFingerprint != newConfiguration.contentFingerprint
            if configuration != newConfiguration {
                let previousOffset = textView.contentOffset
                configuration = newConfiguration
                rebuild(textView: textView, configuration: newConfiguration)
                if textView.bounds.height > 0, !contentChanged {
                    textView.setContentOffset(previousOffset, animated: false)
                }
                // A new chapter needs its initial target; settings/theme
                // changes preserve the existing offset and request key.
                if contentChanged {
                    lastScrollRequestKey = nil
                }
                lastVisibleParagraph = -1
                lastVisibleUpdateAt = .distantPast
            }
            guard let scrollTarget,
                  newConfiguration.paragraphs.indices.contains(scrollTarget),
                  scrollRequestKey != lastScrollRequestKey else { return }
            guard scrollToParagraph(scrollTarget, in: textView, animated: newConfiguration.animatedScrollDuration > 0, duration: newConfiguration.animatedScrollDuration) else { return }
            lastScrollRequestKey = scrollRequestKey
        }

        func updateHighlight(_ paragraphIndex: Int, in textView: UITextView, color: UIColor) {
            let colorChanged = lastHighlightColor?.isEqual(color) != true
            guard paragraphIndex != lastHighlightedParagraph || colorChanged else { return }
            let previous = lastHighlightedParagraph
            lastHighlightedParagraph = paragraphIndex
            lastHighlightColor = color
            guard let configuration else { return }
            textView.textStorage.beginEditing()
            if paragraphRanges.indices.contains(previous) {
                textView.textStorage.removeAttribute(.backgroundColor, range: paragraphRanges[previous])
            }
            if paragraphRanges.indices.contains(paragraphIndex) {
                textView.textStorage.addAttribute(.backgroundColor, value: color, range: paragraphRanges[paragraphIndex])
            }
            textView.textStorage.endEditing()
            // Keep the base color alive when a theme changes without forcing a
            // complete rebuild for every speech callback.
            if paragraphIndex < 0, configuration.paragraphs.isEmpty == false {
                textView.textStorage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: textView.textStorage.length))
            }
        }

        private func rebuild(textView: UITextView, configuration: Configuration) {
            let result = ReaderNativeTextLayout.makeAttributedText(configuration: configuration)
            paragraphRanges = result.paragraphRanges
            lastHighlightedParagraph = -1
            textView.textContainerInset = UIEdgeInsets(
                top: CGFloat(configuration.pagePadding),
                left: CGFloat(configuration.pagePadding),
                bottom: CGFloat(configuration.pagePadding + configuration.footerHeight),
                right: CGFloat(configuration.pagePadding)
            )
            textView.attributedText = result.text
            textView.textColor = configuration.textColor
            textView.setNeedsLayout()
        }

        @discardableResult
        private func scrollToParagraph(_ index: Int, in textView: UITextView, animated: Bool, duration: Double) -> Bool {
            guard paragraphRanges.indices.contains(index), textView.bounds.height > 0 else { return false }
            textView.layoutIfNeeded()
            let range = paragraphRanges[index]
            let glyphRange = textView.layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = textView.layoutManager.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer)
            let minimumY = -textView.adjustedContentInset.top
            let targetY = max(minimumY, rect.minY + textView.textContainerInset.top)
            let maximumY = max(minimumY, textView.contentSize.height - textView.bounds.height + textView.adjustedContentInset.bottom)
            let offset = CGPoint(x: 0, y: min(max(targetY, minimumY), maximumY))
            if animated {
                UIView.animate(
                    withDuration: min(max(duration * 0.9, 0.25), 8),
                    delay: 0,
                    options: [.curveLinear, .beginFromCurrentState, .allowUserInteraction, .allowAnimatedContent]
                ) {
                    textView.setContentOffset(offset, animated: false)
                }
            } else {
                textView.setContentOffset(offset, animated: false)
            }
            return true
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let textView = scrollView as? UITextView,
                  let configuration,
                  !paragraphRanges.isEmpty else { return }
            let now = Date()
            guard now.timeIntervalSince(lastVisibleUpdateAt) >= 0.08 else { return }
            lastVisibleUpdateAt = now
            let visibleRect = CGRect(
                x: 0,
                y: max(textView.contentOffset.y - textView.textContainerInset.top, 0),
                width: textView.bounds.width,
                height: textView.bounds.height
            )
            let glyphRange = textView.layoutManager.glyphRange(forBoundingRect: visibleRect, in: textView.textContainer)
            guard glyphRange.length > 0 else { return }
            let visibleCharacterRange = textView.layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let index = ReaderParagraphIndexResolver.firstVisibleIndex(
                in: paragraphRanges,
                visibleRange: visibleCharacterRange
            )
            guard let index, index != lastVisibleParagraph else { return }
            lastVisibleParagraph = index
            visibleParagraphCallback(index)
        }
    }
}

/// Resolves the first paragraph intersecting the visible character range in
/// O(log n). Long chapters can contain thousands of paragraph ranges; a full
/// linear scan on every scroll callback needlessly steals main-thread time.
enum ReaderParagraphIndexResolver {
    static func firstVisibleIndex(in ranges: [NSRange], visibleRange: NSRange) -> Int? {
        guard !ranges.isEmpty, visibleRange.length > 0 else { return nil }
        let visibleStart = visibleRange.location
        var lower = 0
        var upper = ranges.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if NSMaxRange(ranges[middle]) <= visibleStart {
                lower = middle + 1
            } else {
                upper = middle
            }
        }

        guard ranges.indices.contains(lower) else { return nil }
        if NSIntersectionRange(ranges[lower], visibleRange).length > 0 {
            return lower
        }
        return ranges[lower...].firstIndex { $0.location >= visibleStart }
    }
}

enum ReaderNativeTextLayout {
    struct Result {
        let text: NSAttributedString
        let paragraphRanges: [NSRange]
    }

    static func makeAttributedText(configuration: NativeReaderTextView.Configuration) -> Result {
        let output = NSMutableAttributedString(string: "")
        var ranges: [NSRange] = []
        let titleStyle = NSMutableParagraphStyle()
        titleStyle.lineSpacing = CGFloat(configuration.lineSpacing)
        titleStyle.paragraphSpacing = CGFloat(configuration.paragraphSpacing + configuration.titleSpacing)
        titleStyle.alignment = .natural
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: CGFloat(configuration.fontSize + 8), weight: .bold),
            .foregroundColor: configuration.textColor,
            .paragraphStyle: titleStyle
        ]
        output.append(NSAttributedString(string: configuration.title + "\n", attributes: titleAttributes))

        if let subtitle = configuration.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !subtitle.isEmpty {
            let subtitleStyle = NSMutableParagraphStyle()
            subtitleStyle.paragraphSpacing = CGFloat(configuration.titleSpacing)
            subtitleStyle.alignment = .natural
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: max(CGFloat(configuration.fontSize - 5), 12), weight: .regular),
                .foregroundColor: configuration.textColor.withAlphaComponent(0.62),
                .paragraphStyle: subtitleStyle
            ]
            output.append(NSAttributedString(string: subtitle + "\n", attributes: subtitleAttributes))
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = CGFloat(configuration.lineSpacing)
        paragraphStyle.paragraphSpacing = CGFloat(configuration.paragraphSpacing)
        paragraphStyle.headIndent = CGFloat(configuration.paragraphIndent)
        paragraphStyle.firstLineHeadIndent = CGFloat(configuration.paragraphIndent)
        paragraphStyle.alignment = .natural
        let paragraphAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: CGFloat(configuration.fontSize), weight: .regular),
            .foregroundColor: configuration.textColor,
            .kern: configuration.letterSpacing,
            .paragraphStyle: paragraphStyle
        ]
        for paragraph in configuration.paragraphs {
            let start = output.length
            output.append(NSAttributedString(string: paragraph, attributes: paragraphAttributes))
            ranges.append(NSRange(location: start, length: paragraph.utf16.count))
            output.append(NSAttributedString(string: "\n\n", attributes: paragraphAttributes))
        }
        return Result(text: output, paragraphRanges: ranges)
    }
}
