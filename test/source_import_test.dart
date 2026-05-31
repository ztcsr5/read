import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:read/data/repositories/book_repository.dart';
import 'package:read/features/settings/viewmodels/book_source_viewmodel.dart';

void main() {
  test('imports source catalog separately from rss', () async {
    final vm = BookSourceViewModel(BookRepository(null));

    await vm.importFromJson(
      jsonEncode([
        {
          'sourceName': 'Yiove 书源仓库',
          'sourceUrl': 'https://shuyuan.yiove.com',
          'sourceGroup': '书源',
          'sourceComment': '官网：www.yiove.com',
        },
      ]),
      originalUrl: 'https://shuyuan.yiove.com/sub.json',
    );

    expect(vm.state.catalogs, hasLength(1));
    expect(vm.state.rssSources, isEmpty);
    expect(vm.state.sources, isEmpty);
  });

  test('imports legado book source json', () async {
    final vm = BookSourceViewModel(BookRepository(null));

    await vm.importFromJson(
      jsonEncode([
        {
          'bookSourceName': '测试书源',
          'bookSourceUrl': 'https://example.com',
          'searchUrl': '/search?key={{key}}&page={{page}}',
          'ruleSearch': {
            'bookList': 'data.list',
            'name': 'title',
            'bookUrl': 'id',
          },
        },
      ]),
    );

    expect(vm.state.sources, hasLength(1));
    expect(vm.state.catalogs, isEmpty);
    expect(vm.state.rssSources, isEmpty);
  });

  test('imports book source aliases from shared json', () async {
    final vm = BookSourceViewModel(BookRepository(null));

    await vm.importFromJson(
      jsonEncode([
        {
          'sourceName': 'Alias Source',
          'sourceUrl': 'https://alias.example.com',
          'rulesSearch': {
            'bookList': r'$.data.list[*]',
            'name': 'title',
            'bookUrl': '/detail?id={{bookId}}',
          },
          'rulesToc': {
            'chapterList': 'chapters',
            'chapterName': 'name',
            'chapterUrl': 'url',
          },
          'ruleBookContent': {'content': 'data.content'},
        },
      ]),
    );

    expect(vm.state.sources, hasLength(1));
    expect(vm.state.sources.single.bookSourceName, 'Alias Source');
    expect(vm.state.sources.single.ruleSearch, contains('bookList'));
    expect(vm.state.sources.single.ruleContent, contains('data.content'));
  });

  test('imports source json from bytes', () async {
    final vm = BookSourceViewModel(BookRepository(null));

    await vm.importFromBytes(
      utf8.encode(
        jsonEncode([
          {
            'bookSourceName': '本地文件书源',
            'bookSourceUrl': 'https://local.example.com',
            'searchUrl': '/search?q={{key}}',
            'ruleSearch': {
              'bookList': 'data.list',
              'name': 'title',
              'bookUrl': 'url',
            },
          },
        ]),
      ),
      originalUrl: 'local.json',
    );

    expect(vm.state.sources, hasLength(1));
    expect(vm.state.sources.single.bookSourceName, '本地文件书源');
  });

  test(
    'updates duplicate book source by url instead of adding copies',
    () async {
      final vm = BookSourceViewModel(BookRepository(null));

      await vm.importFromJson(
        jsonEncode([
          {
            'bookSourceName': '旧名字',
            'bookSourceUrl': 'https://dup.example.com',
            'searchUrl': '/old?q={{key}}',
            'ruleSearch': {'bookList': 'data.list', 'name': 'title'},
          },
        ]),
      );
      await vm.importFromJson(
        jsonEncode([
          {
            'bookSourceName': '新名字',
            'bookSourceUrl': 'https://dup.example.com',
            'searchUrl': '/new?q={{key}}',
            'ruleSearch': {'bookList': 'data.items', 'name': 'name'},
          },
        ]),
      );

      expect(vm.state.sources, hasLength(1));
      expect(vm.state.sources.single.bookSourceName, '新名字');
      expect(vm.state.sources.single.searchUrl, '/new?q={{key}}');
    },
  );
}
