import 'package:flutter_test/flutter_test.dart';
import 'package:read/data/models/book.dart';
import 'package:read/features/explore/viewmodels/explore_viewmodel.dart';

void main() {
  group('explore search result filters', () {
    final books = [
      Book(
        title: '斗破苍穹',
        author: '天蚕土豆',
        filePath: 'https://wutong.example.com/book/1',
        fileType: 'source',
        tags: const ['source:梧桐中文', 'group:小说'],
      ),
      Book(
        title: '斗罗大陆',
        author: '唐家三少',
        filePath: 'https://biquge.example.com/book/2',
        fileType: 'source',
        tags: const ['source:笔趣阁', 'group:玄幻'],
      ),
    ];

    test('filters by title only', () {
      final filtered = filterExploreSearchResults(
        books,
        '斗破',
        SearchResultFilterScope.title,
      );

      expect(filtered.map((book) => book.title), ['斗破苍穹']);
    });

    test('filters by author only', () {
      final filtered = filterExploreSearchResults(
        books,
        '唐家',
        SearchResultFilterScope.author,
      );

      expect(filtered.map((book) => book.title), ['斗罗大陆']);
    });

    test('filters by source tags and address only', () {
      final bySource = filterExploreSearchResults(
        books,
        '梧桐',
        SearchResultFilterScope.source,
      );
      final byAddress = filterExploreSearchResults(
        books,
        'biquge',
        SearchResultFilterScope.source,
      );
      final notAuthor = filterExploreSearchResults(
        books,
        '天蚕',
        SearchResultFilterScope.source,
      );

      expect(bySource.map((book) => book.title), ['斗破苍穹']);
      expect(byAddress.map((book) => book.title), ['斗罗大陆']);
      expect(notAuthor, isEmpty);
    });
  });
}
