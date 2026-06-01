import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' show parse;
import 'package:read/data/models/book_source.dart';
import 'package:read/data/parsers/legado/legado_request_builder.dart';
import 'package:read/data/parsers/legado/legado_rule_evaluator.dart';

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
        'https://example.com/api/search?key=%E6%96%97%E7%A0%B4%E8%8B%8D%E7%A9%B9&page=3&site=site-a',
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
        '/search/{{page+1}}/{page-1}?raw={{searchKeyRaw}}&key={{searchKey}}',
        keyword: 'abc def',
        page: 2,
        source: source,
      );

      expect(text, '/search/3/1?raw=abc def&key=abc%20def');
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
  });
}
