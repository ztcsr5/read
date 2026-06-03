import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;

class RuleRankCandidate {
  final String selector;
  final double score;
  final int nodeCount;
  final int textLength;
  final double linkDensity;
  final double chineseRatio;

  RuleRankCandidate({
    required this.selector,
    required this.score,
    required this.nodeCount,
    required this.textLength,
    required this.linkDensity,
    required this.chineseRatio,
  });
}

class RuleRankEngine {
  static List<RuleRankCandidate> rankSelectors(String html, String mode) {
    final doc = parse(html);
    final candidates = <String, RuleRankCandidate>{};
    final body = doc.body ?? doc.documentElement;
    if (body == null) return [];

    // Helper to check Chinese ratio
    double calculateChineseRatio(String text) {
      if (text.isEmpty) return 0.0;
      final chineseChars = RegExp(r'[\u4e00-\u9fa5]');
      final count = chineseChars.allMatches(text).length;
      return count / text.length;
    }

    void scan(Element element) {
      final className = element.className.trim();
      final id = element.id.trim();
      final tag = element.localName?.toLowerCase() ?? '';
      
      if (tag == 'script' || tag == 'style' || tag == 'header' || tag == 'footer' || tag == 'nav') {
        for (final child in element.children) {
          scan(child);
        }
        return;
      }

      final text = element.text.trim();
      final totalLen = text.length;

      // Extract anchor text length
      var anchorTextLen = 0;
      for (final a in element.querySelectorAll('a')) {
        anchorTextLen += a.text.trim().length;
      }
      final linkDensity = totalLen > 0 ? anchorTextLen / totalLen : 0.0;
      final chineseRatio = calculateChineseRatio(text);

      void addCandidate(String selector) {
        if (selector.isEmpty) return;
        // Count elements matching this selector in page
        int count = 0;
        try {
          count = doc.querySelectorAll(selector).length;
        } catch (_) {
          return;
        }

        if (count == 0) return;

        double score = 0.0;
        if (mode == 'search') {
          // Search list mode: search cards, moderate child nodes count, medium link density
          if (count >= 3 && count <= 50) score += 40;
          if (linkDensity >= 0.05 && linkDensity <= 0.6) score += 30;
          if (chineseRatio > 0.3) score += 20;
          if (selector.contains('item') || selector.contains('list') || selector.contains('row')) score += 10;
        } else if (mode == 'toc') {
          // TOC links mode: many link tags, high link density, ending in anchor tag
          if (count >= 10) score += 30;
          if (linkDensity >= 0.7) score += 40;
          if (selector.endsWith('a')) score += 20;
          if (selector.contains('chapter') || selector.contains('catalog') || selector.contains('mulu') || selector.contains('dir')) score += 10;
        } else if (mode == 'content') {
          // Content mode: single node, very long text, extremely low link density, high Chinese ratio
          if (count == 1) score += 20;
          if (totalLen > 600) score += 40;
          if (linkDensity < 0.04) score += 30;
          if (chineseRatio > 0.65) score += 10;
        }

        if (score > 0) {
          final existing = candidates[selector];
          if (existing == null || existing.score < score) {
            candidates[selector] = RuleRankCandidate(
              selector: selector,
              score: score,
              nodeCount: count,
              textLength: totalLen,
              linkDensity: linkDensity,
              chineseRatio: chineseRatio,
            );
          }
        }
      }

      if (id.isNotEmpty) {
        addCandidate('#$id');
        addCandidate('#$id a');
        addCandidate('#$id li a');
      }
      if (className.isNotEmpty) {
        for (final cls in className.split(RegExp(r'\s+'))) {
          if (cls.trim().isNotEmpty) {
            addCandidate('.$cls');
            addCandidate('.$cls a');
            addCandidate('.$cls li a');
          }
        }
      }
      if (tag == 'ul' || tag == 'ol' || tag == 'dl') {
        addCandidate('$tag a');
        addCandidate('$tag li a');
        addCandidate('$tag dd a');
      } else if (tag == 'div' || tag == 'article' || tag == 'section') {
        // also add tag name fallback if text is huge
        if (totalLen > 1000) {
          addCandidate(tag);
        }
      }

      for (final child in element.children) {
        scan(child);
      }
    }

    scan(body);

    final sorted = candidates.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return sorted;
  }
}
