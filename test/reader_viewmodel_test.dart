import 'package:flutter_test/flutter_test.dart';
import 'package:read/features/reader/viewmodels/reader_viewmodel.dart';

void main() {
  group('readerChapterContentToPlainText', () {
    test('keeps html block boundaries as reader paragraphs', () {
      final text = readerChapterContentToPlainText(
        '<div>First&nbsp;line</div><p>Second<br/>Third&#x21;</p>'
        '<script>ignored()</script>',
      );

      expect(
        text.split('\n').map((line) => line.trim()).where((line) {
          return line.isNotEmpty;
        }).toList(),
        ['First line', 'Second', 'Third!'],
      );
    });

    test('decodes common html entities after stripping tags', () {
      final text = readerChapterContentToPlainText(
        '<p>&ldquo;A&amp;B&rdquo; &mdash; &#65;&#x42;</p>',
      ).trim();

      expect(text, '\u201cA&B\u201d \u2014 AB');
    });
  });

  group('readerNeedsOnlineContentRefresh', () {
    test('refreshes url placeholders and suspicious cached text', () {
      expect(
        readerNeedsOnlineContentRefresh(
          cachedContent: 'https://example.com/c1.html',
          chapterUrl: 'https://example.com/c1.html',
        ),
        isTrue,
      );
      expect(
        readerNeedsOnlineContentRefresh(
          cachedContent: '解析失败',
          chapterUrl: 'https://example.com/c1.html',
        ),
        isTrue,
      );
    });

    test(
      'refreshes short legacy caches but keeps downloaded short chapters',
      () {
        expect(
          readerNeedsOnlineContentRefresh(
            cachedContent: '短章正文',
            chapterUrl: 'https://example.com/c1.html',
          ),
          isTrue,
        );
        expect(
          readerNeedsOnlineContentRefresh(
            cachedContent: '短章正文',
            chapterUrl: 'https://example.com/c1.html',
            isDownloaded: true,
            wordCount: 4,
          ),
          isFalse,
        );
      },
    );

    test('does not refresh local chapters or normal cached text', () {
      expect(
        readerNeedsOnlineContentRefresh(
          cachedContent: '短章正文',
          chapterUrl: null,
        ),
        isFalse,
      );
      expect(
        readerNeedsOnlineContentRefresh(
          cachedContent: List.filled(20, '这是一段已经缓存下来的完整正文。').join(),
          chapterUrl: 'https://example.com/c1.html',
        ),
        isFalse,
      );
    });
  });
}
