import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' show parse;
import 'package:fast_gbk/fast_gbk.dart';
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
          '/novel/{{$.novelId}}/chapters',
        ),
        '/novel/152/chapters',
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
