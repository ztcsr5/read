import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' show parse;
import 'package:fast_gbk/fast_gbk.dart';
import 'package:read/data/models/book.dart';
import 'package:read/data/models/diagnostic_report.dart';
import 'package:read/data/models/book_source.dart';
import 'package:read/data/parsers/legado/legado_js_engine.dart';
import 'package:read/data/parsers/legado/legado_request_builder.dart';
import 'package:read/data/parsers/legado/legado_rule_evaluator.dart';
import 'package:read/data/parsers/legado/legado_session_store.dart';
import 'package:read/data/parsers/legado_parser.dart';
import 'package:read/features/source_diagnostic/services/compatibility_analyzer.dart';
import 'package:read/features/source_diagnostic/services/source_auto_repair_service.dart';

void main() {
  group('LegadoRequestBuilder', () {
    test('builds search url with key page and source variables', () {
      final source = BookSource()
        ..bookSourceName = 'Test'
        ..bookSourceUrl = 'https://example.com/api/'
        ..searchUrl = 'search?key={{key}}&page={{page}}&site={{source.key}}'
        ..customConfig = jsonEncode({'key': 'site-a'});

      final url = LegadoRequestBuilder.buildSearchUrl(source, '斗破苍穹', page: 3);

      expect(
        url,
        'https://example.com/api/search?key=%E6%96%97%E7%A0%B4%E8%8B%8D%E7%A9%B9&page=3&site=https://example.com/api',
      );
    });

    test('uses bookSourceUrl as source key fallback', () {
      final source = BookSource()
        ..bookSourceName = 'Test'
        ..bookSourceUrl = 'https://example.com/api/'
        ..searchUrl = '{{source.key}}/search?key={{key}}';

      final url = LegadoRequestBuilder.buildSearchUrl(source, 'abc');

      expect(url, 'https://example.com/api/search?key=abc');
    });

    test('cleans fragment suffixes from shared source base urls', () {
      expect(
        LegadoRequestBuilder.cleanBaseUrl('https://example.com/api#lcs'),
        'https://example.com/api',
      );
      expect(
        LegadoRequestBuilder.cleanBaseUrl('https://example.com/api##comment'),
        'https://example.com/api',
      );
    });

    test('splits embedded config with whitespace before json object', () {
      final embedded = LegadoRequestBuilder.splitEmbeddedConfig(
        'https://example.com/search, {"headers":{"Referer":"https://example.com"}}',
      );

      expect(embedded.url, 'https://example.com/search');
      expect(embedded.config['headers'], isA<Map>());
    });

    test('keeps imported jsLib in source custom config', () {
      final source = BookSource.fromJson({
        'bookSourceName': 'JS Source',
        'bookSourceUrl': 'https://example.com',
        'jsLib': 'function sign(){return "ok";}',
      });
      final config = jsonDecode(source.customConfig!);

      expect(config['jsLib'], contains('function sign'));
    });

    test('replaces source getKey and java encode helpers', () {
      final source = BookSource()
        ..bookSourceName = 'Test'
        ..bookSourceUrl = 'https://example.com/api/';

      final text = LegadoRequestBuilder.replaceVariables(
        '{{source.getKey()}}/search?q={{java.encodeURIComponent(key)}}',
        keyword: '斗破 苍穹',
        source: source,
      );

      expect(
        text,
        'https://example.com/api/search?q=%E6%96%97%E7%A0%B4%20%E8%8B%8D%E7%A9%B9',
      );
    });

    test('replaces legado angle-bracket page sequences', () {
      final source = BookSource()
        ..bookSourceName = 'Test'
        ..bookSourceUrl = 'https://example.com/api/'
        ..searchUrl = 'search?q={{key}}&page=<1,2,2>';

      expect(
        LegadoRequestBuilder.buildSearchUrl(source, 'abc', page: 1),
        'https://example.com/api/search?q=abc&page=1',
      );
      expect(
        LegadoRequestBuilder.buildSearchUrl(source, 'abc', page: 2),
        'https://example.com/api/search?q=abc&page=2',
      );
      expect(
        LegadoRequestBuilder.buildSearchUrl(source, 'abc', page: 9),
        'https://example.com/api/search?q=abc&page=2',
      );
    });

    test('evaluates inline javascript search url blocks', () {
      if (!LegadoJsEngine().isAvailable) return;
      final source = BookSource()
        ..bookSourceName = 'Test'
        ..bookSourceUrl = 'https://example.com/api/';

      final text = LegadoRequestBuilder.replaceVariables(
        '{{var host=source.getKey(); host + "/search?q=" + java.encodeURIComponent(key) + "&p=" + page}}',
        keyword: '斗破 苍穹',
        page: 2,
        source: source,
      );

      expect(
        text,
        'https://example.com/api/search?q=%E6%96%97%E7%A0%B4%20%E8%8B%8D%E7%A9%B9&p=2',
      );
    });

    test('builds request from embedded config', () {
      final source = BookSource()
        ..bookSourceName = 'Test'
        ..bookSourceUrl = 'https://example.com';

      final request = LegadoRequestBuilder.buildRequest(
        source,
        'https://example.com/search,{"method":"POST","body":"q={{key}}&page={{page}}","headers":{"X-Test":"1"},"charset":"gbk"}',
        keyword: '凡人',
        page: 2,
      );

      expect(request.url, 'https://example.com/search');
      expect(request.method, 'POST');
      expect(request.body, 'q=%E5%87%A1%E4%BA%BA&page=2');
      expect(request.headers?['X-Test'], '1');
      expect(
        request.headers?['Content-Type'],
        'application/x-www-form-urlencoded',
      );
      expect(request.charset, 'gbk');
    });

    test('keeps empty signed headers from embedded config', () {
      final source = BookSource()
        ..bookSourceName = 'Signed'
        ..bookSourceUrl = 'https://api.example.com';

      final request = LegadoRequestBuilder.buildRequest(
        source,
        'https://api.example.com/search,{"headers":{"AUTHORIZATION":"","sign":"abc"}}',
      );

      expect(request.headers?['AUTHORIZATION'], '');
      expect(request.headers?['sign'], 'abc');
    });

    test('builds request headers from source header config', () {
      final source = BookSource.fromJson({
        'bookSourceName': 'Header Test',
        'bookSourceUrl': 'https://example.com',
        'header': 'User-Agent: TestAgent\\nCookie: a=b',
      });

      final request = LegadoRequestBuilder.buildRequest(
        source,
        'https://example.com/search',
      );

      expect(request.headers?['User-Agent'], 'TestAgent');
      expect(request.headers?['Cookie'], 'a=b');
    });

    test('replaces page offsets and raw search variables', () {
      final source = BookSource()
        ..bookSourceName = 'Test'
        ..bookSourceUrl = 'https://example.com';

      final text = LegadoRequestBuilder.replaceVariables(
        '/search/{{page+1}}/{page-1}?raw={{searchKeyRaw}}&key={{searchKey}}&old=searchKey&p=searchPage',
        keyword: 'abc def',
        page: 2,
        source: source,
      );

      expect(text, '/search/3/1?raw=abc def&key=abc%20def&old=abc%20def&p=2');
    });

    test('replaces legacy search tokens inside embedded json configs', () {
      final source = BookSource()
        ..bookSourceName = 'Test'
        ..bookSourceUrl = 'https://example.com'
        ..searchUrl =
            'https://example.com/search,{"method":"POST","body":{"title":"searchKey","pageNum":{{searchPage}},"pageNext":"searchPage+1"}}';

      final url = LegadoRequestBuilder.buildSearchUrl(
        source,
        'abc def',
        page: 2,
      );
      final request = LegadoRequestBuilder.buildRequest(
        source,
        url,
        keyword: 'abc def',
        page: 2,
      );

      expect(request.body, contains('"title":"abc%20def"'));
      expect(request.body, contains('"pageNum":2'));
      expect(request.body, contains('"pageNext":"3"'));
    });

    test('replaces placeholders even when shared url encoded braces', () {
      final source = BookSource()
        ..bookSourceName = 'Test'
        ..bookSourceUrl = 'https://example.com';

      final text = LegadoRequestBuilder.replaceVariables(
        '/search?page=%7B%7Bpage%7D%7D&keyword=%7B%7Bkey%7D%7D',
        keyword: '斗破苍穹',
        page: 4,
        source: source,
      );

      expect(
        text,
        '/search?page=4&keyword=%E6%96%97%E7%A0%B4%E8%8B%8D%E7%A9%B9',
      );
    });

    test('guards javascript header strings before Dio sees them', () {
      final headers = LegadoRequestBuilder.parseHeaderString(
        '<js>var headers = {"User-Agent":"MobileUA"}; return JSON.stringify(headers)</js>',
      );

      expect(headers['User-Agent'], 'MobileUA');
      expect(headers.keys, everyElement(matches(RegExp(r'^[^\s=]+$'))));
    });

    test('extracts loose var header objects without unsafe names', () {
      final headers = LegadoRequestBuilder.parseHeaderString(
        'var heders = {"User-Agent":"MobileUA","Referer":"https://example.com"}',
      );

      expect(headers['User-Agent'], 'MobileUA');
      expect(headers['Referer'], 'https://example.com');
    });

    test('filters invalid header names and keeps valid loose headers', () {
      final headers = LegadoRequestBuilder.parseHeaderString(
        'Bad Header = nope: value\nX-Test: ok\nCookie: a=b',
      );

      expect(headers.containsKey('Bad Header = nope'), isFalse);
      expect(headers['X-Test'], 'ok');
      expect(headers['Cookie'], 'a=b');
    });

    test('splits embedded config even when a JS tail follows it', () {
      final embedded = LegadoRequestBuilder.splitEmbeddedConfig(
        'https://example.com/search,{"method":"POST","body":{"q":"{{key}}"}}'
        ',null,if (key.length > 0) { return "ignored"; }',
      );

      expect(embedded.url, 'https://example.com/search');
      expect(embedded.config['method'], 'POST');
      expect(embedded.config['body'], isA<Map>());
    });

    test('encodes map bodies from embedded configs as json', () {
      final source = BookSource()
        ..bookSourceName = 'Test'
        ..bookSourceUrl = 'https://example.com';

      final request = LegadoRequestBuilder.buildRequest(
        source,
        'https://example.com/post,{"method":"POST","body":{"q":"{{keyRaw}}","page":"{{page}}"}}',
        keyword: 'abc def',
        page: 7,
      );

      expect(request.method, 'POST');
      expect(jsonDecode(request.body!), {'q': 'abc def', 'page': '7'});
      expect(request.headers?['Content-Type'], 'application/json');
    });

    test('interpolates single-brace json path templates', () {
      final value = LegadoRuleEvaluator.extractJsonValue({
        'wapBookId': 229093,
      }, r'http://sma.yueyouxs.com/b/{$.wapBookId}.html');

      expect(value, 'http://sma.yueyouxs.com/b/229093.html');
    });

    test('keeps source scoped variables inside json templates', () {
      final source = BookSource()
        ..bookSourceName = 'Test'
        ..bookSourceUrl = 'https://example.com/api';

      final text = LegadoRequestBuilder.replaceVariables(
        '{{source.bookSourceUrl}}/detail/{{bookId}}',
        keyword: '',
        source: source,
      );

      expect(text, 'https://example.com/api/detail/{{bookId}}');
    });
  });

  group('LegadoRuleEvaluator', () {
    test('extracts json values with normalized json path', () {
      final data = {
        'data': {
          'list': [
            {'title': '第一本'},
          ],
        },
      };

      expect(
        LegadoRuleEvaluator.extractJsonValue(data, 'data.list[0].title'),
        '第一本',
      );
    });

    test('expands json list nodes when rule points to an array', () {
      final data = {
        'data': {
          'list': [
            {'title': '第一本'},
            {'title': '第二本'},
          ],
        },
      };

      final nodes = LegadoRuleEvaluator.extractJsonNodes(data, 'data.list');

      expect(nodes, hasLength(2));
      expect((nodes.first as Map)['title'], '第一本');
      expect((nodes.last as Map)['title'], '第二本');
    });

    test('expands json list nodes with wildcard syntax', () {
      final data = {
        'data': {
          'list': [
            {'title': 'A'},
            {'title': 'B'},
          ],
        },
      };

      final nodes = LegadoRuleEvaluator.extractJsonNodes(
        data,
        r'$.data.list[*]',
      );

      expect(nodes, hasLength(2));
      expect((nodes.last as Map)['title'], 'B');
    });

    test('expands json list nodes with simple filter predicates', () {
      final data = {
        'data': {
          'list': [
            {'title': 'A', 'hasContent': 1, 'source': 'free'},
            {'title': 'B', 'hasContent': 0, 'source': 'vip'},
            {'title': 'C', 'hasContent': true, 'source': 'free'},
          ],
        },
      };

      final truthy = LegadoRuleEvaluator.extractJsonNodes(
        data,
        r'$.data.list[?(@.hasContent)]',
      );
      final equals = LegadoRuleEvaluator.extractJsonNodes(
        data,
        r'$.data.list[?(@.hasContent==1)]',
      );
      final notEquals = LegadoRuleEvaluator.extractJsonNodes(
        data,
        r'$.data.list[?(@.source!="vip")]',
      );

      expect(truthy.map((node) => (node as Map)['title']), ['A', 'C']);
      expect(equals.map((node) => (node as Map)['title']), ['A']);
      expect(notEquals.map((node) => (node as Map)['title']), ['A', 'C']);
    });

    test('expands json list nodes through recursive descent', () {
      final data = {
        'payload': {
          'nested': {
            'bookList': [
              {'name': 'A'},
              {'name': 'B'},
            ],
          },
        },
      };

      final nodes = LegadoRuleEvaluator.extractJsonNodes(
        data,
        r'$..bookList[*]',
      );

      expect(nodes, hasLength(2));
      expect((nodes.first as Map)['name'], 'A');
    });

    test('interpolates json template values', () {
      final item = {'bookId': 42, 'title': '第一本'};

      expect(
        LegadoRuleEvaluator.extractJsonValue(
          item,
          '/reading/bookapi/detail/v1?book_id={{bookId}}',
        ),
        '/reading/bookapi/detail/v1?book_id=42',
      );
    });

    test('uses common JSON id aliases in templates', () {
      final item = {'id': 152, 'title': '斗破苍穹'};

      expect(
        LegadoRuleEvaluator.extractJsonValue(
          item,
          r'/novel/{{$.novelId}}/chapters',
        ),
        '/novel/152/chapters',
      );
    });

    test('interpolates @json literal URL templates', () {
      final item = {
        'id': 7,
        'photoPath': '/cover.jpg',
        'chapter_nid': 'n1',
        'chapter_vid': 'v2',
      };

      expect(
        LegadoRuleEvaluator.extractJsonValue(
          item,
          r'@json:https://api.example.com/book?id={$.id}',
        ),
        'https://api.example.com/book?id=7',
      );
      expect(
        LegadoRuleEvaluator.extractJsonValue(
          item,
          r'@JSon:https://cdn.example.com/book{$.photoPath}',
        ),
        'https://cdn.example.com/book/cover.jpg',
      );
      expect(
        LegadoRuleEvaluator.extractJsonValue(
          item,
          r'@json:https://api.example.com/read?nid={{$.chapter_nid}}&vid={{$.chapter_vid}}',
        ),
        'https://api.example.com/read?nid=n1&vid=v2',
      );
    });

    test('keeps @json json path extraction case-insensitive', () {
      final item = {'name': 'Book A'};

      expect(
        LegadoRuleEvaluator.extractJsonValue(item, r'@JSon:$.name'),
        'Book A',
      );
    });

    test('extracts html values with css selector and attributes', () {
      final document = parse('''
        <div class="book">
          <a href="/book/1">九星镇天诀</a>
        </div>
      ''');
      final node = document.querySelector('.book')!;

      expect(LegadoRuleEvaluator.extractHtmlValue(node, 'a@text'), '九星镇天诀');
      expect(LegadoRuleEvaluator.extractHtmlValue(node, 'a@href'), '/book/1');
    });

    test('extracts html alternatives and html attributes', () {
      final document = parse('''
        <div class="book">
          <a href="/book/1"><span>Book A</span></a>
          <p>Line<br>Two</p>
        </div>
      ''');
      final node = document.querySelector('.book')!;

      expect(
        LegadoRuleEvaluator.extractHtmlValue(node, '.missing@text||a@text'),
        'Book A',
      );
      expect(
        LegadoRuleEvaluator.extractHtmlValue(node, 'p@html'),
        contains('<br>'),
      );
    });

    test('does not split fallback operators inside selector arguments', () {
      final document = parse('''
        <div class="book">
          <p>A||B</p>
          <span>Fallback</span>
        </div>
      ''');

      expect(
        LegadoRuleEvaluator.extractHtmlValue(
          document.body!,
          'p:containsOwn(A||B)@text||span@text',
        ),
        'A||B',
      );
      expect(
        LegadoRuleEvaluator.queryAll(
          document,
          'p:containsOwn(A||B)||span',
        ).map((node) => node.localName).toList(),
        ['p'],
      );
    });

    test('interleaves html values and nodes for %% rules', () {
      final document = parse('''
        <div class="toc">
          <a class="free" href="/1">第一章</a>
          <a class="free" href="/3">第三章</a>
          <a class="vip" href="/2">第二章</a>
          <a class="vip" href="/4">第四章</a>
        </div>
      ''');

      expect(
        LegadoRuleEvaluator.extractHtmlValue(
          document.body!,
          '.free@text%%.vip@text',
        ),
        '第一章\n第二章\n第三章\n第四章',
      );

      final nodes = LegadoRuleEvaluator.queryAll(document, '.free%%.vip');
      expect(nodes.map((node) => node.text).toList(), [
        '第一章',
        '第二章',
        '第三章',
        '第四章',
      ]);
    });

    test('supports legado ownText all and attr function attributes', () {
      final document = parse('''
        <div class="card" data-id="42">
          Own <span>Child</span>
          <script>ignored()</script>
        </div>
      ''');
      final node = document.querySelector('.card')!;

      expect(LegadoRuleEvaluator.extractHtmlValue(node, 'ownText'), 'Own');
      expect(
        LegadoRuleEvaluator.extractHtmlValue(node, 'all'),
        contains('data-id="42"'),
      );
      expect(LegadoRuleEvaluator.extractHtmlValue(node, 'attr(data-id)'), '42');
    });

    test('supports legado bracket indexes on html selectors', () {
      final document = parse('''
        <ul>
          <li>A</li>
          <li>B</li>
          <li>C</li>
          <li>D</li>
        </ul>
      ''');

      expect(
        LegadoRuleEvaluator.queryAll(
          document,
          'li[-1]',
        ).map((node) => node.text).toList(),
        ['D'],
      );
      expect(
        LegadoRuleEvaluator.queryAll(
          document,
          'li[1,3]',
        ).map((node) => node.text).toList(),
        ['B', 'D'],
      );
      expect(
        LegadoRuleEvaluator.queryAll(
          document,
          'li[-1:0]',
        ).map((node) => node.text).toList(),
        ['D', 'C', 'B', 'A'],
      );
      expect(
        LegadoRuleEvaluator.queryAll(
          document,
          'li[!1:2]',
        ).map((node) => node.text).toList(),
        ['A', 'D'],
      );
      expect(
        LegadoRuleEvaluator.extractHtmlValue(document.body!, 'li[1,3]@text'),
        'B\nD',
      );
    });

    test('supports jquery eq lt gt pseudo indexes on html selectors', () {
      final document = parse('''
        <table>
          <tr><td>R0C0</td><td>R0C1</td></tr>
          <tr><td>R1C0</td><td>R1C1</td></tr>
          <tr><td>R2C0</td><td>R2C1</td></tr>
        </table>
      ''');

      expect(
        LegadoRuleEvaluator.queryAll(
          document,
          'tr:eq(1)',
        ).map((node) => node.text.trim()).toList(),
        ['R1C0R1C1'],
      );
      expect(
        LegadoRuleEvaluator.queryAll(
          document,
          'tr:lt(2)',
        ).map((node) => node.text.trim()).toList(),
        ['R0C0R0C1', 'R1C0R1C1'],
      );
      expect(
        LegadoRuleEvaluator.queryAll(
          document,
          'tr:gt(0)',
        ).map((node) => node.text.trim()).toList(),
        ['R1C0R1C1', 'R2C0R2C1'],
      );
      expect(
        LegadoRuleEvaluator.queryAll(
          document,
          'tr:nth-child(n+2)',
        ).map((node) => node.text.trim()).toList(),
        ['R1C0R1C1', 'R2C0R2C1'],
      );
      expect(
        LegadoRuleEvaluator.queryAll(
          document,
          'td:nth-child(2n+1)',
        ).map((node) => node.text.trim()).toList(),
        ['R0C0', 'R1C0', 'R2C0'],
      );
      expect(
        LegadoRuleEvaluator.extractHtmlValue(
          document.body!,
          'tr:eq(1)>td:eq(0)@text',
        ),
        'R1C0',
      );
    });

    test('supports match arrow regex post processors', () {
      final document = parse('''
        <div class="author">作者：Alice</div>
        <ul class="info">
          <li>状态：连载</li>
          <li>最后更新时间：2026-01-02</li>
        </ul>
      ''');

      expect(
        LegadoRuleEvaluator.extractHtmlValue(
          document.body!,
          'div.author@match->(?<=作者：)(.+)',
        ),
        'Alice',
      );
      expect(
        LegadoRuleEvaluator.extractHtmlValue(
          document.body!,
          'ul.info > li:nth-child(2)@match->(?<=最后更新时间：)(.+)',
        ),
        '2026-01-02',
      );
    });

    test('supports legado text shorthand selector', () {
      final document = parse('''
        <div class="links">
          <a href="/catalog">查看目录</a>
          <a href="/upper">CATALOG</a>
          <a href="/about">关于</a>
        </div>
      ''');

      expect(
        LegadoRuleEvaluator.extractHtmlValue(document.body!, 'text.目录@href'),
        '/catalog',
      );
      expect(
        LegadoRuleEvaluator.queryAll(
          document,
          'text.目录',
        ).map((node) => node.attributes['href']).toList(),
        ['/catalog'],
      );
      expect(
        LegadoRuleEvaluator.extractHtmlValue(
          document.body!,
          'text.catalog@href',
        ),
        '/upper',
      );
    });

    test('joins multiple xpath values and interleaves xpath lists', () {
      final document = parse('''
        <div id="content">
          <p>Line A</p>
          <p>Line B</p>
        </div>
        <div class="toc">
          <a href="/1">Chapter 1</a>
          <a href="/2">Chapter 2</a>
        </div>
      ''');

      expect(
        LegadoRuleEvaluator.extractHtmlValue(
          document.body!,
          '//div[@id="content"]/p/text()',
        ),
        'Line A\nLine B',
      );
      expect(
        LegadoRuleEvaluator.extractHtmlValue(
          document.body!,
          '//div[@class="toc"]/a/@href%%//div[@class="toc"]/a/text()',
        ),
        '/1\nChapter 1\n/2\nChapter 2',
      );
    });

    test('extracts chained html selectors and indexed selectors', () {
      final document = parse('''
        <div id="chaptercontent">
          <p>广告</p>
          <p>正文一</p>
          <p>正文二</p>
          <p>尾页</p>
        </div>
        <div class="book"><a href="/book/1">书名</a></div>
      ''');

      expect(
        LegadoRuleEvaluator.extractHtmlValue(
          document.body!,
          'id.chaptercontent@p!1:-1@text',
        ),
        '正文一\n正文二',
      );
      expect(
        LegadoRuleEvaluator.extractHtmlValue(
          document.querySelector('.book')!,
          'a.0@href',
        ),
        '/book/1',
      );
      expect(
        LegadoRuleEvaluator.extractHtmlValue(
          document.querySelector('.book')!,
          'tag.a.0@href',
        ),
        '/book/1',
      );
      expect(
        LegadoRuleEvaluator.queryOne(document, 'class.book@html')?.text.trim(),
        '书名',
      );
    });

    test('keeps selector suffix after js preprocessor block', () {
      expect(
        LegadoRuleEvaluator.stripPostProcessors(
          '<js>result = result.replace("a","b")</js>\n.item@text',
        ),
        '.item@text',
      );
      expect(
        LegadoRuleEvaluator.extractJsonValue({
          'chapterId': 123,
        }, r'chapterId@put:{chapterId:$.chapterId}'),
        '123',
      );
    });

    test('supports legado inline put and get variables in json rules', () {
      final item = {'name': '斗破苍穹', 'id': 42, 'chapter': 7};
      expect(
        LegadoRuleEvaluator.extractJsonValue(item, r'$.name@put:{bid:$.id}'),
        '斗破苍穹',
      );
      expect(
        LegadoRuleEvaluator.extractJsonValue(
          item,
          r'https://example.com/book/@get:{bid}/{{$.chapter}}.html',
        ),
        'https://example.com/book/42/7.html',
      );
    });

    test('supports legado inline put and get variables in html rules', () {
      final document = parse('''
        <html><head>
          <meta property="book_name" content="斗破苍穹">
        </head><body>
          <a href="/toc">章节目录</a>
        </body></html>
      ''');
      final root = document.documentElement!;
      expect(
        LegadoRuleEvaluator.queryOne(
          document,
          r'@put:{n:"meta[property~=book_name]@content",u:"@@text.章节目录@href"}',
        ),
        isNotNull,
      );
      expect(LegadoRuleEvaluator.extractHtmlValue(root, r'@get:{n}'), '斗破苍穹');
      expect(LegadoRuleEvaluator.extractHtmlValue(root, r'@get:{u}'), '/toc');
    });

    test('sanitizes non-standard Legado CSS selectors', () {
      expect(
        LegadoRuleEvaluator.sanitizeCssSelector('.info li.0 a'),
        '.info li.0 a',
      );
      expect(LegadoRuleEvaluator.sanitizeCssSelector('div:eq(0) a'), 'div.0 a');
      expect(
        LegadoRuleEvaluator.sanitizeCssSelector('div:eq(-1) a'),
        'div.-1 a',
      );
      expect(
        LegadoRuleEvaluator.sanitizeCssSelector('.info .0 a'),
        '.info *.0 a',
      );
    });

    test('supports JSoup-like element self-matching', () {
      final document = parse('<a href="/test">link</a>');
      final node = document.querySelector('a')!;
      // Even if selector is "a" and the element is "a", it matches itself
      expect(LegadoRuleEvaluator.extractHtmlValue(node, 'a@href'), '/test');
    });

    test('supports JSoup-like attribute fallback to descendants', () {
      final document = parse('''
        <li class="item">
          <a href="/target">link</a>
          <img src="/image.png" alt="cover"/>
        </li>
      ''');
      final node = document.querySelector('.item')!;
      // li has no href directly, falls back to sub-a's href
      expect(LegadoRuleEvaluator.extractHtmlValue(node, 'href'), '/target');
      // li has no src directly, falls back to sub-img's src
      expect(LegadoRuleEvaluator.extractHtmlValue(node, 'src'), '/image.png');
    });

    test('applies json path javascript post processors for book urls', () {
      final item = {'id': 155711, 'iconUrlSmall': '/book/155711.jpg@!bns?1'};

      expect(
        LegadoRuleEvaluator.extractJsonValue(
          item,
          r'$.id@js:"https://www.ruochu.com/book/"+result',
        ),
        'https://www.ruochu.com/book/155711',
      );
      expect(
        LegadoRuleEvaluator.extractJsonValue(
          item,
          r'$.iconUrlSmall@js:"https://b.heiyanimg.com"+result',
        ),
        'https://b.heiyanimg.com/book/155711.jpg@!bns?1',
      );
    });

    test('keeps multiline js post processors intact for chapter names', () {
      final document = parse('''
        <li><a href="/book/1">Chapter One</a></li>
      ''');
      final node = document.querySelector('li')!;

      expect(
        LegadoRuleEvaluator.extractHtmlValue(
          node,
          r'''html@js:if(result.match(/isvip/)){
result=""+result.match(/>([^<]+)<\/a>/)[1];
}else{result=result.match(/>([^<]+)<\/a>/)[1];}''',
        ),
        'Chapter One',
      );
    });

    test('supports legado class shorthand with descendant selector', () {
      final document = parse('''
        <ul class="float-list fill-block">
          <li><a href="/book/1">Chapter One</a></li>
          <li><a href="/book/2">Chapter Two</a></li>
        </ul>
      ''');

      final nodes = LegadoRuleEvaluator.queryAll(
        document,
        'class.float-list fill-block@li',
      );

      expect(nodes, hasLength(2));
      expect(
        LegadoRuleEvaluator.extractHtmlValue(nodes.first, 'a@href'),
        '/book/1',
      );
    });
  });

  group('LegadoJsEngine', () {
    test('supports java.getString json path and CryptoJS MD5', () {
      final engine = LegadoJsEngine();
      if (!engine.isAvailable) return;
      final value = engine.evaluate(
        'java.getString("\$.data.title") + "|" + CryptoJS.MD5("abc").toString()',
        variables: {
          'result': jsonEncode({
            'data': {'title': '斗破苍穹'},
          }),
        },
      );

      expect(value, '斗破苍穹|900150983cd24fb0d6963f7d28e17f72');
    });

    test('resolves ajax calls through Dart callback', () async {
      if (!LegadoJsEngine().isAvailable) return;
      final value = await LegadoJsEngine().evaluateWithAjax(
        '<js>var data = JSON.parse(java.ajax("https://example.com/books")); data.list;</js>',
        ajax: (_) async => jsonEncode({
          'list': [
            {'title': 'A'},
          ],
        }),
      );

      expect(jsonDecode(value), isA<List>());
      expect((jsonDecode(value) as List).first['title'], 'A');
    });

    test('wraps top-level java.ajax snippets as async iife', () {
      final code = JsCompatibilityTransformer.transform(
        'var data = JSON.parse(java.ajax("https://example.com/books")); data.list;',
      );

      expect(code.trimLeft(), startsWith('(async function()'));
      expect(code, contains('await java.ajax'));
      expect(code, contains('return (data.list)'));
    });

    test('upgrades function java.ajax snippets to async functions', () {
      final code = JsCompatibilityTransformer.transform(
        '(function(){ return java.ajax("https://example.com/books"); })()',
      );

      expect(code, contains('async function'));
      expect(code, contains('await java.ajax'));
    });
  });

  group('LegadoSessionStore', () {
    test('applies stored cookies and user agent to headers', () {
      final uri = Uri.parse('https://example.com/books');
      LegadoSessionStore.setCookieString(uri, 'sid=1; Path=/; HttpOnly');
      LegadoSessionStore.setUserAgent(uri, 'AgentA');

      final headers = <String, dynamic>{'Cookie': 'a=b'};
      LegadoSessionStore.apply(uri, headers);

      expect(headers['Cookie'], contains('a=b'));
      expect(headers['Cookie'], contains('sid=1'));
      expect(headers['User-Agent'], 'AgentA');
    });
  });

  group('LegadoParser Robustness', () {
    test(
      'keeps original book url when book info rule repeats last segment',
      () async {
        final source = BookSource()
          ..bookSourceName = 'Biquge-like'
          ..bookSourceUrl = 'https://www.biquge8.xyz'
          ..ruleBookInfo = jsonEncode({
            'name': 'h1@text',
            'tocUrl': 'a.catalog@href',
          });
        final book = Book(
          title: '万相之王',
          author: '天蚕土豆',
          filePath: 'https://www.biquge8.xyz/50045',
          fileType: 'online',
          isFromSource: true,
        );
        final response = Response<dynamic>(
          data:
              '<html><body><h1>万相之王</h1><a class="catalog" href="50045">目录</a></body></html>',
          statusCode: 200,
          requestOptions: RequestOptions(path: book.filePath),
        );

        final parsed = await LegadoParser.parseBookInfo(
          source,
          book,
          preFetchedResponse: response,
        );

        expect(parsed.filePath, 'https://www.biquge8.xyz/50045');
      },
    );

    test('repairs TOC alias fields and preserves editable source json', () {
      final source = BookSource()
        ..bookSourceName = 'Alias Source'
        ..bookSourceUrl = 'https://example.com'
        ..ruleToc = jsonEncode({
          'chapterListTOC': '.chapter_list li a',
          'chapterNameTOC': '@text',
          'chapterUrlTOC': '@href',
        });

      final result = SourceAutoRepairService.repairWithReport(source);
      final toc = jsonDecode(result.source.ruleToc!) as Map<String, dynamic>;

      expect(toc['chapterList'], '.chapter_list li a');
      expect(toc['chapterName'], '@text');
      expect(toc['chapterUrl'], '@href');
      expect(result.changes.join('\n'), contains('chapterListTOC'));

      final exported = result.source.toJson();
      final imported = BookSource.fromJson(exported);
      expect(imported.bookSourceName, source.bookSourceName);
      expect(imported.ruleToc, result.source.ruleToc);
    });

    test('auto repair fills html defaults and normalizes legacy aliases', () {
      final source = BookSource()
        ..bookSourceName = 'Repair Source'
        ..bookSourceUrl = 'https://example.com'
        ..ruleSearch = jsonEncode({
          'list': '.result-item',
          'title': 'h3@text',
          'url': 'h3 a@href',
        })
        ..ruleToc = jsonEncode({'chapterListTOC': 'class.chapter-list item'});

      final result = SourceAutoRepairService.repairWithReport(source);
      final search = jsonDecode(result.source.ruleSearch!) as Map;
      final toc = jsonDecode(result.source.ruleToc!) as Map;

      expect(search['bookList'], '.result-item');
      expect(search['name'], 'h3@text');
      expect(search['bookUrl'], 'h3 a@href');
      expect(toc['chapterList'], 'class.chapter-list.item');
      expect(toc['chapterName'], '@text');
      expect(toc['chapterUrl'], '@href');
    });

    test('auto repair applies diagnostic selector candidates', () {
      final source = BookSource()
        ..bookSourceName = 'Candidate Source'
        ..bookSourceUrl = 'https://example.com'
        ..ruleSearch = jsonEncode({
          'bookList': '.old',
          'name': 'a@text',
          'bookUrl': 'a@href',
        });
      final report = DiagnosticReport(
        searchSuccess: false,
        bookInfoSuccess: true,
        tocSuccess: true,
        contentSuccess: true,
        score: 70,
        riskLevel: 'medium',
        issues: [
          DiagnosticIssue(
            stage: 'search',
            field: 'bookList',
            reason: 'old selector failed',
            suggestion: 'replace ".old" with ".book-item"',
          ),
        ],
      );

      final result = SourceAutoRepairService.repairWithReport(
        source,
        report: report,
      );
      final search = jsonDecode(result.source.ruleSearch!) as Map;

      expect(search['bookList'], '.book-item');
      expect(result.changes.join('\n'), contains('bookList=.book-item'));
    });

    test(
      'auto repair applies Chinese candidate lists by stage and rule field',
      () {
        final source = BookSource()
          ..bookSourceName = 'Chinese Candidate Source'
          ..bookSourceUrl = 'https://example.com'
          ..ruleToc = jsonEncode({
            'chapterList': '.old-toc a',
            'chapterName': '@text',
            'chapterUrl': '@href',
          });
        final report = DiagnosticReport(
          searchSuccess: true,
          bookInfoSuccess: true,
          tocSuccess: false,
          contentSuccess: true,
          score: 70,
          riskLevel: 'medium',
          issues: [
            DiagnosticIssue(
              stage: 'toc',
              field: 'ruleToc',
              reason: '目录解析失败：推荐候补 CSS 规则',
              suggestion: '检测到可能替代的目录选择器：.chapter-list li a，#catalog a',
            ),
          ],
        );

        final result = SourceAutoRepairService.repairWithReport(
          source,
          report: report,
        );
        final toc = jsonDecode(result.source.ruleToc!) as Map;

        expect(toc['chapterList'], '.chapter-list li a');
        expect(
          result.changes.join('\n'),
          contains('chapterList=.chapter-list li a'),
        );
      },
    );

    test(
      'auto repair prefers new redesign selector over old quoted selector',
      () {
        final source = BookSource()
          ..bookSourceName = 'Redesign Candidate Source'
          ..bookSourceUrl = 'https://example.com'
          ..ruleSearch = jsonEncode({
            'bookList': '.old',
            'name': 'a@text',
            'bookUrl': 'a@href',
          });
        final report = DiagnosticReport(
          searchSuccess: false,
          bookInfoSuccess: false,
          tocSuccess: false,
          contentSuccess: false,
          score: 0,
          riskLevel: 'high',
          issues: [
            DiagnosticIssue(
              stage: 'search',
              field: 'bookList',
              rule: '.old',
              reason: '检测到网站结构可能改版',
              suggestion: '检测到高权重备选规则！建议将旧选择器 ".old" 自动替换为 ".novel-item"',
              htmlSnippet: '旧规则: .old\n新规则候选: .novel-item (得分: 89)',
            ),
          ],
        );

        final result = SourceAutoRepairService.repairWithReport(
          source,
          report: report,
        );
        final search = jsonDecode(result.source.ruleSearch!) as Map;

        expect(search['bookList'], '.novel-item');
      },
    );

    test(
      'falls back to chapter-like html anchors when toc selector misses',
      () async {
        final source = BookSource()
          ..bookSourceName = 'Fallback Source'
          ..bookSourceUrl = 'https://example.com'
          ..ruleToc = jsonEncode({
            'chapterList': '.missing-list a',
            'chapterName': '@text',
            'chapterUrl': '@href',
          });
        final book = Book(
          title: 'Book',
          filePath: 'https://example.com/book/1',
          fileType: 'online',
          isFromSource: true,
        );
        final response = Response<dynamic>(
          data: '''
          <html><body>
            <div class="chapter-list">
              <a href="/book/1/1.html">第一章 开始</a>
              <a href="/book/1/2.html">第二章 继续</a>
            </div>
          </body></html>
        ''',
          statusCode: 200,
          requestOptions: RequestOptions(path: book.filePath),
        );

        final chapters = await LegadoParser.getChapterList(
          source,
          book,
          preFetchedResponse: response,
        );

        expect(chapters, hasLength(2));
        expect(chapters.first.title, contains('第一章'));
        expect(chapters.first.url, 'https://example.com/book/1/1.html');
      },
    );

    test(
      'cleans URLs of trailing control characters and percent-encoded controls',
      () {
        final baseUrl = 'https://example.com/api/\n\r%0A%0D';
        final relativeUrl = 'search\n\r%0a%0d';
        final resolved = LegadoRequestBuilder.resolveUrl(baseUrl, relativeUrl);
        expect(resolved, 'https://example.com/api/search');

        final embedded = LegadoRequestBuilder.splitEmbeddedConfig(
          'https://example.com/books\n\r%0A%0D,{"method":"POST"}',
        );
        expect(embedded.url, 'https://example.com/books');
        expect(embedded.config['method'], 'POST');
      },
    );

    test('auto-detects and decodes GBK encoding from headers or meta tags', () {
      final utf8Text = '测试中文编码';
      final gbkBytes = gbk.encode(utf8Text);

      // 1. Detect from Headers
      final decodedFromHeaders = LegadoParser.decodeBytes(
        gbkBytes,
        null,
        headers: {
          'Content-Type': ['text/html; charset=gbk'],
        },
      );
      expect(decodedFromHeaders, utf8Text);

      // 2. Detect from HTML Meta Tag
      final htmlPrefix = utf8.encode(
        '<html><head><meta charset="gbk"></head><body>',
      );
      final combinedBytes = [...htmlPrefix, ...gbkBytes];
      final decodedFromMeta = LegadoParser.decodeBytes(combinedBytes, null);
      expect(decodedFromMeta, contains(utf8Text));
    });

    test('detects spaced GB family charsets and broken utf8 fallback', () {
      final text = '斗破苍穹 第一章 测试中文';
      final bytes = gbk.encode(text);

      expect(
        LegadoParser.decodeBytes(
          bytes,
          null,
          headers: {
            'content-type': ['text/html; charset = "gb2312"'],
          },
        ),
        text,
      );
      expect(LegadoParser.decodeBytes(bytes, 'gb18030'), text);
      expect(LegadoParser.decodeBytes(bytes, null), text);
    });

    test('evaluates raw @js searchUrl before URL resolution', () async {
      if (!LegadoJsEngine().isAvailable) return;
      final source = BookSource()
        ..bookSourceName = 'Signed'
        ..bookSourceUrl = 'https://api.example.com'
        ..searchUrl =
            '@js:var u=source.getKey()+"/search?keyword="+java.encodeURIComponent(key); u+","+java.put("headers",JSON.stringify({"headers":{"X-Test":"1"}}))';

      final url = await LegadoParser.buildSearchUrl(source, '斗破苍穹');

      expect(url, startsWith('https://api.example.com/search?keyword='));
      expect(url, isNot(contains('/@js:')));
      expect(url, contains('"X-Test":"1"'));
    });

    test('evaluates mixed searchUrl js blocks before URL resolution', () async {
      if (!LegadoJsEngine().isAvailable) return;
      final source = BookSource()
        ..bookSourceName = 'Mixed JS'
        ..bookSourceUrl = 'https://example.com/api/'
        ..searchUrl =
            'search/<js>result + "?q=" + java.encodeURIComponent(key)</js>';

      final url = await LegadoParser.buildSearchUrl(source, '斗破 苍穹');

      expect(
        url,
        'https://example.com/api/search/?q=%E6%96%97%E7%A0%B4%20%E8%8B%8D%E7%A9%B9',
      );
    });

    test('keeps embedded post config returned by raw @js searchUrl', () async {
      if (!LegadoJsEngine().isAvailable) return;
      final source = BookSource()
        ..bookSourceName = 'Post'
        ..bookSourceUrl = 'https://m.example.com'
        ..searchUrl =
            '@js:var body="q="+java.encodeURIComponent(key); source.getKey()+"/api/search,"+JSON.stringify({"method":"POST","body":body,"charset":"gbk"})';

      final url = await LegadoParser.buildSearchUrl(source, '斗破苍穹');

      expect(url, startsWith('https://m.example.com/api/search,'));
      expect(url, contains('"method":"POST"'));
      expect(url, contains('"charset":"gbk"'));
      expect(url, isNot(contains('/@js:')));
    });

    test('wraps raw js search url scripts so the last expression returns', () {
      final prepared = LegadoJsEngine().prepareForTesting('''
@js:
sign_key='secret'
headers={'AUTHORIZATION':''}
body='q='+java.encodeURIComponent(key)
"/api/search?" + body + "," + java.put("headers",JSON.stringify({"headers":headers}))
''');

      expect(prepared, contains('return ("/api/search?" + body'));
      expect(prepared, contains('java.put("headers"'));
    });

    test('wraps raw js search url scripts with nested function returns', () {
      final prepared = LegadoJsEngine().prepareForTesting(r'''
@js:
sign_key='secret'
headers={'AUTHORIZATION':''}
params={'page':page,'wd':key}
var urlEncode = function (param, key, encode) {
  if(param==null) return '';
  var paramStr = '';
  for (var i in param) {
    paramStr += '&' + i + '=' + encodeURIComponent(param[i]);
  }
  return paramStr;
};
body=urlEncode(params)
"/api/v5/search/words?" + body + "," + java.put("headers",JSON.stringify({"headers":headers}))
''');

      expect(prepared, contains('return ("/api/v5/search/words?" + body'));
      expect(prepared, contains("if(param==null) return ''"));
    });

    test('falls back for signed raw js search url templates', () async {
      final source = BookSource()
        ..bookSourceName = 'Signed fallback'
        ..bookSourceUrl = 'https://api.example.com'
        ..searchUrl = r'''
@js:
sign_key='secret'
headers={'app-version':'51110','platform':'android','AUTHORIZATION':''}
params={'gender':'3','page':page,'wd':key}
var urlEncode = function (param, key, encode) {
  if(param==null) return '';
  var paramStr = '';
  for (var i in param) {
    paramStr += '&' + i + '=' + encodeURIComponent(param[i]);
  }
  return paramStr;
};
headerSign=String(java.md5Encode(Object.keys(headers).sort().reduce((pre,n)=>pre+n+'='+headers[n],'')+sign_key))
paramSign=String(java.md5Encode(Object.keys(params).sort().reduce((pre,n)=>pre+n+'='+params[n],'')+sign_key))
headers['sign']=headerSign
params['sign']=paramSign
body=urlEncode(params)
"/api/v5/search/words?" +body+","+java.put("headers",JSON.stringify({"headers":headers}))
''';

      final url = await LegadoParser.buildSearchUrl(source, '斗破苍穹');

      expect(url, startsWith('https://api.example.com/api/v5/search/words?'));
      expect(url, contains('wd=%E6%96%97%E7%A0%B4%E8%8B%8D%E7%A9%B9'));
      expect(url, contains('"app-version":"51110"'));
      expect(url, contains('"sign"'));
      expect(url, isNot(contains('/@js:')));
    });

    test('wraps result mutation javascript post processors', () {
      final prepared = LegadoJsEngine().prepareForTesting(
        r'''@js:if(result.match(/isvip/)){result="🔒"+result.match(/>([^<]+)<\/a>/)[1];}else{result=result.match(/>([^<]+)<\/a>/)[1];}''',
      );

      expect(prepared, contains('return (typeof result === "undefined"'));
      expect(prepared, contains('result.match(/>([^<]+)<\\/a>/)[1]'));
    });

    test('applies json value javascript post processor to book URLs', () {
      final value = LegadoRuleEvaluator.extractJsonValue({
        'id': 155711,
      }, r'$.id@js:"https://www.ruochu.com/book/"+result');

      expect(value, 'https://www.ruochu.com/book/155711');
    });

    test('applies json value javascript post processor to cover URLs', () {
      final value = LegadoRuleEvaluator.extractJsonValue({
        'iconUrlSmall': '/book/155711.jpg@!bns?1',
      }, r'$.iconUrlSmall@js:"https://b.heiyanimg.com"+result');

      expect(value, 'https://b.heiyanimg.com/book/155711.jpg@!bns?1');
    });

    test(
      'applies simple javascript replace post processors without runtime',
      () {
        final value = LegadoRuleEvaluator.applyPostProcessors(
          '第1章 广告 正文 广告',
          r'@js:result.replace(/广告/g,"")',
        );

        expect(value, '第1章  正文');
      },
    );

    test('expands capture groups in replaceRegex post processors', () {
      final value = LegadoRuleEvaluator.applyPostProcessors(
        'cover http://img.example.com/a.webp done',
        r'##(http.*webp)##<img src="$1">',
      );

      expect(value, 'cover <img src="http://img.example.com/a.webp"> done');
    });

    test('uses legado first-match replaceRegex semantics', () {
      final value = LegadoRuleEvaluator.applyPostProcessors(
        'noise callback({"ok":true}) tail',
        r'##callback\((.*)\)##$1###',
      );

      expect(value, '{"ok":true}');
    });

    test('keeps text for t2s and s2t javascript post processors', () {
      expect(
        LegadoRuleEvaluator.applyPostProcessors('繁體', r'@js:java.t2s(result)'),
        '繁體',
      );
      expect(
        LegadoRuleEvaluator.applyPostProcessors('简体', r'@js:java.s2t(result)'),
        '简体',
      );
    });

    test('extracts chapter names from html result mutation js rules', () {
      final node = parse(
        '<li><a href="/book/1.html">第一章 龙潜苍穹</a></li>',
      ).querySelector('li')!;

      final title = LegadoRuleEvaluator.extractHtmlValue(
        node,
        r'''html@js:if(result.match(/isvip/)){result="🔒"+result.match(/>([^<]+)<\/a>/)[1];}else{result=result.match(/>([^<]+)<\/a>/)[1];}''',
      );

      expect(title, '第一章 龙潜苍穹');
    });

    test('treats html tag tokens after @ as selector steps', () {
      final document = parse('''
<html><body>
  <ul class="float-list fill-block">
    <li><a href="/book/1.html">Chapter One</a></li>
    <li><a href="/book/2.html">Chapter Two</a></li>
  </ul>
</body></html>
''');

      final nodes = LegadoRuleEvaluator.queryAll(
        document,
        'class.float-list fill-block@li',
      );

      expect(nodes, hasLength(2));
      expect(
        LegadoRuleEvaluator.extractHtmlValue(nodes.first, 'a@text'),
        'Chapter One',
      );
      expect(
        LegadoRuleEvaluator.extractHtmlValue(nodes.first, 'a@href'),
        '/book/1.html',
      );
    });

    test(
      'keeps response data when leading js block only defines rule vars',
      () async {
        if (!LegadoJsEngine().isAvailable) return;
        final source = BookSource()
          ..bookSourceName = 'Comment Rule'
          ..bookSourceUrl = 'https://example.com'
          ..customConfig = jsonEncode({
            'bookSourceComment': 'var p = { sone: ".book" };',
          })
          ..ruleSearch = jsonEncode({
            'bookList':
                '<js>eval(String(source.bookSourceComment))</js>\np.sone',
            'name': 'a@text',
            'bookUrl': 'a@href',
          });
        final response = Response(
          data:
              '<html><body><div class="book"><a href="/b/1">斗破苍穹</a></div></body></html>',
          requestOptions: RequestOptions(path: 'https://example.com/search'),
          statusCode: 200,
        );

        final books = await LegadoParser.searchBooks(
          source,
          '斗破',
          preFetchedResponse: response,
        );

        expect(books, hasLength(1));
        expect(books.first.title, '斗破苍穹');
        expect(books.first.filePath, 'https://example.com/b/1');
      },
    );

    test('applies embedded url js and bodyJs request options', () async {
      if (!LegadoJsEngine().isAvailable) return;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requestedPaths = <String>[];
      server.listen((request) async {
        requestedPaths.add(request.uri.path);
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/search') {
          request.response.write(
            jsonEncode({
              'books': [
                {'name': 'raw title', 'url': '/book/1'},
              ],
            }),
          );
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write('{}');
        }
        await request.response.close();
      });

      final base = 'http://${server.address.host}:${server.port}';
      final source = BookSource()
        ..bookSourceName = 'URL Option Source'
        ..bookSourceUrl = base
        ..searchUrl =
            '$base/placeholder,${jsonEncode({'js': '@js:result.replace("placeholder", "search")', 'bodyJs': '@js:result.replace("raw title", "斗破苍穹")'})}'
        ..ruleSearch = jsonEncode({
          'bookList': r'$.books',
          'name': r'$.name',
          'bookUrl': r'$.url',
        });

      final books = await LegadoParser.searchBooks(source, '斗破苍穹');

      expect(requestedPaths, contains('/search'));
      expect(requestedPaths, isNot(contains('/placeholder')));
      expect(books, hasLength(1));
      expect(books.first.title, '斗破苍穹');
      expect(books.first.filePath, '$base/book/1');
    });

    test('keeps toc rows with same fallback url but different titles', () async {
      final source = BookSource()
        ..bookSourceName = 'No Chapter Url Source'
        ..bookSourceUrl = 'https://example.com'
        ..ruleToc = jsonEncode({
          'chapterList': '.toc a',
          'chapterName': '@text',
          'chapterUrl': '@href',
        });
      final book = Book(
        title: '目录测试',
        author: '',
        filePath: 'https://example.com/toc',
        fileType: 'online',
        isFromSource: true,
      );
      final response = Response<dynamic>(
        data:
            '<html><body><div class="toc"><a>第一章</a><a>第二章</a><a>第三章</a></div></body></html>',
        requestOptions: RequestOptions(path: book.filePath),
        statusCode: 200,
      );

      final chapters = await LegadoParser.getChapterList(
        source,
        book,
        preFetchedResponse: response,
      );

      expect(chapters.map((chapter) => chapter.title), ['第一章', '第二章', '第三章']);
      expect(chapters.map((chapter) => chapter.url).toSet(), {
        'https://example.com/toc',
      });
    });

    test('loads all toc pages when nextTocUrl returns multiple urls', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.headers.contentType = ContentType.html;
        switch (request.uri.path) {
          case '/toc':
            request.response.write('''
              <div class="toc"><a href="/c1">Chapter 1</a></div>
              <div class="pages">
                <a href="/toc2">2</a>
                <a href="/toc3">3</a>
              </div>
            ''');
            break;
          case '/toc2':
            request.response.write(
              '<div class="toc"><a href="/c2">Chapter 2</a></div>',
            );
            break;
          case '/toc3':
            request.response.write(
              '<div class="toc"><a href="/c3">Chapter 3</a></div>',
            );
            break;
          default:
            request.response.statusCode = HttpStatus.notFound;
            request.response.write('');
        }
        await request.response.close();
      });

      final base = 'http://${server.address.host}:${server.port}';
      final source = BookSource()
        ..bookSourceName = 'Paged Toc Source'
        ..bookSourceUrl = base
        ..ruleToc = jsonEncode({
          'chapterList': '.toc a',
          'chapterName': '@text',
          'chapterUrl': '@href',
          'nextTocUrl': '.pages a@href',
        });
      final book = Book(
        title: 'Paged Toc',
        author: '',
        filePath: '$base/toc',
        fileType: 'online',
        isFromSource: true,
      );

      final chapters = await LegadoParser.getChapterList(source, book);

      expect(chapters.map((chapter) => chapter.title), [
        'Chapter 1',
        'Chapter 2',
        'Chapter 3',
      ]);
      expect(chapters.map((chapter) => chapter.url), [
        '$base/c1',
        '$base/c2',
        '$base/c3',
      ]);
    });

    test('loads toc from legacy json path without json prefix', () async {
      final source = BookSource()
        ..bookSourceName = 'Legacy Json Toc Source'
        ..bookSourceUrl = 'https://example.com'
        ..ruleToc = jsonEncode({
          'chapterList': 'data[*].directory[*]',
          'chapterName': 'title',
          'chapterUrl': r'/read?page={{$.page}}&books_id=123',
        });
      final book = Book(
        title: 'Json Toc',
        author: '',
        filePath: 'https://example.com/api/toc',
        fileType: 'online',
        isFromSource: true,
      );
      final response = Response<dynamic>(
        data: jsonEncode({
          'data': [
            {
              'directory': [
                {'title': 'C1', 'page': 1},
                {'title': 'C2', 'page': 2},
              ],
            },
            {
              'directory': [
                {'title': 'C3', 'page': 3},
              ],
            },
          ],
        }),
        requestOptions: RequestOptions(path: book.filePath),
        statusCode: 200,
      );

      final chapters = await LegadoParser.getChapterList(
        source,
        book,
        preFetchedResponse: response,
      );

      expect(chapters.map((chapter) => chapter.title), ['C1', 'C2', 'C3']);
      expect(chapters.map((chapter) => chapter.url), [
        'https://example.com/read?page=1&books_id=123',
        'https://example.com/read?page=2&books_id=123',
        'https://example.com/read?page=3&books_id=123',
      ]);
    });

    test('flattens all nested chapter lists in json toc fallback', () async {
      final source = BookSource()
        ..bookSourceName = 'Nested Json Toc Source'
        ..bookSourceUrl = 'https://example.com'
        ..ruleToc = jsonEncode({});
      final book = Book(
        title: 'Nested Toc',
        author: '',
        filePath: 'https://example.com/api/toc',
        fileType: 'online',
        isFromSource: true,
      );
      final response = Response<dynamic>(
        data: jsonEncode({
          'data': {
            'volumeList': [
              {
                'volumeName': 'V1',
                'chapters': [
                  {'chapterName': 'C1', 'url': '/c1'},
                  {'chapterName': 'C2', 'url': '/c2'},
                ],
              },
              {
                'volumeName': 'V2',
                'chapters': [
                  {'Text': 'C3', 'Href': '/c3'},
                ],
              },
            ],
          },
        }),
        requestOptions: RequestOptions(path: book.filePath),
        statusCode: 200,
      );

      final chapters = await LegadoParser.getChapterList(
        source,
        book,
        preFetchedResponse: response,
      );

      expect(chapters.map((chapter) => chapter.title), ['C1', 'C2', 'C3']);
      expect(chapters.map((chapter) => chapter.url), [
        'https://example.com/c1',
        'https://example.com/c2',
        'https://example.com/c3',
      ]);
    });

    test(
      'loads all content pages when nextContentUrl returns multiple urls',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final requestedPaths = <String>[];
        server.listen((request) async {
          requestedPaths.add(request.uri.path);
          request.response.headers.contentType = ContentType.html;
          switch (request.uri.path) {
            case '/c1':
              request.response.write('''
              <div id="content"><p>Part 1</p></div>
              <div class="pages">
                <a href="/c1p2">2</a>
                <a href="/c1p3">3</a>
              </div>
            ''');
              break;
            case '/c1p2':
              request.response.write('<div id="content"><p>Part 2</p></div>');
              break;
            case '/c1p3':
              request.response.write('<div id="content"><p>Part 3</p></div>');
              break;
            default:
              request.response.statusCode = HttpStatus.notFound;
              request.response.write('');
          }
          await request.response.close();
        });

        final base = 'http://${server.address.host}:${server.port}';
        final source = BookSource()
          ..bookSourceName = 'Paged Content Source'
          ..bookSourceUrl = base
          ..ruleContent = jsonEncode({
            'content': '#content@html',
            'nextContentUrl': '.pages a@href',
          });

        final content = await LegadoParser.getChapterContent(
          source,
          '$base/c1',
        );

        expect(content, contains('Part 1'));
        expect(content, contains('Part 2'));
        expect(content, contains('Part 3'));
        expect(requestedPaths, ['/c1', '/c1p2', '/c1p3']);
      },
    );

    test('extracts all matching content text nodes', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.headers.contentType = ContentType.html;
        request.response.write('''
          <div id="content">
            <p>Para 1</p>
            <p>Para 2</p>
            <p>Para 3</p>
          </div>
        ''');
        await request.response.close();
      });

      final base = 'http://${server.address.host}:${server.port}';
      final source = BookSource()
        ..bookSourceName = 'Multi Paragraph Content Source'
        ..bookSourceUrl = base
        ..ruleContent = jsonEncode({'content': '#content p@textNodes'});

      final content = await LegadoParser.getChapterContent(source, '$base/c1');

      expect(content, contains('Para 1'));
      expect(content, contains('Para 2'));
      expect(content, contains('Para 3'));
    });

    test('applies ajax javascript post processor for content', () async {
      if (!LegadoJsEngine().isAvailable) return;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.headers.contentType = ContentType.html;
        if (request.uri.path == '/ajax') {
          request.response.write('<p>Ajax Body</p>');
        } else {
          request.response.write('<div id="seed">/ajax</div>');
        }
        await request.response.close();
      });

      final base = 'http://${server.address.host}:${server.port}';
      final source = BookSource()
        ..bookSourceName = 'Ajax Content Source'
        ..bookSourceUrl = base
        ..ruleContent = jsonEncode({
          'content': '#seed@text<js>java.ajax(result)</js>',
        });

      final content = await LegadoParser.getChapterContent(source, '$base/c1');

      expect(content, contains('Ajax Body'));
    });

    test('supports ESO style crypto helper aliases', () {
      if (!LegadoJsEngine().isAvailable) return;
      expect(
        LegadoJsEngine().evaluate('@js:esoTools.md5Encode("abc")'),
        '900150983cd24fb0d6963f7d28e17f72',
      );
      expect(
        LegadoJsEngine().evaluate(
          '@js:esoTools.base64Decode(esoTools.base64Encode("abc"))',
        ),
        'abc',
      );
    });

    test('supports java.getElements bridge for html result rules', () {
      if (!LegadoJsEngine().isAvailable) return;
      final html = '<div id="content"><p>第一段</p><p data-id="2">第二段</p></div>';

      final text = LegadoJsEngine().evaluate(
        '@js:java.getElements("#content p").text()',
        variables: {'result': html},
      );
      final returnedHtml = LegadoJsEngine().evaluate(
        '@js:return java.getElements("#content p")',
        variables: {'result': html},
      );
      final attr = LegadoJsEngine().evaluate(
        '@js:java.getElement("#content p[data-id]").attr("data-id")',
        variables: {'result': html},
      );
      final indexedAttr = LegadoJsEngine().evaluate(
        '@js:java.getElements("#content p")[1].attr("data-id")',
        variables: {'result': html},
      );

      expect(text, '第一段\n第二段');
      expect(returnedHtml, contains('<p>第一段</p>'));
      expect(returnedHtml, contains('data-id="2"'));
      expect(attr, '2');
      expect(indexedAttr, '2');
    });

    test('supports java.getString and getStringList for html rules', () {
      if (!LegadoJsEngine().isAvailable) return;
      final html =
          '<div id="content"><p>第一段</p><p data-id="2"><a href="/c2">第二段</a></p></div>';

      final text = LegadoJsEngine().evaluate(
        '@js:java.getString("#content p[data-id]@text")',
        variables: {'result': html},
      );
      final href = LegadoJsEngine().evaluate(
        '@js:java.getString("#content p[data-id] a@href")',
        variables: {'result': html},
      );
      final attr = LegadoJsEngine().evaluate(
        '@js:java.getString("#content p[data-id]@attr(data-id)")',
        variables: {'result': html},
      );
      final list = LegadoJsEngine().evaluate(
        '@js:JSON.stringify(java.getStringList("#content p@text"))',
        variables: {'result': html},
      );

      expect(text, '第二段');
      expect(href, '/c2');
      expect(attr, '2');
      expect(jsonDecode(list), ['第一段', '第二段']);
    });

    test('supports @@ legacy html rules in java bridge helpers', () {
      if (!LegadoJsEngine().isAvailable) return;
      final html =
          '<div class="zlb"><li><a href="/a">A</a></li><li><a href="/b">B</a></li></div>';

      final text = LegadoJsEngine().evaluate(
        '@js:java.getElements("@@class.zlb@tag.li@tag.a").text()',
        variables: {'result': html},
      );
      final href = LegadoJsEngine().evaluate(
        '@js:java.getString("@@class.zlb@tag.li@tag.a@href")',
        variables: {'result': html},
      );

      expect(text, 'A\nB');
      expect(href, '/a');
    });

    test('supports getStringList toArray and setContent in js bridge', () {
      if (!LegadoJsEngine().isAvailable) return;
      final html = '''
<div class="volume"><h2>V1</h2><a href="/1">C1</a><a href="/2">C2</a></div>
<div class="volume"><h2>V2</h2><a href="/3">C3</a></div>
''';

      final value = LegadoJsEngine().evaluate(
        r'''@js:
var out = [];
java.getElements(".volume").toArray().forEach(function(vol) {
  java.setContent(vol);
  out.push(java.getString("h2@text") + ":" + java.getStringList("a@href").toArray().join(","));
});
out.join("|");
''',
        variables: {'result': html},
      );

      expect(value, 'V1:/1,/2|V2:/3');
    });

    test('supports cookie bridge backed by session store', () {
      if (!LegadoJsEngine().isAvailable) return;
      final uri = Uri.parse('https://cookie.example/path');
      LegadoSessionStore.clearHost(uri);
      addTearDown(() => LegadoSessionStore.clearHost(uri));

      final sid = LegadoJsEngine().evaluate(
        '@js:cookie.setCookie("https://cookie.example/path", "sid=abc; Path=/"); cookie.getKey("https://cookie.example/path", "sid")',
      );

      expect(sid, 'abc');
      expect(LegadoSessionStore.cookieHeaderFor(uri), contains('sid=abc'));
    });

    test('supports legacy class selector with multiple class tokens', () {
      final document = parse('''
        <ul class="float-list fill-block">
          <li><a href="/1">第一章</a></li>
          <li><a href="/2">第二章</a></li>
        </ul>
      ''');

      final nodes = LegadoRuleEvaluator.queryAll(
        document,
        'class.float-list fill-block@tag.li',
      );

      expect(nodes, hasLength(2));
      expect(LegadoRuleEvaluator.extractHtmlValue(nodes.last, 'a@text'), '第二章');
    });

    test('does not throw on loose Legado attribute selectors', () {
      final document = parse('''
        <ul>
          <li property="last_test_chapter_name">最新章节</li>
          <li property="other">其他</li>
        </ul>
      ''');

      expect(
        () => LegadoRuleEvaluator.extractHtmlValue(
          document.body!,
          'li[property~=las?test_chapter_name]@text',
        ),
        returnsNormally,
      );
    });

    test(
      'testSource fails early when searchUrl JS builds an empty URL',
      () async {
        final source = BookSource()
          ..bookSourceName = 'Bad JS Search'
          ..bookSourceUrl = 'https://example.com'
          ..searchUrl = '@js:throw new Error("boom")'
          ..ruleSearch = jsonEncode({'bookList': '.book'});

        final report = await LegadoParser.testSource(source, '斗破苍穹');

        expect(report.hasFailure, isTrue);
        expect(report.steps.first.title, '搜索 URL');
        expect(report.steps.first.status, LegadoStepStatus.fail);
        expect(report.steps.first.message, contains('构建结果为空'));
      },
    );
  });

  group('CompatibilityAnalyzer', () {
    test('detects advanced Legado compatibility risks', () {
      final source = BookSource()
        ..bookSourceName = 'Advanced'
        ..bookSourceUrl = 'https://example.com'
        ..searchUrl =
            '<js>var data = java.ajax("https://example.com/search"); data</js>'
        ..ruleSearch = jsonEncode({
          'bookList': 'Jsoup.parse(result).select(".book")',
          'name': '@get:{title}',
          'bookUrl': '@put:{url:\$.url}',
        })
        ..customConfig = jsonEncode({
          'charset': 'gb2312',
          'header': 'cf_clearance=1',
        });

      final reasons = CompatibilityAnalyzer.analyze(
        source,
      ).map((issue) => issue.reason).join('\n');

      expect(reasons, contains('JavaScript'));
      expect(reasons, contains('java.ajax'));
      expect(reasons, contains('Jsoup'));
      expect(reasons, contains('GBK'));
      expect(reasons, contains('@get'));
      expect(reasons, contains('@put'));
      expect(reasons, contains('验证'));
    });

    test('does not flag URLs and CSS JSON as XPath risks', () {
      final source = BookSource()
        ..bookSourceName = 'Css'
        ..bookSourceUrl = 'https://example.com'
        ..searchUrl = '/api/search?keyword={{key}}'
        ..ruleSearch = jsonEncode({
          'bookList': 'ul.flex li',
          'name': 'h2@text',
          'bookUrl': 'a[href^="/"]@href',
        });

      final reasons = CompatibilityAnalyzer.analyze(
        source,
      ).map((issue) => issue.reason).join('\n');

      expect(reasons, isNot(contains('XPath')));
    });
  });
}
