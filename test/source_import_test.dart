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

  test('does not treat valid source json as cloudflare page', () async {
    final vm = BookSourceViewModel(BookRepository(null));

    await vm.importFromJson(
      jsonEncode([
        {
          'bookSourceName': 'CF keyword source',
          'bookSourceUrl': 'https://cf.example.com',
          'searchUrl': '/search?q={{key}}',
          'ruleSearch': {
            'bookList': 'data.list',
            'name': 'title',
            'bookUrl': 'url',
            'debug': 'challenge-form /cdn-cgi/challenge-platform',
          },
        },
      ]),
    );

    expect(vm.state.error, isNull);
    expect(vm.state.sources, hasLength(1));
    expect(vm.state.sources.single.bookSourceName, 'CF keyword source');
  });

  test(
    'imports browser text json with nested arrays and cloudflare words',
    () async {
      final vm = BookSourceViewModel(BookRepository(null));

      await vm.importFromJson('''
page header
[
  {
    "bookSourceName": "Nested CF source",
    "bookSourceUrl": "https://nested.example.com",
    "searchUrl": "/search?q={{key}}",
    "exploreUrl": [{"title":"榜单","url":"/rank/{{page}}"}],
    "ruleSearch": {
      "bookList": "data.list",
      "name": "title",
      "bookUrl": "url",
      "debug": "challenge-form /cdn-cgi/challenge-platform"
    }
  }
]
page footer
''');

      expect(vm.state.error, isNull);
      expect(vm.state.sources, hasLength(1));
      expect(vm.state.sources.single.bookSourceName, 'Nested CF source');
    },
  );

  test('imports json extracted from browser page text', () async {
    final vm = BookSourceViewModel(BookRepository(null));
    final payload = jsonEncode([
      {
        'bookSourceName': 'Browser extracted source',
        'bookSourceUrl': 'https://browser.example.com',
        'searchUrl': '/search?q={{key}}',
        'ruleSearch': {'bookList': 'data.list', 'name': 'title'},
      },
    ]);

    await vm.importFromJson('header text\n$payload\nfooter text');

    expect(vm.state.error, isNull);
    expect(vm.state.sources, hasLength(1));
    expect(vm.state.sources.single.bookSourceName, 'Browser extracted source');
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

  test('imports sources from items wrapper', () async {
    final vm = BookSourceViewModel(BookRepository(null));

    await vm.importFromJson(
      jsonEncode({
        'items': [
          {
            'bookSourceName': 'Items wrapped source',
            'bookSourceUrl': 'https://items.example.com',
            'searchUrl': '/search?q={{key}}',
            'ruleSearch': {'bookList': 'data.list', 'name': 'title'},
          },
        ],
      }),
    );

    expect(vm.state.error, isNull);
    expect(vm.state.sources, hasLength(1));
    expect(vm.state.sources.single.bookSourceName, 'Items wrapped source');
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

  test('imports string typed enabled and weight fields', () async {
    final vm = BookSourceViewModel(BookRepository(null));

    await vm.importFromJson(
      jsonEncode([
        {
          'bookSourceName': 'String typed flags',
          'bookSourceUrl': 'https://flags.example.com',
          'enabled': 'false',
          'weight': '88',
          'searchUrl': '/search?q={{key}}',
          'ruleSearch': {'bookList': 'data.list', 'name': 'title'},
        },
      ]),
    );

    expect(vm.state.error, isNull);
    expect(vm.state.sources, hasLength(1));
    expect(vm.state.sources.single.enabled, isFalse);
    expect(vm.state.sources.single.weight, 88);
  });

  test('imports old legado rule fields through migration aliases', () async {
    final vm = BookSourceViewModel(BookRepository(null));

    await vm.importFromJson(
      jsonEncode([
        {
          'bookSourceName': 'Old format source',
          'bookSourceUrl': 'https://old.example.com',
          'ruleSearchUrl':
              'https://old.example.com/search?kw=searchKey&page=searchPage',
          'ruleSearchList': 'class.result@tag.li',
          'ruleSearchName': 'tag.a@text',
          'ruleSearchNoteUrl': 'tag.a@href',
          'ruleChapterUrl': 'class.title@tag.a@href',
          'ruleChapterList': 'class.chapter-list@tag.li',
          'ruleChapterName': 'tag.a@text',
          'ruleContentUrl': 'tag.a@href',
          'ruleBookContent': 'class.content@tag.p@text',
          'ruleBookContentReplace': '#ad#',
          'ruleContentUrlNext': 'text.下一页@href',
          'enable': '1',
          'serialNumber': '7',
        },
      ]),
    );

    expect(vm.state.error, isNull);
    final source = vm.state.sources.single;
    expect(source.searchUrl, contains('{{key}}'));
    expect(source.searchUrl, contains('{{page}}'));
    expect(source.weight, 7);
    expect(jsonDecode(source.ruleSearch!)['bookList'], 'class.result@tag.li');
    expect(jsonDecode(source.ruleSearch!)['bookUrl'], 'tag.a@href');
    expect(
      jsonDecode(source.ruleBookInfo!)['tocUrl'],
      'class.title@tag.a@href',
    );
    expect(jsonDecode(source.ruleToc!)['chapterUrl'], 'tag.a@href');
    expect(
      jsonDecode(source.ruleContent!)['content'],
      'class.content@tag.p@text',
    );
    expect(jsonDecode(source.ruleContent!)['replaceRegex'], '##ad##');
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
