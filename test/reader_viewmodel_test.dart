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
}
