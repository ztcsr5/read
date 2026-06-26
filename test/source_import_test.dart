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
          'sourceName': 'Yiove catalog',
          'sourceUrl': 'https://shuyuan.yiove.com',
          'sourceGroup': 'Book sources',
          'sourceComment': 'Official site',
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
          'bookSourceName': 'Test source',
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
    "exploreUrl": [{"title":"Rank","url":"/rank/{{page}}"}],
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
            'bookSourceName': 'Local file source',
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
    expect(vm.state.sources.single.bookSourceName, 'Local file source');
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
          'ruleContentUrlNext': 'text.next@href',
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
            'bookSourceName': 'Duplicate old',
            'bookSourceUrl': 'https://dup.example.com',
            'searchUrl': '/old?q={{key}}',
            'ruleSearch': {'bookList': 'data.list', 'name': 'title'},
          },
        ]),
      );
      await vm.importFromJson(
        jsonEncode([
          {
            'bookSourceName': 'Duplicate new',
            'bookSourceUrl': 'https://dup.example.com',
            'searchUrl': '/new?q={{key}}',
            'ruleSearch': {'bookList': 'data.items', 'name': 'name'},
          },
        ]),
      );

      expect(vm.state.sources, hasLength(1));
      expect(vm.state.sources.single.bookSourceName, 'Duplicate new');
      expect(vm.state.sources.single.searchUrl, '/new?q={{key}}');
    },
  );

  test('imports sourceUrls recursively and deduplicates by url', () async {
    final responses = {
      'https://example.com/a.json': jsonEncode([
        {
          'bookSourceName': 'A old',
          'bookSourceUrl': 'https://a.example',
          'searchUrl': '/old?q={{key}}',
          'ruleSearch': {'bookList': 'data.list', 'name': 'title'},
        },
      ]),
      'https://example.com/b.json': jsonEncode({
        'bookSourceName': 'A new',
        'bookSourceUrl': 'https://a.example',
        'searchUrl': '/new?q={{key}}',
        'ruleSearch': {'bookList': 'data.items', 'name': 'name'},
      }),
    };

    final vm = BookSourceViewModel(
      BookRepository(null),
      fetchText: (url, {bool withoutUserAgent = false}) async =>
          responses[url]!,
    );

    await vm.importFromJson(
      jsonEncode({
        'sourceUrls': [
          'https://example.com/a.json',
          'https://example.com/b.json',
        ],
      }),
    );

    expect(vm.state.error, isNull);
    expect(vm.state.sources, hasLength(1));
    expect(vm.state.sources.single.bookSourceName, 'A new');
    expect(vm.state.sources.single.searchUrl, '/new?q={{key}}');
  });

  test('passes requestWithoutUA flag while importing sourceUrls', () async {
    var requestedWithoutUa = false;

    final vm = BookSourceViewModel(
      BookRepository(null),
      fetchText: (url, {bool withoutUserAgent = false}) async {
        requestedWithoutUa = withoutUserAgent;
        return jsonEncode({
          'bookSourceName': 'No UA',
          'bookSourceUrl': 'https://noua.example',
          'searchUrl': '/s?q={{key}}',
          'ruleSearch': {'bookList': 'data.list', 'name': 'title'},
        });
      },
    );

    await vm.importFromJson(
      jsonEncode({
        'sourceUrls': ['https://example.com/no-ua.json#requestWithoutUA'],
      }),
    );

    expect(vm.state.error, isNull);
    expect(requestedWithoutUa, isTrue);
    expect(vm.state.sources.single.bookSourceName, 'No UA');
  });

  test('imports js function source', () async {
    final vm = BookSourceViewModel(BookRepository(null));

    await vm.importFromJs(r'''
// @name JS Test Source
// @url https://js.example
// @group JS Group
// @searchUrl /search?q={{key}}&page={{page}}
function search(key, page, result) {
  return [{name: "A", bookUrl: "/a"}];
}
function toc(result) {
  return [{name: "Chapter 1", url: "/1"}];
}
function content(result) {
  return ["Body"];
}
''');

    expect(vm.state.error, isNull);
    expect(vm.state.sources, hasLength(1));
    final source = vm.state.sources.single;
    expect(source.bookSourceName, 'JS Test Source');
    expect(source.bookSourceUrl, 'https://js.example');
    expect(source.searchUrl, '/search?q={{key}}&page={{page}}');
    expect(
      jsonDecode(source.ruleSearch!)['bookList'],
      '<js>search(key, page, result)</js>',
    );
    expect(jsonDecode(source.ruleToc!)['chapterList'], '<js>toc(result)</js>');
    expect(
      jsonDecode(source.ruleContent!)['content'],
      '<js>content(result)</js>',
    );
    final config = jsonDecode(source.customConfig!) as Map;
    expect(config['engine'], 'quickjs');
    expect(config['sourceFormat'], 'js');
    expect(config['jsLib'], contains('function search'));
  });

  test('imports modern js function source declarations', () async {
    final vm = BookSourceViewModel(BookRepository(null));

    await vm.importFromJs(r'''
// @name Modern JS Source
// @url https://modern-js.example
// @searchUrl /search?q={{key}}
async function search(key, page, result) {
  return [{name: "A", bookUrl: "/a"}];
}
const explore = (baseUrl, result) => [{name: "B", bookUrl: "/b"}];
let bookInfo = function(result) {
  return {name: "Book", tocUrl: "/toc"};
};
const toc = async (result) => [{name: "C1", url: "/1"}];
var content = function(result) {
  return "Body";
};
const nextContentUrl = () => "";
''');

    expect(vm.state.error, isNull);
    expect(vm.state.sources, hasLength(1));
    final source = vm.state.sources.single;
    expect(source.bookSourceName, 'Modern JS Source');
    expect(jsonDecode(source.ruleSearch!)['bookList'], contains('search('));
    expect(jsonDecode(source.ruleExplore!)['bookList'], contains('explore('));
    expect(jsonDecode(source.ruleBookInfo!)['init'], contains('bookInfo('));
    expect(jsonDecode(source.ruleToc!)['chapterList'], contains('toc('));
    expect(jsonDecode(source.ruleContent!)['content'], contains('content('));
    expect(
      jsonDecode(source.ruleContent!)['nextContentUrl'],
      contains('nextContentUrl('),
    );
  });
}
