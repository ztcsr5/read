import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;

class RuleSuggestEngine {
  /// 推荐书籍列表 CSS 选择器
  static List<String> suggestBookListRules(String html) {
    final doc = parse(html);
    final candidates = <String, double>{};

    void scan(Element element) {
      final className = element.className.toLowerCase();
      final id = element.id.toLowerCase();
      final tag = element.localName?.toLowerCase() ?? '';

      double score = 0;
      if (className.contains('book-item') || className.contains('novel-item') || className.contains('book-list-item')) score += 10;
      if (className.contains('item') || className.contains('list') || className.contains('result')) score += 5;
      if (className.contains('book') || className.contains('novel')) score += 5;
      if (id.contains('book-item') || id.contains('novel-item')) score += 10;
      if (id.contains('item') || id.contains('list') || id.contains('result')) score += 5;
      if (id.contains('book') || id.contains('novel')) score += 5;

      if (score > 0) {
        if (id.isNotEmpty) {
          candidates['#$id'] = (candidates['#$id'] ?? 0) + score;
        }
        if (className.isNotEmpty) {
          for (final cls in className.split(RegExp(r'\s+'))) {
            if (cls.trim().isNotEmpty) {
              final sel = '.$cls';
              candidates[sel] = (candidates[sel] ?? 0) + score;
            }
          }
        }
      }
      
      for (final child in element.children) {
        scan(child);
      }
    }

    scan(doc.body ?? doc.documentElement!);

    final sorted = candidates.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return sorted.map((e) => e.key).take(5).toList();
  }

  /// 推荐章节目录 CSS 选择器
  static List<String> suggestChapterListRules(String html) {
    final doc = parse(html);
    final candidates = <String, double>{};

    void scan(Element element) {
      final className = element.className.toLowerCase();
      final id = element.id.toLowerCase();
      final tag = element.localName?.toLowerCase() ?? '';

      double score = 0;
      if (tag == 'ul' || tag == 'ol') score += 2;
      if (className.contains('chapter') || className.contains('catalog') || className.contains('volume') || className.contains('directory') || className.contains('mulu')) score += 10;
      if (className.contains('list') || className.contains('dir')) score += 3;
      if (id.contains('chapter') || id.contains('catalog') || id.contains('volume') || id.contains('directory') || id.contains('mulu')) score += 10;
      if (id.contains('list') || id.contains('dir')) score += 3;

      if (score > 0) {
        if (id.isNotEmpty) {
          candidates['#$id a'] = (candidates['#$id a'] ?? 0) + score;
          candidates['#$id li a'] = (candidates['#$id li a'] ?? 0) + score;
        }
        if (className.isNotEmpty) {
          for (final cls in className.split(RegExp(r'\s+'))) {
            if (cls.trim().isNotEmpty) {
              candidates['.$cls a'] = (candidates['.$cls a'] ?? 0) + score;
              candidates['.$cls li a'] = (candidates['.$cls li a'] ?? 0) + score;
            }
          }
        }
        if (tag == 'ul' || tag == 'ol') {
          candidates['$tag a'] = (candidates['$tag a'] ?? 0) + score;
          candidates['$tag li a'] = (candidates['$tag li a'] ?? 0) + score;
        }
      }

      for (final child in element.children) {
        scan(child);
      }
    }

    scan(doc.body ?? doc.documentElement!);

    final sorted = candidates.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return sorted.map((e) => e.key).take(5).toList();
  }

  /// 推荐正文内容 CSS 选择器
  static List<String> suggestContentRules(String html) {
    final doc = parse(html);
    final candidates = <String, double>{};

    void scan(Element element) {
      final className = element.className.toLowerCase();
      final id = element.id.toLowerCase();
      final tag = element.localName?.toLowerCase() ?? '';
      
      if (tag == 'script' || tag == 'style' || tag == 'header' || tag == 'footer' || tag == 'nav') return;

      final ownText = element.text.trim();
      double textLengthScore = ownText.length / 100.0;
      if (textLengthScore > 20) textLengthScore = 20;

      double score = textLengthScore;
      if (className.contains('content') || className.contains('article') || className.contains('read') || className.contains('body') || className.contains('booktxt') || className.contains('txt')) score += 10;
      if (id.contains('content') || id.contains('article') || id.contains('read') || id.contains('body') || id.contains('booktxt') || id.contains('txt')) score += 10;
      if (tag == 'div' || tag == 'article') score += 1;

      if (score > 0 && (id.isNotEmpty || className.isNotEmpty)) {
        if (id.isNotEmpty) {
          candidates['#$id'] = (candidates['#$id'] ?? 0) + score;
        }
        if (className.isNotEmpty) {
          for (final cls in className.split(RegExp(r'\s+'))) {
            if (cls.trim().isNotEmpty) {
              candidates['.$cls'] = (candidates['.$cls'] ?? 0) + score;
            }
          }
        }
      }

      for (final child in element.children) {
        scan(child);
      }
    }

    scan(doc.body ?? doc.documentElement!);

    final sorted = candidates.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return sorted.map((e) => e.key).take(5).toList();
  }
}
