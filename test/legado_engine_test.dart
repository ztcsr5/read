import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' show parse;
import 'package:fast_gbk/fast_gbk.dart';
import 'package:read/data/models/book.dart';
import 'package:read/data/models/chapter.dart';
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
  group('LegadoJsEngine cipher padding', () {
    final engine = LegadoJsEngine();
    final key16 = Uint8List.fromList(utf8.encode('0123456789abcdef'));
    final iv16 = Uint8List.fromList(utf8.encode('abcdef0123456789'));

    Uint8List trimZeros(Uint8List bytes) {
      var end = bytes.length;
      while (end > 0 && bytes[end - 1] == 0) {
        end--;
      }
      return Uint8List.sublistView(bytes, 0, end);
    }

    test('AES/CBC/NoPadding round trips aligned blocks', () {
      final input = Uint8List.fromList(utf8.encode('1234567890ABCDEF'));
      final encrypted = engine.cipherProcessBytesForTesting(
        input: input,
        keyBytes: key16,
        ivBytes: iv16,
        transformation: 'AES/CBC/NoPadding',
        encrypting: true,
      );
      final decrypted = engine.cipherProcessBytesForTesting(
        input: encrypted,
        keyBytes: key16,
        ivBytes: iv16,
        transformation: 'AES/CBC/NoPadding',
        encrypting: false,
      );
      expect(decrypted, input);
    });

    test('AES/CBC/NoPadding rejects unaligned input', () {
      final input = Uint8List.fromList(utf8.encode('not-aligned'));
      expect(
        () => engine.cipherProcessBytesForTesting(
          input: input,
          keyBytes: key16,
          ivBytes: iv16,
          transformation: 'AES/CBC/NoPadding',
          encrypting: true,
        ),
        throwsArgumentError,
      );
    });

    test('AES/CBC/ZeroPadding pads and decrypts to zero-tailed plaintext', () {
      final input = Uint8List.fromList(utf8.encode('hello'));
      final encrypted = engine.cipherProcessBytesForTesting(
        input: input,
        keyBytes: key16,
        ivBytes: iv16,
        transformation: 'AES/CBC/ZeroPadding',
        encrypting: true,
      );
      expect(encrypted.length % 16, 0);
      final decrypted = engine.cipherProcessBytesForTesting(
        input: encrypted,
        keyBytes: key16,
        ivBytes: iv16,
        transformation: 'AES/CBC/ZeroPadding',
        encrypting: false,
      );
      expect(trimZeros(decrypted), input);
    });

    test('DES/ECB/NoPadding round trips aligned blocks', () {
      final key8 = Uint8List.fromList(utf8.encode('8bytekey'));
      final input = Uint8List.fromList(utf8.encode('12345678'));
      final encrypted = engine.cipherProcessBytesForTesting(
        input: input,
        keyBytes: key8,
        ivBytes: Uint8List(0),
        transformation: 'DES/ECB/NoPadding',
        encrypting: true,
      );
      final decrypted = engine.cipherProcessBytesForTesting(
        input: encrypted,
        keyBytes: key8,
        ivBytes: Uint8List(0),
        transformation: 'DES/ECB/NoPadding',
        encrypting: false,
      );
      expect(decrypted, input);
    });
  });

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

    test('splits legado loose single quoted embedded config', () {
      final embedded = LegadoRequestBuilder.splitEmbeddedConfig(
        "https://example.com/search,{'webView': true, method:'POST', 'headers':{'User-Agent':'MobileUA',},}",
      );

      expect(embedded.url, 'https://example.com/search');
      expect(embedded.config['webView'], isTrue);
      expect(embedded.config['method'], 'POST');
      expect(embedded.config['headers'], isA<Map>());
      expect(embedded.config['headers']['User-Agent'], 'MobileUA');
    });

    test('splits legado header directives before and after urls', () {
      final prefixed = LegadoRequestBuilder.splitEmbeddedConfig(
        "@Header:{Referer:'https://m.example.com/search'}/search@kw=abc",
      );
      expect(prefixed.url, '/search@kw=abc');
      expect(
        prefixed.config['headers']['Referer'],
        'https://m.example.com/search',
      );

      final suffixed = LegadoRequestBuilder.splitEmbeddedConfig(
        'https://example.com/search@header:{referer:example.com,Accept-Encoding:*}',
      );
      expect(suffixed.url, 'https://example.com/search');
      expect(suffixed.config['headers']['referer'], 'example.com');
      expect(suffixed.config['headers']['Accept-Encoding'], '*');
    });

    test('merges legado header directives with comma embedded config', () {
      final embedded = LegadoRequestBuilder.splitEmbeddedConfig(
        '@Header:{Referer:"https://ref.example"}https://example.com/search,{"headers":{"X-Test":"1"},"method":"POST"}',
      );

      expect(embedded.url, 'https://example.com/search');
      expect(embedded.config['method'], 'POST');
      expect(embedded.config['headers']['X-Test'], '1');
      expect(embedded.config['headers']['Referer'], 'https://ref.example');
    });

    test('resolves legado header directive urls into request headers', () {
      final source = BookSource()
        ..bookSourceName = 'Header URL'
        ..bookSourceUrl = 'https://example.com/base/';

      final resolved = LegadoRequestBuilder.resolveUrl(
        source.bookSourceUrl,
        '@Header:{Referer:"https://ref.example"}/api/search',
      );
      final request = LegadoRequestBuilder.buildRequest(source, resolved);

      expect(
        resolved,
        'https://example.com/api/search,{"headers":{"Referer":"https://ref.example"}}',
      );
      expect(request.url, 'https://example.com/api/search');
      expect(request.headers?['Referer'], 'https://ref.example');
    });

    test('drops empty urls with only embedded config suffix', () {
      expect(
        LegadoRequestBuilder.resolveUrl(
          'https://example.com/book/1.html',
          ',{"webView":true}',
        ),
        isEmpty,
      );
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

    test('replaces gbk java encode helpers in search urls', () {
      final source = BookSource()
        ..bookSourceName = 'GBK'
        ..bookSourceUrl = 'https://example.com'
        ..searchUrl =
            '/search.php?kw={{java.encodeURI(key, "gbk")}}&p={{page}}';

      final url = LegadoRequestBuilder.buildSearchUrl(
        source,
        '\u4e2d',
        page: 2,
      );

      expect(url, 'https://example.com/search.php?kw=%D6%D0&p=2');
    });

    test('replaces Packages getBytes hex templates without js runtime', () {
      final source = BookSource()
        ..bookSourceName = 'Bytes'
        ..bookSourceUrl = 'http://www.shubao96.com'
        ..searchUrl =
            'http://www.shubao96.com/search/_{{Packages.java.lang.String("key").getBytes("gbk").map(x => (x&0xff).toString(16)).join("_")}}/{{page}}';

      final url = LegadoRequestBuilder.buildSearchUrl(
        source,
        '\u4e2d',
        page: 3,
      );

      expect(url, 'http://www.shubao96.com/search/_d6_d0/3');
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

    test('keeps result placeholder after json field post processors', () {
      final data = {'BookId': 1209977};

      final value = LegadoRuleEvaluator.extractJsonValue(
        data,
        'BookId\n'
        '<js>java.base64Encode(result)</js>\n'
        'data:bookId;base64,{{result}},{"type":"ywc"}',
      );

      expect(value, 'data:bookId;base64,MTIwOTk3Nw==,{"type":"ywc"}');
    });

    test('does not run json field post processors on missing fields', () {
      final value = LegadoRuleEvaluator.extractJsonValue(
        {'OtherId': 1209977},
        'BookId\n'
        '<js>java.base64Encode(result)</js>\n'
        'data:bookId;base64,{{result}},{"type":"ywc"}',
      );

      expect(value, isEmpty);
    });

    test('does not treat missing fields in json strings as literals', () {
      final value = LegadoRuleEvaluator.extractJsonValue(
        '{"Result":-3,"Message":"签名错误"}',
        'BookId\n'
            '<js>java.base64Encode(result)</js>\n'
            'data:bookId;base64,{{result}},{"type":"ywc"}',
      );

      expect(value, isEmpty);
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

    test('expands dotted json list alternatives on api responses', () {
      final data = {
        'Data': {
          'Books': [
            {'BookName': '重生霍雨浩，但是斗破苍穹', 'BookId': 1044903196},
            {'BookName': '斗破苍穹', 'BookId': 1209977},
          ],
        },
      };

      final nodes = LegadoRuleEvaluator.extractJsonNodes(
        data,
        '.BookCard&&Data.Books&&Data.Data.Items||Data.RankBookList',
      );

      expect(nodes, hasLength(2));
      expect((nodes.last as Map)['BookName'], '斗破苍穹');
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

    test('runs json template js blocks with node context as result', () {
      if (!LegadoJsEngine().canEvaluate) return;
      final item = {'order': 1, 'name': '正文', 'type': 'volume'};

      final title = LegadoRuleEvaluator.extractJsonValue(
        item,
        r'''第{{$.order}}章 {{$.name}}
<js>
vol = "{{$.type}}"=="volume"?" 📖 ":""
vol+result+vol
</js>
##第章\s*|第\d+章\s*(?=第\d+章)''',
      );

      expect(title, '📖 第1章 正文 📖');
    });

    test('runs chained json js and @js blocks for chapter url', () {
      if (!LegadoJsEngine().canEvaluate) return;
      final item = {'id': 456, 'type': 'chapter'};

      final url = LegadoRuleEvaluator.extractJsonValue(item, r'''<js>
var ids = "{{$.id}}"
result = "https://api.example.com/read?chapter_ids=" + ids
</js>
@js:
"{{$.type}}"=="volume"?"":result''');

      expect(url, 'https://api.example.com/read?chapter_ids=456');
    });

    test('interpolates json template java expression fallbacks', () {
      final item = {'book_id': 12345, 'updated_at': 1700000000};

      expect(
        LegadoRuleEvaluator.extractJsonValue(
          item,
          r'https://book.example/details/{{parseInt(java.getString("$.book_id")/1000)}}/{{$.book_id}}.html',
        ),
        'https://book.example/details/12/12345.html',
      );
      expect(
        LegadoRuleEvaluator.extractJsonValue(
          item,
          r'{{java.timeFormat(java.getString("$.updated_at")*1000)}}',
        ),
        contains('2023'),
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
      expect(LegadoRuleEvaluator.extractHtmlValue(node, 'textNodes'), 'Own');
      expect(
        LegadoRuleEvaluator.extractHtmlValue(node, 'all'),
        contains('data-id="42"'),
      );
      expect(LegadoRuleEvaluator.extractHtmlValue(node, 'attr(data-id)'), '42');
    });

    test('interpolates html template rules with css fragments', () {
      final document = parse('''
        <article>
          <meta property="og:novel:status" content="ongoing">
          <meta property="og:novel:category" content="fantasy">
          <a class="bt" href="/book/1">Open</a>
          <a class="PagesLink" href="/book/1_2.html">next page</a>
        </article>
      ''');
      final root = document.body!;

      expect(
        LegadoRuleEvaluator.extractHtmlValue(
          root,
          '{{@css:meta[property="og:novel:status"] @content}}/'
          '{{@css:meta[property="og:novel:category"] @content}}',
        ),
        'ongoing/fantasy',
      );
      expect(
        LegadoRuleEvaluator.extractHtmlValue(
          root,
          'https://www.example.com{{@css:a.bt @href}}',
        ),
        'https://www.example.com/book/1',
      );
      expect(
        LegadoRuleEvaluator.extractHtmlValue(
          root,
          '{{@css:a.PagesLink @href}},{"webView":true}',
        ),
        '/book/1_2.html,{"webView":true}',
      );
      expect(
        LegadoRuleEvaluator.extractHtmlValue(
          root,
          '{{@@article@html@@a.bt @href}}',
        ),
        '/book/1',
      );
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

    test(
      'supports official legado legacy index filters and children selector',
      () {
        final document = parse('''
        <div class="books m-cols">
          <article>A</article>
          <article>B</article>
          <article>C</article>
          <article>D</article>
        </div>
        <table>
          <tr><td>header</td></tr>
          <tr><td>row1</td></tr>
          <tr><td>row2</td></tr>
        </table>
      ''');

        expect(
          LegadoRuleEvaluator.queryAll(
            document,
            'class.books m-cols@children',
          ).map((node) => node.text.trim()).toList(),
          ['A', 'B', 'C', 'D'],
        );
        expect(
          LegadoRuleEvaluator.queryAll(
            document,
            'class.books m-cols@children.0:2:-1',
          ).map((node) => node.text.trim()).toList(),
          ['A', 'C', 'D'],
        );
        expect(
          LegadoRuleEvaluator.queryAll(
            document,
            'tag.tr!0',
          ).map((node) => node.text.trim()).toList(),
          ['row1', 'row2'],
        );
        expect(
          LegadoRuleEvaluator.extractHtmlValue(
            document.body!,
            'class.books m-cols@children!0:-1@text',
          ),
          'B\nC',
        );
      },
    );

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
        LegadoRuleEvaluator.queryAll(
          document,
          'td:nth-of-type(2)',
        ).map((node) => node.text.trim()).toList(),
        ['R0C1', 'R1C1', 'R2C1'],
      );
      expect(
        LegadoRuleEvaluator.extractHtmlValue(
          document.body!,
          'tr:eq(1)>td:eq(0)@text',
        ),
        'R1C0',
      );
    });

    test('supports not pseudo filters used by content rules', () {
      final document = parse('''
        <div id="content">
          <p>first</p>
          <p>middle</p>
          <p>ads</p>
        </div>
        <div class="introduction">
          <p>normal intro</p>
          <p>Audio intro</p>
        </div>
        <table class="grid">
          <tr><td>header</td></tr>
          <tr align="center"><td>skip</td></tr>
          <tr><td>keep</td></tr>
        </table>
        <div id="booklist">
          <table><tr><td><li><a href="/c1">c1</a></li></td></tr></table>
        </div>
      ''');

      expect(
        LegadoRuleEvaluator.extractHtmlValue(
          document.body!,
          '#content p:not(:last-child)@text',
        ),
        'first\nmiddle',
      );
      expect(
        LegadoRuleEvaluator.extractHtmlValue(
          document.body!,
          '.introduction p:not(:matches(Audio|Listen))@text',
        ),
        'normal intro',
      );
      expect(
        LegadoRuleEvaluator.queryAll(
          document,
          '.grid tr:not([align])',
        ).map((node) => node.text.trim()).toList(),
        ['header', 'keep'],
      );
      expect(
        LegadoRuleEvaluator.extractHtmlValue(
          document.body!,
          '#booklist table:not(strong:contains(Latest)) li a@href',
        ),
        '/c1',
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

    test('supports cipher decode js post processor fallback', () {
      final aes = LegadoRuleEvaluator.applyPostProcessors(
        'ZM6V+N4TrIblhrpN+FfkYw==',
        r'''@js:java.aesBase64DecodeToString(result, "1234567890123456", "AES/CBC/PKCS5Padding", "abcdefghijklmnop")''',
      );
      final des = LegadoRuleEvaluator.applyPostProcessors(
        '0XUfPCehJ3Q=',
        r'''@js:java.aesBase64DecodeToString(result, "6CB1E21E", "DES/CBC/PKCS5Padding", "1F0FB845")''',
      );

      expect(aes, 'hello');
      expect(des, 'hello');
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

    test('normalizes uppercase css and xpath rule prefixes', () {
      final document = parse('''
        <div class="book"><a href="/book/1">Book One</a></div>
      ''');

      expect(LegadoRuleEvaluator.queryAll(document, '@CSS:.book').length, 1);
      expect(
        LegadoRuleEvaluator.extractHtmlValue(
          document.body!,
          '@CSS:.book a@href',
        ),
        '/book/1',
      );
      expect(
        LegadoRuleEvaluator.extractHtmlValue(
          document.body!,
          '@XPath://div[@class="book"]/a/text()',
        ),
        'Book One',
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
          'id.chaptercontent@p[1:-2]@text',
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
      LegadoRuleEvaluator.extractJsonValue({
        'BOOKID': 953528,
      }, r'@put:{"savebid":"$.BOOKID"}');
      expect(
        LegadoRuleEvaluator.extractJsonValue({}, r'@get:{savebid}'),
        '953528',
      );
      expect(
        LegadoRuleEvaluator.extractJsonValue(item, r'$.id@PUT:{BID:$.id}'),
        '42',
      );
      expect(
        LegadoRuleEvaluator.extractJsonValue(
          item,
          r'https://example.com/book/@GET:{BID}/{{$.chapter}}.html',
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

    test('injects source book and chapter convenience aliases', () {
      final engine = LegadoJsEngine();
      if (!engine.isAvailable) return;
      final value = engine.evaluate(
        [
          'source.getName()',
          'source.getSourceUrl()',
          'book.getName()',
          'book.getBookUrl()',
          'book.getTocUrl()',
          'chapter.getTitle()',
          'chapter.getChapterUrl()',
          'chapter.getChapterIndex()',
        ].join(' + "|" + '),
        variables: {
          'source': {
            'bookSourceName': 'Source A',
            'bookSourceUrl': 'https://source.example',
          },
          'book': {
            'name': 'Book A',
            'bookUrl': 'https://source.example/book/1',
            'tocUrl': 'https://source.example/book/1/toc',
          },
          'chapter': {
            'title': 'Chapter A',
            'chapterUrl': 'https://source.example/book/1/1.html',
            'chapterIndex': 7,
          },
        },
      );

      expect(
        value,
        'Source A|https://source.example|Book A|https://source.example/book/1|https://source.example/book/1/toc|Chapter A|https://source.example/book/1/1.html|7',
      );
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

    test('resolves java.connect get body through ajax callback', () async {
      if (!LegadoJsEngine().isAvailable) return;
      final requests = <String>[];
      final value = await LegadoJsEngine().evaluateWithAjax(
        '<js>var body = java.connect("https://example.com/books").get().body(); JSON.parse(body).title;</js>',
        ajax: (request) async {
          requests.add(request);
          return jsonEncode({'title': 'Connected'});
        },
      );

      expect(value, 'Connected');
      expect(requests.single, 'https://example.com/books');
    });

    test('resolves java.connect direct body string alias', () async {
      if (!LegadoJsEngine().isAvailable) return;
      final requests = <String>[];
      final value = await LegadoJsEngine().evaluateWithAjax(
        '<js>java.connect("https://example.com/books").body().string();</js>',
        ajax: (request) async {
          requests.add(request);
          return jsonEncode({'title': 'DirectBody'});
        },
      );

      expect(value, '{"title":"DirectBody"}');
      expect(requests.single, 'https://example.com/books');
    });

    test('resolves java.connect post body through ajax callback', () async {
      if (!LegadoJsEngine().isAvailable) return;
      final requests = <String>[];
      final value = await LegadoJsEngine().evaluateWithAjax(
        '<js>var body = java.connect("https://example.com/books").header("X-Test","1").post("a=1").body(); JSON.parse(body).ok;</js>',
        ajax: (request) async {
          requests.add(request);
          return jsonEncode({'ok': true});
        },
      );

      expect(value, 'true');
      expect(requests.single, contains('https://example.com/books,'));
      expect(requests.single, contains('"method":"POST"'));
      expect(requests.single, contains('"body":"a=1"'));
      expect(requests.single, contains('"X-Test":"1"'));
    });

    test('supports java ajaxAll head and getStrResponse helpers', () async {
      if (!LegadoJsEngine().canEvaluate) return;
      final value = await LegadoJsEngine().evaluateWithAjax(
        r'''@js:
var all = await java.ajaxAll(["data:text/plain,A", "data:text/plain,B"]);
var head = java.head("data:text/plain,meta-ok", {"X-Test":"1"});
var headBody = await head.body();
var headStatus = head.statusCode();
var title = await java.getStrResponse("data:text/html,%3Cdiv%3E%3Cspan%20class%3D%22title%22%3EBook%20Title%3C%2Fspan%3E%3C%2Fdiv%3E", ".title@text");
var responseCode = java.getResponseCode("data:text/plain,response-code-ok");
JSON.stringify({
  all: all,
  headBody: headBody && typeof headBody.string === "function" ? headBody.string() : String(headBody),
  status: headStatus,
  responseCode: responseCode,
  title: title
})''',
        ajax: (request) async {
          if (request.contains('data:text/plain,A')) return 'A';
          if (request.contains('data:text/plain,B')) return 'B';
          if (request.contains('data:text/plain,meta-ok')) return 'meta-ok';
          if (request.contains('data:text/html,')) {
            return '<div><span class="title">Book Title</span></div>';
          }
          if (request.contains('data:text/plain,response-code-ok')) {
            return 'response-code-ok';
          }
          return '';
        },
      );
      final decoded = jsonDecode(value) as Map<String, dynamic>;

      expect(decoded['all'], ['A', 'B']);
      expect(decoded['headBody'], 'meta-ok');
      expect(decoded['status'], 200);
      expect(decoded['responseCode'], 200);
      expect(decoded['title'], 'Book Title');
    });

    test('supports java importScript helper aliases', () async {
      if (!LegadoJsEngine().canEvaluate) return;
      final value = await LegadoJsEngine().evaluateWithAjax(r'''@js:
java.importScript("data:text/javascript,function%20fromJavaImport()%20%7B%20return%20%22java-import%22%3B%20%7D");
importScript("data:text/javascript,function%20fromGlobalImport()%20%7B%20return%20%22global-import%22%3B%20%7D");
fromJavaImport() + "|" + fromGlobalImport();
''', ajax: (request) async => '');

      expect(value, 'java-import|global-import');
    });

    test('supports source scoped file cache helpers', () async {
      if (!LegadoJsEngine().canEvaluate) return;
      final value = await LegadoJsEngine().evaluateWithAjax(r'''@js:
java.cacheFile("token.txt", "abc123");
var before = java.readTxtFile("token.txt");
var removed = java.deleteFile("token.txt");
var after = java.readFile("token.txt");
JSON.stringify({before: before, removed: removed, after: after});
''', ajax: (request) async => '');
      final decoded = jsonDecode(value) as Map<String, dynamic>;

      expect(decoded['before'], 'abc123');
      expect(decoded['removed'], true);
      expect(decoded['after'], '');
    });

    test('supports ajax metadata status and headers', () async {
      if (!LegadoJsEngine().canEvaluate) return;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.statusCode = HttpStatus.notFound;
        request.response.headers.contentType = ContentType.text;
        request.response.write('meta-body');
        await request.response.close();
      });
      final baseUrl = 'http://${server.address.host}:${server.port}/meta';
      final value = await LegadoJsEngine().evaluateWithAjax('''@js:
var fetched = await java.fetch("$baseUrl");
var fetchedBody = await fetched.body();
JSON.stringify({
  fetchedStatus: fetched.statusCode(),
  body: fetchedBody.string(),
  directCode: await java.getResponseCode("$baseUrl")
})''', ajax: (request) async => '');
      final decoded = jsonDecode(value) as Map<String, dynamic>;

      expect(decoded['fetchedStatus'], 404);
      expect(decoded['body'], 'meta-body');
      expect(decoded['directCode'], 404);
    });

    test('resolves global fetch through ajax callback', () async {
      if (!LegadoJsEngine().isAvailable) return;
      final requests = <String>[];
      final value = await LegadoJsEngine().evaluateWithAjax(
        '<js>var html = fetch("https://example.com/page"); html.match(/<h1>(.*?)<\\/h1>/)[1];</js>',
        ajax: (request) async {
          requests.add(request);
          return '<h1>Fetched</h1>';
        },
      );

      expect(value, 'Fetched');
      expect(requests.single, 'https://example.com/page');
    });

    test('resolves request post options through ajax callback', () async {
      if (!LegadoJsEngine().isAvailable) return;
      final requests = <String>[];
      final value = await LegadoJsEngine().evaluateWithAjax(
        '<js>var res = request("https://example.com/api", {method:"post", body:"q=1", headers:{"X-App":"reader"}}); res.json().ok;</js>',
        ajax: (request) async {
          requests.add(request);
          return jsonEncode({'ok': true});
        },
      );

      expect(value, 'true');
      expect(requests.single, contains('https://example.com/api,'));
      expect(requests.single, contains('"method":"POST"'));
      expect(requests.single, contains('"body":"q=1"'));
      expect(requests.single, contains('"X-App":"reader"'));
    });

    test('resolves java fetch response aliases through ajax callback', () async {
      if (!LegadoJsEngine().isAvailable) return;
      final requests = <String>[];
      final value = await LegadoJsEngine().evaluateWithAjax(
        '<js>java.fetch("https://example.com/api", {method:"post", body:"a=1"}).body().string();</js>',
        ajax: (request) async {
          requests.add(request);
          return '{"ok":true}';
        },
      );

      expect(value, '{"ok":true}');
      expect(requests.single, contains('"method":"POST"'));
      expect(requests.single, contains('"body":"a=1"'));
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

    test(
      'keeps original book url when book info tocUrl points to category page',
      () async {
        final source = BookSource()
          ..bookSourceName = 'Category Toc Source'
          ..bookSourceUrl = 'https://example.com'
          ..ruleBookInfo = jsonEncode({
            'name': 'h1@text',
            'tocUrl': '.btns a.-2@href',
          });
        final book = Book(
          title: 'Alpha Novel',
          author: 'Author A',
          filePath: 'https://example.com/book/159555/',
          fileType: 'online',
          isFromSource: true,
        );
        final response = Response<dynamic>(
          data: '''
            <html><body>
              <h1>Alpha Novel</h1>
              <div class="btns">
                <a href="/read/159555/1.html">Read</a>
                <a href="/cat/45/">Category</a>
                <a href="/user/fav">Favorite</a>
              </div>
            </body></html>
          ''',
          statusCode: 200,
          requestOptions: RequestOptions(path: book.filePath),
        );

        final parsed = await LegadoParser.parseBookInfo(
          source,
          book,
          preFetchedResponse: response,
        );

        expect(parsed.filePath, 'https://example.com/book/159555/');
      },
    );

    test(
      'keeps original book url when book info tocUrl contains inert javascript',
      () async {
        final source = BookSource()
          ..bookSourceName = 'Javascript Toc Source'
          ..bookSourceUrl = 'https://example.com'
          ..ruleBookInfo = jsonEncode({
            'name': 'h1@text',
            'tocUrl': 'a.catalog@href',
          });
        final book = Book(
          title: 'Alpha Novel',
          author: 'Author A',
          filePath: 'https://example.com/book/159555/',
          fileType: 'online',
          isFromSource: true,
        );
        final response = Response<dynamic>(
          data: '''
            <html><body>
              <h1>Alpha Novel</h1>
              <a class="catalog" href="/book/159555/MainIndex/javascript:">Catalog</a>
            </body></html>
          ''',
          statusCode: 200,
          requestOptions: RequestOptions(path: book.filePath),
        );

        final parsed = await LegadoParser.parseBookInfo(
          source,
          book,
          preFetchedResponse: response,
        );

        expect(parsed.filePath, 'https://example.com/book/159555/');
      },
    );

    test('keeps original book url when book info has no tocUrl rule', () async {
      final source = BookSource()
        ..bookSourceName = 'No Toc Url Source'
        ..bookSourceUrl = 'https://example.com'
        ..ruleBookInfo = jsonEncode({
          'name': 'h1@text',
          'lastChapter': '.latest a@text',
        });
      final book = Book(
        title: 'Alpha Novel',
        author: 'Author A',
        filePath: 'https://example.com/book/159555/',
        fileType: 'online',
        isFromSource: true,
      );
      final response = Response<dynamic>(
        data: '''
            <html><body>
              <h1>Alpha Novel</h1>
              <div class="latest"><a href="/chapter/1.html">Chapter One</a></div>
            </body></html>
          ''',
        statusCode: 200,
        requestOptions: RequestOptions(path: book.filePath),
      );

      final parsed = await LegadoParser.parseBookInfo(
        source,
        book,
        preFetchedResponse: response,
      );

      expect(parsed.filePath, 'https://example.com/book/159555/');
    });

    test('uses imported js bookInfo chapter list url aliases', () async {
      if (!LegadoJsEngine().isAvailable) return;
      final source = BookSource()
        ..bookSourceName = 'JS BookInfo Alias'
        ..bookSourceUrl = 'https://js.example.com'
        ..customConfig = jsonEncode({
          'engine': 'quickjs',
          'sourceFormat': 'js',
          'jsLib': r'''
function bookInfo(result) {
  return {
    title: "Alias Book",
    writer: "Alias Author",
    chapterListUrl: "/book/1/catalog",
    img: "/cover.jpg"
  };
}
''',
        })
        ..ruleBookInfo = jsonEncode({
          'init': '<js>bookInfo(result)</js>',
          'name': r'$.title',
          'author': r'$.writer',
          'coverUrl': r'$.img',
        });
      final book = Book(
        title: 'Original',
        author: 'Unknown',
        filePath: 'https://js.example.com/book/1',
        fileType: 'online',
        isFromSource: true,
      );
      final response = Response<dynamic>(
        data: '<html><body>ignored by js bookInfo</body></html>',
        statusCode: 200,
        requestOptions: RequestOptions(path: book.filePath),
      );

      final parsed = await LegadoParser.parseBookInfo(
        source,
        book,
        preFetchedResponse: response,
      );

      expect(parsed.title, 'Alias Book');
      expect(parsed.author, 'Alias Author');
      expect(parsed.filePath, 'https://js.example.com/book/1/catalog');
      expect(parsed.coverPath, 'https://js.example.com/cover.jpg');
    });

    test('does not build data toc url from missing json book id', () async {
      final source = BookSource()
        ..bookSourceName = 'Missing Json Toc Id Source'
        ..bookSourceUrl = 'https://example.com'
        ..ruleBookInfo = jsonEncode({
          'init': r'$.Data',
          'name': 'BookName',
          'tocUrl':
              'BookId\n<js>java.base64Encode(result)</js>\ndata:bookId;base64,{{result}},{"type":"ywc"}',
        });
      final book = Book(
        title: 'Existing',
        author: '',
        filePath: 'https://example.com/detail?bookId=1209977',
        fileType: 'online',
        isFromSource: true,
      );
      final response = Response<dynamic>(
        data: '{"Result":-3,"Message":"签名错误"}',
        requestOptions: RequestOptions(path: book.filePath),
        statusCode: 200,
      );

      final parsed = await LegadoParser.parseBookInfo(
        source,
        book,
        preFetchedResponse: response,
      );

      expect(parsed.filePath, isNot(contains('Qm9va0lk')));
      expect(parsed.filePath, book.filePath);
    });

    test('repairs data toc payload field name from original book id', () async {
      final source = BookSource()
        ..bookSourceName = 'Literal Json Toc Id Source'
        ..bookSourceUrl = 'https://example.com'
        ..ruleBookInfo = jsonEncode({
          'name': 'BookName',
          'tocUrl':
              'BookId\n<js>java.base64Encode(result)</js>\ndata:bookId;base64,{{result}},{"type":"ywc"}',
        });
      final book = Book(
        title: 'Existing',
        author: '',
        filePath: 'https://example.com/detail?bookId=1209977',
        fileType: 'online',
        isFromSource: true,
      );
      final response = Response<dynamic>(
        data: '{"BookName":"Existing","BookId":"BookId"}',
        requestOptions: RequestOptions(path: book.filePath),
        statusCode: 200,
      );

      final parsed = await LegadoParser.parseBookInfo(
        source,
        book,
        preFetchedResponse: response,
      );

      expect(parsed.filePath, 'data:bookId;base64,MTIwOTk3Nw==,{"type":"ywc"}');
    });

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
      'falls back to chapter-like html anchors when chapterList is missing',
      () async {
        final source = BookSource()
          ..bookSourceName = 'No ChapterList Source'
          ..bookSourceUrl = 'https://example.com'
          ..ruleToc = jsonEncode({
            'chapterName': '@text',
            'chapterUrl': '@href',
          });
        final book = Book(
          title: 'Book',
          filePath: 'https://example.com/book/2',
          fileType: 'online',
          isFromSource: true,
        );
        final response = Response<dynamic>(
          data: '''
          <html><body>
            <div class="catalog">
              <a href="/book/2/001.html">001. 序幕</a>
              <a href="/book/2/002.html">002. 出发</a>
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
        expect(chapters.first.title, '001. 序幕');
        expect(chapters.last.url, 'https://example.com/book/2/002.html');
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

    test('keeps relative URL after empty inline cookie helper', () async {
      final source = BookSource()
        ..bookSourceName = 'Inline Cookie'
        ..bookSourceUrl = 'https://www.dmx5.cc#tag'
        ..searchUrl = '''
{{cookie.removeCookie(source.getKey())}}
/search/book,{
  "charset": "gbk",
  "method": "post",
  "body": "searchkey={{key}}"
}''';

      final url = await LegadoParser.buildSearchUrl(source, '斗破苍穹');

      expect(url, startsWith('https://www.dmx5.cc/search/book,'));
      expect(url, contains('"charset":"gbk"'));
      expect(url, contains('%B6%B7%C6%C6%B2%D4%F1%B7'));
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

    test('does not treat missing bare json keys as literal field values', () {
      final errorPayload = {'code': 16, 'data': null, 'msg': '鉴权参数无效'};

      expect(
        LegadoRuleEvaluator.extractJsonValue(errorPayload, 'bookName'),
        isEmpty,
      );
      expect(
        LegadoRuleEvaluator.extractJsonValue(errorPayload, 'data.list[*]'),
        isEmpty,
      );
      expect(LegadoRuleEvaluator.extractJsonValue(errorPayload, '0'), '0');
      expect(
        LegadoRuleEvaluator.extractJsonValue(errorPayload, '固定分类'),
        '固定分类',
      );
    });

    test('exposes book origin to javascript post processors', () {
      final value = LegadoRuleEvaluator.extractJsonValue(
        {'Id': '155711'},
        r'$.Id@js:book.origin+"/BookFiles/Html/"+result+"/index.html"',
        variables: {
          'book': {'origin': 'https://api.example.com'},
        },
      );

      expect(value, 'https://api.example.com/BookFiles/Html/155711/index.html');
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

    test('normalizes uppercase javascript post processor markers', () {
      expect(LegadoRuleEvaluator.isJsOnlyRule('@JS:result'), isTrue);
      expect(LegadoRuleEvaluator.containsJsRule('<JS>result</JS>'), isTrue);
      expect(
        LegadoRuleEvaluator.applyPostProcessors('abc', r'@JS:"x"+result'),
        'xabc',
      );
      expect(
        LegadoRuleEvaluator.applyPostProcessors(
          'ads text ads',
          r'<JS>result.replace(/ads/g,"")</JS>',
        ),
        'text',
      );
    });

    test('applies String(result) replace chains and JS replacement groups', () {
      expect(
        LegadoRuleEvaluator.applyPostProcessors(
          'https://m.example.com/book/12/34.html',
          r'''<js>String(result).replace(/.*\/(\d+)\/(\d+).*/, "https://m.example.com/wapbook/$1_$2.html").trim()</js>''',
        ),
        'https://m.example.com/wapbook/12_34.html',
      );
      expect(
        LegadoRuleEvaluator.applyPostProcessors(
          'A ads B ads',
          r'''@js:String(result).replace(/ads/g, "").replace(/\s+/g, " ").trim().toLowerCase()''',
        ),
        'a b',
      );
    });

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

    test('supports legado first-match triple marker before replacement', () {
      final value = LegadoRuleEvaluator.applyPostProcessors(
        "https://book.example.com/info/1,{'webView': true}",
        "##,{'webView': true}###Catalog,{'webView': true}",
      );

      expect(value, "Catalog,{'webView': true}");
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

    test('parses imported js function search results', () async {
      if (!LegadoJsEngine().isAvailable) return;
      final source = BookSource()
        ..bookSourceName = 'JS Function Search'
        ..bookSourceUrl = 'https://js.example.com'
        ..searchUrl = '/search?q={{key}}'
        ..customConfig = jsonEncode({
          'engine': 'quickjs',
          'sourceFormat': 'js',
          'jsLib': r'''
function search(key, page, result) {
  return [
    {
      name: key + " One",
      author: "Author A",
      bookUrl: "/book/1",
      coverUrl: "/cover/1.jpg",
      intro: "Intro A",
      kind: "Fantasy",
      lastChapter: "Chapter 9"
    }
  ];
}
''',
        })
        ..ruleSearch = jsonEncode({
          'bookList': '<js>search(key, page, result)</js>',
          'name': r'$.name',
          'author': r'$.author',
          'bookUrl': r'$.bookUrl',
          'coverUrl': r'$.coverUrl',
          'intro': r'$.intro',
          'kind': r'$.kind',
          'lastChapter': r'$.lastChapter',
        });
      final response = Response<dynamic>(
        data: '<html><body>ignored by js function source</body></html>',
        requestOptions: RequestOptions(path: 'https://js.example.com/search'),
        statusCode: 200,
      );

      final books = await LegadoParser.searchBooks(
        source,
        'Novel',
        preFetchedResponse: response,
      );

      expect(books, hasLength(1));
      expect(books.single.title, 'Novel One');
      expect(books.single.author, 'Author A');
      expect(books.single.filePath, 'https://js.example.com/book/1');
      expect(books.single.coverPath, 'https://js.example.com/cover/1.jpg');
      expect(books.single.tags, contains('Fantasy'));
      expect(books.single.totalChapters, 9);
    });

    test('parses imported js function search field aliases', () async {
      if (!LegadoJsEngine().isAvailable) return;
      final source = BookSource()
        ..bookSourceName = 'JS Function Search Aliases'
        ..bookSourceUrl = 'https://js.example.com'
        ..searchUrl = '/search?q={{key}}'
        ..customConfig = jsonEncode({
          'engine': 'quickjs',
          'sourceFormat': 'js',
          'jsLib': r'''
function search(key, page, result) {
  return {
    books: [{
      title: key + " Alias",
      writer: "Alias Author",
      url: "/book/alias",
      img: "/cover/alias.jpg",
      category: "Fantasy,Hot",
      latest: "Chapter 12"
    }]
  };
}
''',
        })
        ..ruleSearch = jsonEncode({
          'bookList': '<js>search(key, page, result)</js>',
        });
      final response = Response<dynamic>(
        data: '<html><body>ignored by js function source aliases</body></html>',
        requestOptions: RequestOptions(path: 'https://js.example.com/search'),
        statusCode: 200,
      );

      final books = await LegadoParser.searchBooks(
        source,
        'Novel',
        preFetchedResponse: response,
      );

      expect(books, hasLength(1));
      expect(books.single.title, 'Novel Alias');
      expect(books.single.author, 'Alias Author');
      expect(books.single.filePath, 'https://js.example.com/book/alias');
      expect(books.single.coverPath, 'https://js.example.com/cover/alias.jpg');
      expect(books.single.tags, containsAll(['Fantasy', 'Hot']));
      expect(books.single.totalChapters, 12);
    });

    test('parses imported js function explore results', () async {
      if (!LegadoJsEngine().canEvaluate) return;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.headers.contentType = ContentType.html;
        request.response.write('<html><body>explore seed</body></html>');
        await request.response.close();
      });
      final baseUrl = 'http://${server.address.host}:${server.port}';
      final source = BookSource()
        ..bookSourceName = 'JS Function Explore Source'
        ..bookSourceUrl = baseUrl
        ..exploreUrl = '/rank/{{page}}'
        ..customConfig = jsonEncode({
          'engine': 'quickjs',
          'sourceFormat': 'js',
          'jsLib': r'''
function explore(baseUrl, result) {
  return {
    data: {
      items: [{
        title: "Explore Book",
        writer: "Explore Author",
        url: "/books/explore",
        img: "/covers/explore.jpg",
        latest: "Chapter 9",
        category: "Fantasy"
      }]
    }
  };
}
''',
        })
        ..ruleExplore = jsonEncode({
          'bookList': '<js>explore(baseUrl, result)</js>',
        });

      final books = await LegadoParser.parseExploreBooks(
        source,
        '$baseUrl/rank/1',
        page: 1,
      );

      expect(books, hasLength(1));
      expect(books.single.title, 'Explore Book');
      expect(books.single.author, 'Explore Author');
      expect(books.single.filePath, '$baseUrl/books/explore');
      expect(books.single.coverPath, '$baseUrl/covers/explore.jpg');
      expect(books.single.tags, contains('Fantasy'));
    });

    test('parses imported js function toc results', () async {
      if (!LegadoJsEngine().isAvailable) return;
      final source = BookSource()
        ..bookSourceName = 'JS Function Toc'
        ..bookSourceUrl = 'https://js.example.com'
        ..customConfig = jsonEncode({
          'engine': 'quickjs',
          'sourceFormat': 'js',
          'jsLib': r'''
function toc(result) {
  return [
    {name: "Chapter 1", url: "/chapter/1"},
    {name: "Chapter 2", url: "/chapter/2"}
  ];
}
''',
        })
        ..ruleToc = jsonEncode({
          'chapterList': '<js>toc(result)</js>',
          'chapterName': r'$.name',
          'chapterUrl': r'$.url',
        });
      final book = Book(
        title: 'Novel',
        author: 'Author',
        filePath: 'https://js.example.com/book/1',
        fileType: 'online',
        isFromSource: true,
      );
      final response = Response<dynamic>(
        data: '<html><body>ignored by js toc</body></html>',
        requestOptions: RequestOptions(path: 'https://js.example.com/book/1'),
        statusCode: 200,
      );

      final chapters = await LegadoParser.getChapterList(
        source,
        book,
        preFetchedResponse: response,
      );

      expect(chapters, hasLength(2));
      expect(chapters.first.title, 'Chapter 1');
      expect(chapters.first.url, 'https://js.example.com/chapter/1');
      expect(chapters.last.title, 'Chapter 2');
    });

    test('parses imported js function toc container results', () async {
      if (!LegadoJsEngine().isAvailable) return;
      final source = BookSource()
        ..bookSourceName = 'JS Function Toc Container'
        ..bookSourceUrl = 'https://js.example.com'
        ..customConfig = jsonEncode({
          'engine': 'quickjs',
          'sourceFormat': 'js',
          'jsLib': r'''
function toc(result) {
  return {
    chapters: [
      {title: "Chapter A", chapterUrl: "/chapter/a"},
      {title: "Chapter B", chapterUrl: "/chapter/b"}
    ]
  };
}
''',
        })
        ..ruleToc = jsonEncode({
          'chapterList': '<js>toc(result)</js>',
          'chapterName': r'$.title',
          'chapterUrl': r'$.chapterUrl',
        });
      final book = Book(
        title: 'Novel',
        author: 'Author',
        filePath: 'https://js.example.com/book/1',
        fileType: 'online',
        isFromSource: true,
      );
      final response = Response<dynamic>(
        data: '<html><body>ignored by js toc</body></html>',
        requestOptions: RequestOptions(path: 'https://js.example.com/book/1'),
        statusCode: 200,
      );

      final chapters = await LegadoParser.getChapterList(
        source,
        book,
        preFetchedResponse: response,
      );

      expect(chapters, hasLength(2));
      expect(chapters.first.title, 'Chapter A');
      expect(chapters.first.url, 'https://js.example.com/chapter/a');
      expect(chapters.last.title, 'Chapter B');
    });

    test('parses imported js function toc field aliases', () async {
      if (!LegadoJsEngine().isAvailable) return;
      final source = BookSource()
        ..bookSourceName = 'JS Function Toc Aliases'
        ..bookSourceUrl = 'https://js.example.com'
        ..customConfig = jsonEncode({
          'engine': 'quickjs',
          'sourceFormat': 'js',
          'jsLib': r'''
function toc(result) {
  return {
    list: [
      {chapterTitle: "Alias Chapter 1", href: "/read/1"},
      {text: "Alias Chapter 2", path: "/read/2"}
    ]
  };
}
''',
        })
        ..ruleToc = jsonEncode({'chapterList': '<js>toc(result)</js>'});
      final book = Book(
        title: 'Novel',
        author: 'Author',
        filePath: 'https://js.example.com/book/1',
        fileType: 'online',
        isFromSource: true,
      );
      final response = Response<dynamic>(
        data: '<html><body>ignored by js toc aliases</body></html>',
        requestOptions: RequestOptions(path: 'https://js.example.com/book/1'),
        statusCode: 200,
      );

      final chapters = await LegadoParser.getChapterList(
        source,
        book,
        preFetchedResponse: response,
      );

      expect(chapters, hasLength(2));
      expect(chapters.first.title, 'Alias Chapter 1');
      expect(chapters.first.url, 'https://js.example.com/read/1');
      expect(chapters.last.title, 'Alias Chapter 2');
      expect(chapters.last.url, 'https://js.example.com/read/2');
    });

    test('parses imported js function content results', () async {
      if (!LegadoJsEngine().isAvailable) return;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) {
        request.response
          ..headers.contentType = ContentType.html
          ..write('<html><body>ignored by js content</body></html>')
          ..close();
      });
      final baseUrl = 'http://${server.address.host}:${server.port}';
      final source = BookSource()
        ..bookSourceName = 'JS Function Content'
        ..bookSourceUrl = baseUrl
        ..customConfig = jsonEncode({
          'engine': 'quickjs',
          'sourceFormat': 'js',
          'jsLib': r'''
function content(result) {
  return ["First paragraph", "<p>Second paragraph</p>"];
}
''',
        })
        ..ruleContent = jsonEncode({'content': '<js>content(result)</js>'});
      final book = Book(
        title: 'Novel',
        author: 'Author',
        filePath: '$baseUrl/book/1',
        fileType: 'online',
        isFromSource: true,
      );
      final chapter = Chapter(
        bookId: book.id,
        title: 'Chapter 1',
        index: 0,
        url: '$baseUrl/chapter/1',
        content: '$baseUrl/chapter/1',
      );

      final content = await LegadoParser.getChapterContent(
        source,
        '$baseUrl/chapter/1',
        book: book,
        chapter: chapter,
      );

      expect(content, contains('First paragraph'));
      expect(content, contains('Second paragraph'));
      expect(content, isNot(contains('<p>')));
    });

    test('parses imported js function nested content results', () async {
      if (!LegadoJsEngine().isAvailable) return;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) {
        request.response
          ..headers.contentType = ContentType.html
          ..write('<html><body>ignored by nested js content</body></html>')
          ..close();
      });
      final baseUrl = 'http://${server.address.host}:${server.port}';
      final source = BookSource()
        ..bookSourceName = 'JS Function Nested Content'
        ..bookSourceUrl = baseUrl
        ..customConfig = jsonEncode({
          'engine': 'quickjs',
          'sourceFormat': 'js',
          'jsLib': r'''
function content(result) {
  return {data: {paragraphs: ["Nested first", "<p>Nested second</p>"]}};
}
''',
        })
        ..ruleContent = jsonEncode({'content': '<js>content(result)</js>'});
      final book = Book(
        title: 'Novel',
        author: 'Author',
        filePath: '$baseUrl/book/1',
        fileType: 'online',
        isFromSource: true,
      );
      final chapter = Chapter(
        bookId: book.id,
        title: 'Chapter 1',
        index: 0,
        url: '$baseUrl/chapter/1',
        content: '$baseUrl/chapter/1',
      );

      final content = await LegadoParser.getChapterContent(
        source,
        '$baseUrl/chapter/1',
        book: book,
        chapter: chapter,
      );

      expect(content, contains('Nested first'));
      expect(content, contains('Nested second'));
      expect(content, isNot(contains('<p>')));
    });

    test('keeps multiline embedded request config as one book url', () async {
      final source = BookSource()
        ..bookSourceName = 'Embedded Config Search Source'
        ..bookSourceUrl = 'http://h5.example.com'
        ..searchUrl = '/search'
        ..ruleSearch = jsonEncode({
          'bookList': r'$.KEYLIST[*]',
          'name': r'$.BOOKNAME',
          'bookUrl': r'''/book/h,{
  "charset": "UTF-8",
  "method": "POST",
  "body":"bID={{$.BOOKID}}"
}''',
        });
      final response = Response<dynamic>(
        data: jsonEncode({
          'KEYLIST': [
            {'BOOKID': 953528, 'BOOKNAME': '斗破苍穹'},
          ],
        }),
        requestOptions: RequestOptions(path: 'http://h5.example.com/search'),
        statusCode: 200,
      );

      final books = await LegadoParser.searchBooks(
        source,
        '斗破',
        preFetchedResponse: response,
      );

      expect(books, hasLength(1));
      expect(books.first.filePath, startsWith('http://h5.example.com/book/h,'));
      expect(books.first.filePath, contains('"body":"bID=953528"'));
      expect(books.first.filePath, isNot(contains('}"body"')));
    });

    test(
      'falls back to keyword-matched links when search selector misses',
      () async {
        final source = BookSource()
          ..bookSourceName = 'Search Fallback Source'
          ..bookSourceUrl = 'https://example.com'
          ..searchUrl = '/search?key={{key}}'
          ..ruleSearch = jsonEncode({
            'bookList': '.old-result',
            'name': 'a@text',
            'bookUrl': 'a@href',
          });
        final response = Response<dynamic>(
          data: '''
          <html><body>
            <div class="result-item">
              <a href="/book/12345/">Alpha Novel</a>
              <span>Author A</span>
            </div>
            <a href="/help">Help</a>
          </body></html>
        ''',
          statusCode: 200,
          requestOptions: RequestOptions(path: 'https://example.com/search'),
        );

        final books = await LegadoParser.searchBooks(
          source,
          'Alpha',
          preFetchedResponse: response,
        );

        expect(books, hasLength(1));
        expect(books.first.title, 'Alpha Novel');
        expect(books.first.filePath, 'https://example.com/book/12345/');
      },
    );

    test(
      'uses sibling book href when configured search href is inert',
      () async {
        final source = BookSource()
          ..bookSourceName = 'Inert Href Source'
          ..bookSourceUrl = 'https://example.com'
          ..searchUrl = '/search?key={{key}}'
          ..ruleSearch = jsonEncode({
            'bookList': '.novel-item',
            'name': '.title@text',
            'bookUrl': '.title@href',
          });
        final response = Response<dynamic>(
          data: '''
          <html><body>
            <div class="novel-item">
              <a class="title" href="javascript:void(0)">Alpha Novel</a>
              <a class="detail" href="/book/12345/">Read</a>
            </div>
          </body></html>
        ''',
          statusCode: 200,
          requestOptions: RequestOptions(path: 'https://example.com/search'),
        );

        final books = await LegadoParser.searchBooks(
          source,
          'Alpha',
          preFetchedResponse: response,
        );

        expect(books, hasLength(1));
        expect(books.first.filePath, 'https://example.com/book/12345/');
      },
    );

    test(
      'uses first plausible detail href when a search rule returns multiple hrefs',
      () async {
        final source = BookSource()
          ..bookSourceName = 'Multi Href Source'
          ..bookSourceUrl = 'https://example.com'
          ..searchUrl = '/search?key={{key}}'
          ..ruleSearch = jsonEncode({
            'bookList': '.bookbox',
            'name': '.bookname@text',
            'bookUrl': 'a@href',
          });
        final response = Response<dynamic>(
          data: '''
          <html><body>
            <div class="bookbox">
              <h4 class="bookname"><a href="/book/51841/">Alpha Novel</a></h4>
              <div class="update">
                <a href="/read/51841/13213185.html">Latest Chapter</a>
              </div>
            </div>
          </body></html>
        ''',
          statusCode: 200,
          requestOptions: RequestOptions(path: 'https://example.com/search'),
        );

        final books = await LegadoParser.searchBooks(
          source,
          'Alpha',
          preFetchedResponse: response,
        );

        expect(books, hasLength(1));
        expect(books.first.filePath, 'https://example.com/book/51841/');
      },
    );

    test('collapses repeated path groups in search book urls', () async {
      final source = BookSource()
        ..bookSourceName = 'Repeated Path Source'
        ..bookSourceUrl = 'https://example.com'
        ..searchUrl = '/search?key={{key}}'
        ..ruleSearch = jsonEncode({
          'bookList': '.item',
          'name': 'a@text',
          'bookUrl': 'a@href',
        });
      final response = Response<dynamic>(
        data: '''
          <html><body>
            <div class="item">
              <a href="/book/e3587891856ffc8c/book/e3587891856ffc8c/book/e3587891856ffc8c">Alpha Novel</a>
            </div>
          </body></html>
        ''',
        statusCode: 200,
        requestOptions: RequestOptions(path: 'https://example.com/search'),
      );

      final books = await LegadoParser.searchBooks(
        source,
        'Alpha',
        preFetchedResponse: response,
      );

      expect(books, hasLength(1));
      expect(books.first.filePath, 'https://example.com/book/e3587891856ffc8c');
    });

    test(
      'trims embedded absolute url pollution from search book urls',
      () async {
        final source = BookSource()
          ..bookSourceName = 'Embedded Url Source'
          ..bookSourceUrl = 'https://example.com'
          ..searchUrl = '/search?key={{key}}'
          ..ruleSearch = jsonEncode({
            'bookList': '.item',
            'name': 'a@text',
            'bookUrl': 'a@href',
          });
        final response = Response<dynamic>(
          data: '''
          <html><body>
            <div class="item">
              <a href="https://example.com/book/51841/https://example.com/read/51841/13213185.html">Alpha Novel</a>
            </div>
          </body></html>
        ''',
          statusCode: 200,
          requestOptions: RequestOptions(path: 'https://example.com/search'),
        );

        final books = await LegadoParser.searchBooks(
          source,
          'Alpha',
          preFetchedResponse: response,
        );

        expect(books, hasLength(1));
        expect(books.first.filePath, 'https://example.com/book/51841/');
      },
    );

    test('ignores placeholder search rows without a book url', () async {
      final source = BookSource()
        ..bookSourceName = 'Empty Search Row Source'
        ..bookSourceUrl = 'https://example.com'
        ..searchUrl = '/search?key={{key}}'
        ..ruleSearch = jsonEncode({
          'bookList': '#j li',
          'name': 'b@text',
          'bookUrl': 'a@href',
          'intro': 'p@text',
        });
      final response = Response<dynamic>(
        data: '''
          <html><body>
            <ul id="j">
              <li><p>抱歉，无相关作品……</p></li>
            </ul>
          </body></html>
        ''',
        statusCode: 200,
        requestOptions: RequestOptions(path: 'https://example.com/search'),
      );

      final books = await LegadoParser.searchBooks(
        source,
        'Alpha',
        preFetchedResponse: response,
      );

      expect(books, isEmpty);
    });

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

    test(
      'keeps embedded POST config out of request path and realUri',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final observed = <String>[];
        server.listen((request) async {
          final body = await utf8.decoder.bind(request).join();
          observed.add('${request.method} ${request.uri.path} $body');
          request.response.headers.contentType = ContentType.html;
          request.response.write('<html><body>ok</body></html>');
          await request.response.close();
        });

        final base = 'http://${server.address.host}:${server.port}';
        final source = BookSource()
          ..bookSourceName = 'POST Config Source'
          ..bookSourceUrl = base;
        final response = await LegadoParser.fetchHtml(
          source,
          '$base/search,{"method":"POST","body":"q={{key}}"}',
          keyword: '斗破苍穹',
        );

        expect(observed, [
          'POST /search q=%E6%96%97%E7%A0%B4%E8%8B%8D%E7%A9%B9',
        ]);
        expect(response.realUri.toString(), '$base/search');
      },
    );

    test('parses regex search lists with capture group field rules', () async {
      final source = BookSource()
        ..bookSourceName = 'Regex Search Source'
        ..bookSourceUrl = 'https://example.com'
        ..searchUrl = 'https://example.com/search?key={{key}}'
        ..ruleSearch = jsonEncode({
          'bookList':
              r':(?s)<li class="result">.*?<a href="([^"]+)">([^<]+)</a>.*?<span class="a">([^<]+)</span>.*?<img src="([^"]+)">.*?<span class="k">([^<]+)</span>.*?<span class="last">([^<]+)</span>',
          'name': r'$2',
          'bookUrl': r'$1',
          'author': r'$3',
          'coverUrl': r'$4',
          'kind': r'$5',
          'lastChapter': r'$6',
        });
      final response = Response<dynamic>(
        data: '''
          <li class="result">
            <a href="/book/1">Alpha</a>
            <span class="a">Tom</span>
            <img src="/cover/1.jpg">
            <span class="k">fantasy,done</span>
            <span class="last">Chapter 23</span>
          </li>
        ''',
        requestOptions: RequestOptions(path: 'https://example.com/search'),
        statusCode: 200,
      );

      final books = await LegadoParser.searchBooks(
        source,
        'alpha',
        preFetchedResponse: response,
      );

      expect(books, hasLength(1));
      expect(books.first.title, 'Alpha');
      expect(books.first.author, 'Tom');
      expect(books.first.filePath, 'https://example.com/book/1');
      expect(books.first.coverPath, 'https://example.com/cover/1.jpg');
      expect(books.first.tags, ['fantasy', 'done']);
      expect(books.first.totalChapters, 23);
    });

    test('reverses regex search lists with minus prefix', () async {
      final source = BookSource()
        ..bookSourceName = 'Reverse Regex Search Source'
        ..bookSourceUrl = 'https://example.com'
        ..searchUrl = 'https://example.com/search?key={{key}}'
        ..ruleSearch = jsonEncode({
          'bookList': r'-:<div data-url="([^"]+)">([^<]+)</div>',
          'name': r'$2',
          'bookUrl': r'$1',
        });
      final response = Response<dynamic>(
        data:
            '<div data-url="/book/1">First</div><div data-url="/book/2">Second</div>',
        requestOptions: RequestOptions(path: 'https://example.com/search'),
        statusCode: 200,
      );

      final books = await LegadoParser.searchBooks(
        source,
        'alpha',
        preFetchedResponse: response,
      );

      expect(books.map((book) => book.title), ['Second', 'First']);
      expect(books.map((book) => book.filePath), [
        'https://example.com/book/2',
        'https://example.com/book/1',
      ]);
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

    test('strips toc list direction prefixes', () async {
      final book = Book(
        title: 'Prefixed Toc',
        author: '',
        filePath: 'https://example.com/toc',
        fileType: 'online',
        isFromSource: true,
      );
      final response = Response<dynamic>(
        data:
            '<html><body><div class="toc"><a href="/c1">C1</a><a href="/c2">C2</a><a href="/c3">C3</a></div></body></html>',
        requestOptions: RequestOptions(path: book.filePath),
        statusCode: 200,
      );

      final forwardSource = BookSource()
        ..bookSourceName = 'Plus Toc Source'
        ..bookSourceUrl = 'https://example.com'
        ..ruleToc = jsonEncode({
          'chapterList': '+.toc a',
          'chapterName': '@text',
          'chapterUrl': '@href',
        });
      final reversedSource = BookSource()
        ..bookSourceName = 'Minus Toc Source'
        ..bookSourceUrl = 'https://example.com'
        ..ruleToc = jsonEncode({
          'chapterList': '-.toc a',
          'chapterName': '@text',
          'chapterUrl': '@href',
        });

      final forward = await LegadoParser.getChapterList(
        forwardSource,
        book,
        preFetchedResponse: response,
      );
      final reversed = await LegadoParser.getChapterList(
        reversedSource,
        book,
        preFetchedResponse: response,
      );

      expect(forward.map((chapter) => chapter.title), ['C1', 'C2', 'C3']);
      expect(reversed.map((chapter) => chapter.title), ['C3', 'C2', 'C1']);
    });

    test('parses regex toc lists with capture group rules', () async {
      final source = BookSource()
        ..bookSourceName = 'Regex Toc Source'
        ..bookSourceUrl = 'https://example.com'
        ..ruleToc = jsonEncode({
          'chapterList': r'-:f="([^"]+)" title="([^"]+)">',
          'chapterName': r'$2',
          'chapterUrl': r'$1',
        });
      final book = Book(
        title: 'Regex Toc',
        author: '',
        filePath: 'https://example.com/toc/',
        fileType: 'online',
        isFromSource: true,
      );
      final response = Response<dynamic>(
        data:
            '<a f="1.html" title="C1"></a><a f="2.html" title="C2"></a><a f="3.html" title="C3"></a>',
        requestOptions: RequestOptions(path: book.filePath),
        statusCode: 200,
      );

      final chapters = await LegadoParser.getChapterList(
        source,
        book,
        preFetchedResponse: response,
      );

      expect(chapters.map((chapter) => chapter.title), ['C3', 'C2', 'C1']);
      expect(chapters.map((chapter) => chapter.url), [
        'https://example.com/toc/3.html',
        'https://example.com/toc/2.html',
        'https://example.com/toc/1.html',
      ]);
    });

    test('parses regex toc item post processors and volume markers', () async {
      final source = BookSource()
        ..bookSourceName = 'Regex Volume Toc Source'
        ..bookSourceUrl = 'https://example.com'
        ..ruleToc = jsonEncode({
          'chapterList':
              r':("name":"(?!正文卷?)[^\n"]+","list":|"id":\d+,"name":"[^\n"]+","hasContent":1)',
          'chapterName': r'##"name":"([^\n"]+)"##$1###',
          'chapterUrl': r'##"id":(\d+)##$1.html###',
          'isVolume': r'##"list":##$0###',
        });
      final book = Book(
        title: 'Regex Volume Toc',
        author: '',
        filePath: 'https://example.com/book/',
        fileType: 'online',
        isFromSource: true,
      );
      final response = Response<dynamic>(
        data:
            '"name":"Volume 1","list":,"id":100,"name":"C1","hasContent":1,"id":101,"name":"C2","hasContent":1',
        requestOptions: RequestOptions(path: book.filePath),
        statusCode: 200,
      );

      final chapters = await LegadoParser.getChapterList(
        source,
        book,
        preFetchedResponse: response,
      );

      expect(chapters.map((chapter) => chapter.title), [
        'Volume 1',
        'C1',
        'C2',
      ]);
      expect(chapters.first.url, startsWith('volume://'));
      expect(chapters.skip(1).map((chapter) => chapter.url), [
        'https://example.com/book/100.html',
        'https://example.com/book/101.html',
      ]);
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

    test(
      'follows implicit read/catalog link when toc selector misses',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final requestedPaths = <String>[];
        server.listen((request) async {
          requestedPaths.add(request.uri.path);
          request.response.headers.contentType = ContentType.html;
          switch (request.uri.path) {
            case '/book':
              request.response.write('''
              <html><body>
                <a class="btn" href="/book/MainIndex/">点击阅读</a>
              </body></html>
            ''');
              break;
            case '/book/MainIndex/':
              request.response.write('''
              <div class="catalog-list">
                <a href="/c1">Chapter One</a>
                <a href="/c2">Chapter Two</a>
              </div>
            ''');
              break;
            default:
              request.response.statusCode = HttpStatus.notFound;
              request.response.write('');
          }
          await request.response.close();
        });

        final base = 'http://${server.address.host}:${server.port}';
        final source = BookSource()
          ..bookSourceName = 'Implicit Toc Source'
          ..bookSourceUrl = base
          ..ruleToc = jsonEncode({
            'chapterList': '.catalog-list a',
            'chapterName': '@text',
            'chapterUrl': '@href',
          });
        final book = Book(
          title: 'Implicit Toc Book',
          author: 'Author A',
          filePath: '$base/book',
          fileType: 'online',
          isFromSource: true,
        );

        final chapters = await LegadoParser.getChapterList(source, book);

        expect(chapters, hasLength(2));
        expect(chapters.first.title, 'Chapter One');
        expect(requestedPaths, ['/book', '/book/MainIndex/']);
      },
    );

    test(
      'skips broken toc pages and continues pending nextTocUrl queue',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          request.response.headers.contentType = ContentType.html;
          switch (request.uri.path) {
            case '/toc':
              request.response.write('''
              <div class="toc"><a href="/c1">Chapter 1</a></div>
              <div class="pages">
                <a href="/bad">bad</a>
                <a href="/toc3">3</a>
              </div>
            ''');
              break;
            case '/bad':
              request.response.statusCode = HttpStatus.internalServerError;
              request.response.write('Server Error');
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
          'Chapter 3',
        ]);
        expect(chapters.map((chapter) => chapter.url), [
          '$base/c1',
          '$base/c3',
        ]);
      },
    );

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

    test('loads toc from custom data url payloads', () async {
      if (!LegadoJsEngine().canEvaluate) return;
      final source = BookSource()
        ..bookSourceName = 'Data Toc Source'
        ..bookSourceUrl = 'https://example.com'
        ..ruleToc = jsonEncode({
          'chapterList': r'''@js:
var id = java.hexDecodeToString(result);
[
  {ChapterName: "第一章", chapterUrl: "/read/" + id + "/1"},
  {ChapterName: "第二章", chapterUrl: "/read/" + id + "/2"}
];''',
          'chapterName': 'ChapterName',
          'chapterUrl': 'chapterUrl',
        });
      final book = Book(
        title: 'Data Toc',
        author: '',
        filePath: 'data:bookId;base64,MTIwOTk3Nw==,{"type":"ywc"}',
        fileType: 'online',
        isFromSource: true,
      );

      final chapters = await LegadoParser.getChapterList(source, book);

      expect(chapters.map((chapter) => chapter.title), ['第一章', '第二章']);
      expect(chapters.map((chapter) => chapter.url), [
        'https://example.com/read/1209977/1',
        'https://example.com/read/1209977/2',
      ]);
    });

    test('passes toc baseUrl variables into json template js rules', () async {
      if (!LegadoJsEngine().canEvaluate) return;
      final source = BookSource()
        ..bookSourceName = 'Json Toc JS Source'
        ..bookSourceUrl = 'https://example.com'
        ..ruleToc = jsonEncode({
          'chapterList': r'$.data.list[*]',
          'chapterName': r'''第{{$.order}}章 {{$.name}}
<js>
vol = "{{$.type}}"=="volume"?" 📖 ":""
vol+result+vol
</js>
##第章\s*|第\d+章\s*(?=第\d+章)''',
          'chapterUrl': r'''<js>
var nid = baseUrl.match(/nid=.*/)[0].replace("nid=","")
var ids = "{{$.id}}"
var url = "https://api.example.com/read?nid="+nid+"&chapter_ids="+ids
result = url
</js>
@js:
"{{$.type}}"=="volume"?"":result''',
          'isVolume': r'''<js>
"{{$.type}}"=="volume"?true:false
</js>''',
        });
      final book = Book(
        title: 'Json Toc JS',
        author: '',
        filePath: 'https://example.com/api/toc?nid=1404068',
        fileType: 'online',
        isFromSource: true,
      );
      final response = Response<dynamic>(
        data: jsonEncode({
          'data': {
            'list': [
              {'order': '', 'name': '正文', 'type': 'volume', 'id': 'v1'},
              {'order': 1, 'name': '第一章', 'type': 'chapter', 'id': 'c1'},
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

      expect(chapters, hasLength(2));
      expect(chapters.first.title, '📖 第章 正文 📖');
      expect(
        chapters.first.url,
        'volume://https://example.com/api/toc?nid=1404068#0',
      );
      expect(
        chapters.last.url,
        'https://api.example.com/read?nid=1404068&chapter_ids=c1',
      );
    });

    test('parses toc when chapterList is a js-generated list', () async {
      if (!LegadoJsEngine().canEvaluate) return;
      final source = BookSource()
        ..bookSourceName = 'HTML JS Toc Source'
        ..bookSourceUrl = 'https://example.com'
        ..ruleToc = jsonEncode({
          'chapterList': r'''@js:
var list = [];
var re = /href="([^"]+)">([^<]+)<\/a>/g;
var m;
while ((m = re.exec(result)) != null) {
  list.push({k:m[2], v:m[1]});
}
list;''',
          'chapterName': 'k',
          'chapterUrl': 'v',
        });
      final book = Book(
        title: 'HTML JS Toc',
        author: '',
        filePath: 'https://example.com/toc',
        fileType: 'online',
        isFromSource: true,
      );
      final response = Response<dynamic>(
        data: '<a href="/c/1/">第一章</a><a href="/c/2/">第二章</a>',
        requestOptions: RequestOptions(path: book.filePath),
        statusCode: 200,
      );

      final chapters = await LegadoParser.getChapterList(
        source,
        book,
        preFetchedResponse: response,
      );

      expect(chapters.map((chapter) => chapter.title), ['第一章', '第二章']);
      expect(chapters.map((chapter) => chapter.url), [
        'https://example.com/c/1/',
        'https://example.com/c/2/',
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

    test('uses book context variables for detail toc url templates', () async {
      final source = BookSource()
        ..bookSourceName = 'Book Context Detail Source'
        ..bookSourceUrl = 'https://example.com'
        ..ruleBookInfo = jsonEncode({
          'name': 'h1@text',
          'tocUrl': '{{book.bookUrl}}/catalog',
        });
      final book = Book(
        title: 'Original Name',
        author: 'Author',
        filePath: 'https://example.com/book/1',
        fileType: 'online',
        isFromSource: true,
      );
      final response = Response<dynamic>(
        data: '<h1>Resolved Name</h1>',
        requestOptions: RequestOptions(path: book.filePath),
        statusCode: 200,
      );

      final detail = await LegadoParser.parseBookInfo(
        source,
        book,
        preFetchedResponse: response,
      );

      expect(detail.title, 'Resolved Name');
      expect(detail.filePath, 'https://example.com/book/1/catalog');
    });

    test('follows toc url templates with book context', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requested = <String>[];
      server.listen((request) async {
        requested.add(request.uri.path);
        request.response.headers.contentType = ContentType.html;
        if (request.uri.path == '/book/1/catalog') {
          request.response.write('<a href="/c1">Chapter One</a>');
        } else {
          request.response.write('<html><body>detail</body></html>');
        }
        await request.response.close();
      });

      final base = 'http://${server.address.host}:${server.port}';
      final source = BookSource()
        ..bookSourceName = 'Book Context Toc Source'
        ..bookSourceUrl = base
        ..ruleToc = jsonEncode({
          'tocUrl': '{{book.bookUrl}}/catalog',
          'chapterList': 'a',
          'chapterName': 'text',
          'chapterUrl': 'href',
        });
      final book = Book(
        title: 'Demo Book',
        author: '',
        filePath: '$base/book/1',
        fileType: 'online',
        isFromSource: true,
      );

      final chapters = await LegadoParser.getChapterList(source, book);

      expect(requested, ['/book/1', '/book/1/catalog']);
      expect(chapters, hasLength(1));
      expect(chapters.first.title, 'Chapter One');
      expect(chapters.first.url, '$base/c1');
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

    test('ignores inert javascript urls from nextContentUrl', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requestedPaths = <String>[];
      server.listen((request) async {
        requestedPaths.add(request.uri.path);
        request.response.headers.contentType = ContentType.html;
        request.response.write('''
          <div id="content"><p>Only page</p></div>
          <div class="pages">
            <a href="javascript:alert('no more')">Next</a>
          </div>
        ''');
        await request.response.close();
      });

      final base = 'http://${server.address.host}:${server.port}';
      final source = BookSource()
        ..bookSourceName = 'Inert Next Content Source'
        ..bookSourceUrl = base
        ..ruleContent = jsonEncode({
          'content': '#content@html',
          'nextContentUrl': '.pages a@href',
        });

      final content = await LegadoParser.getChapterContent(source, '$base/c1');

      expect(content, contains('Only page'));
      expect(requestedPaths, ['/c1']);
    });

    test(
      'uses safe next-page fallback when nextContentUrl is absent',
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
              <a href="/c1_2">下一页</a>
              <a href="/c2">下一章</a>
            ''');
              break;
            case '/c1_2':
              request.response.write('<div id="content"><p>Part 2</p></div>');
              break;
            default:
              request.response.statusCode = HttpStatus.notFound;
              request.response.write('');
          }
          await request.response.close();
        });

        final base = 'http://${server.address.host}:${server.port}';
        final source = BookSource()
          ..bookSourceName = 'Fallback Paged Content Source'
          ..bookSourceUrl = base
          ..ruleContent = jsonEncode({'content': '#content@html'});

        final content = await LegadoParser.getChapterContent(
          source,
          '$base/c1',
        );

        expect(content, contains('Part 1'));
        expect(content, contains('Part 2'));
        expect(requestedPaths, ['/c1', '/c1_2']);
      },
    );

    test(
      'skips broken content pages and continues pending nextContentUrl queue',
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
                <a href="/broken">2</a>
                <a href="/c1p3">3</a>
              </div>
            ''');
              break;
            case '/broken':
              request.response.statusCode = HttpStatus.internalServerError;
              request.response.write('Server Error');
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
          ..bookSourceName = 'Broken Paged Content Source'
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
        expect(content, contains('Part 3'));
        expect(requestedPaths, ['/c1', '/broken', '/c1p3']);
      },
    );

    test('uses book and chapter context variables for content rules', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requested = <String>[];
      server.listen((request) async {
        requested.add(request.uri.toString());
        request.response.headers.contentType = ContentType.html;
        if (request.uri.queryParameters['page'] == '2') {
          request.response.write('<div id="content"><p>Demo Tail</p></div>');
        } else {
          request.response.write(
            '<div id="content"><p>Demo Book Intro</p><p>Demo Body</p></div>',
          );
        }
        await request.response.close();
      });

      final base = 'http://${server.address.host}:${server.port}';
      final source = BookSource()
        ..bookSourceName = 'Context Content Source'
        ..bookSourceUrl = base
        ..ruleContent = jsonEncode({
          'content': '#content@text',
          'nextContentUrl': '{{chapter.url}}?page=2',
          'replaceRegex': '##{{book.name}}\\s*##',
        });
      final book = Book(
        title: 'Demo Book',
        author: '',
        filePath: '$base/book/1',
        fileType: 'online',
        isFromSource: true,
      );
      final chapter = Chapter(
        bookId: 1,
        title: 'Chapter 1',
        index: 0,
        url: '$base/c1',
        content: '$base/c1',
      );

      final content = await LegadoParser.getChapterContent(
        source,
        chapter.url!,
        book: book,
        chapter: chapter,
      );

      expect(content, contains('Intro'));
      expect(content, contains('Body'));
      expect(content, contains('Tail'));
      expect(content, isNot(contains('Demo Book')));
      expect(requested, ['/c1', '/c1?page=2']);
    });

    test(
      'testSource passes book and chapter context into content rules',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          request.response.headers.contentType = ContentType.html;
          switch (request.uri.path) {
            case '/search':
              request.response.write('''
              <div class="book">
                <a href="/book"><span class="title">Demo Book</span></a>
              </div>
            ''');
              break;
            case '/book':
              request.response.write('''
              <div class="toc">
                <a class="chapter" href="/chapter">ChapterOne</a>
              </div>
            ''');
              break;
            case '/chapter':
              request.response.write(
                "<div id=\"ChapterOne\">${List.filled(12, 'Context Body').join(' ')}</div>",
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
          ..bookSourceName = 'Context Test Source'
          ..bookSourceUrl = base
          ..searchUrl = '/search?q={{key}}'
          ..ruleSearch = jsonEncode({
            'bookList': '.book',
            'name': '.title@text',
            'bookUrl': 'a@href',
          })
          ..ruleToc = jsonEncode({
            'chapterList': '.chapter',
            'chapterName': '@text',
            'chapterUrl': '@href',
          })
          ..ruleContent = jsonEncode({'content': '#{{chapter.title}}@text'});

        final report = await LegadoParser.testSource(source, 'demo');
        final contentStep = report.steps.lastWhere(
          (step) => step.title == '正文',
        );

        expect(contentStep.status, LegadoStepStatus.ok);
        expect(contentStep.sample, contains('Context Body'));
      },
    );

    test(
      'testSource tries later chapters when first content is unavailable',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final requestedPaths = <String>[];
        server.listen((request) async {
          requestedPaths.add(request.uri.path);
          request.response.headers.contentType = ContentType.html;
          switch (request.uri.path) {
            case '/search':
              request.response.write('''
              <div class="book">
                <a href="/book"><span class="title">Demo Book</span></a>
              </div>
            ''');
              break;
            case '/book':
              request.response.write('''
              <div class="toc">
                <a class="chapter" href="/c1">Chapter One</a>
                <a class="chapter" href="/c2">Chapter Two</a>
              </div>
            ''');
              break;
            case '/c1':
              request.response.write(
                '<div class="error">Content unavailable</div>',
              );
              break;
            case '/c2':
              request.response.write(
                "<div id=\"content\">${List.filled(20, 'Readable second chapter body').join(' ')}</div>",
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
          ..bookSourceName = 'Later Chapter Test Source'
          ..bookSourceUrl = base
          ..searchUrl = '/search?q={{key}}'
          ..ruleSearch = jsonEncode({
            'bookList': '.book',
            'name': '.title@text',
            'bookUrl': 'a@href',
          })
          ..ruleToc = jsonEncode({
            'chapterList': '.chapter',
            'chapterName': '@text',
            'chapterUrl': '@href',
          })
          ..ruleContent = jsonEncode({'content': '#content@text'});

        final report = await LegadoParser.testSource(source, 'demo');

        expect(report.hasFailure, isFalse);
        expect(requestedPaths, contains('/c1'));
        expect(requestedPaths, contains('/c2'));
      },
    );

    test(
      'testSource uses a keyword-matching result instead of first noise item',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final requestedPaths = <String>[];
        server.listen((request) async {
          requestedPaths.add(request.uri.path);
          request.response.headers.contentType = ContentType.html;
          switch (request.uri.path) {
            case '/search':
              request.response.write('''
              <div class="book"><a href="/broken-book"><span class="title">广告入口</span></a></div>
              <div class="book"><a href="/book"><span class="title">斗破苍穹</span></a></div>
            ''');
              break;
            case '/broken-book':
              request.response.write('<div class="empty">no chapters</div>');
              break;
            case '/book':
              request.response.write('''
              <div class="toc">
                <a class="chapter" href="/chapter">第一章</a>
              </div>
            ''');
              break;
            case '/chapter':
              request.response.write(
                "<div id=\"content\">${List.filled(50, '正文内容').join('，')}</div>",
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
          ..bookSourceName = 'Keyword Candidate Source'
          ..bookSourceUrl = base
          ..searchUrl = '/search?q={{key}}'
          ..ruleSearch = jsonEncode({
            'bookList': '.book',
            'name': '.title@text',
            'bookUrl': 'a@href',
          })
          ..ruleToc = jsonEncode({
            'chapterList': '.chapter',
            'chapterName': '@text',
            'chapterUrl': '@href',
          })
          ..ruleContent = jsonEncode({'content': '#content@text'});

        final report = await LegadoParser.testSource(source, '斗破苍穹');

        expect(report.hasFailure, isFalse);
        expect(requestedPaths, contains('/book'));
        expect(requestedPaths, isNot(contains('/broken-book')));
        final searchStep = report.steps.firstWhere(
          (step) => step.title == '搜索结果',
        );
        expect(searchStep.sample, contains('斗破苍穹'));
      },
    );

    test('testSource prefers ruleSearch.checkKeyWord for probing', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      String? receivedKeyword;
      server.listen((request) async {
        request.response.headers.contentType = ContentType.html;
        switch (request.uri.path) {
          case '/search':
            receivedKeyword = request.uri.queryParameters['q'];
            if (receivedKeyword == '道观') {
              request.response.write('''
              <div class="book"><a href="/book"><span class="title">道观</span></a></div>
            ''');
            } else {
              request.response.write('<div class="empty"></div>');
            }
            break;
          case '/book':
            request.response.write('''
              <div class="toc">
                <a class="chapter" href="/chapter">第一章</a>
              </div>
            ''');
            break;
          case '/chapter':
            request.response.write(
              "<div id=\"content\">${List.filled(50, '正文内容').join('，')}</div>",
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
        ..bookSourceName = 'Check Keyword Source'
        ..bookSourceUrl = base
        ..searchUrl = '/search?q={{key}}'
        ..ruleSearch = jsonEncode({
          'bookList': '.book',
          'name': '.title@text',
          'bookUrl': 'a@href',
          'checkKeyWord': '道观',
        })
        ..ruleToc = jsonEncode({
          'chapterList': '.chapter',
          'chapterName': '@text',
          'chapterUrl': '@href',
        })
        ..ruleContent = jsonEncode({'content': '#content@text'});

      final report = await LegadoParser.testSource(source, '斗破苍穹');

      expect(report.hasFailure, isFalse);
      expect(receivedKeyword, '道观');
      expect(
        report.steps.first.logs.join('\n'),
        contains('ruleSearch.checkKeyWord'),
      );
    });

    test('follows content url templates with chapter context', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requested = <String>[];
      server.listen((request) async {
        requested.add(request.uri.path);
        request.response.headers.contentType = ContentType.html;
        if (request.uri.path == '/c1/real') {
          request.response.write('<div id="content">Resolved Body</div>');
        } else {
          request.response.write('<html><body>stub</body></html>');
        }
        await request.response.close();
      });

      final base = 'http://${server.address.host}:${server.port}';
      final source = BookSource()
        ..bookSourceName = 'Chapter Context Content Url Source'
        ..bookSourceUrl = base
        ..ruleContent = jsonEncode({
          'contentUrl': '{{chapter.url}}/real',
          'content': '#content@text',
        });
      final book = Book(
        title: 'Demo Book',
        author: '',
        filePath: '$base/book/1',
        fileType: 'online',
        isFromSource: true,
      );
      final chapter = Chapter(
        bookId: 1,
        title: 'Chapter 1',
        index: 0,
        url: '$base/c1',
        content: '$base/c1',
      );

      final content = await LegadoParser.getChapterContent(
        source,
        chapter.url!,
        book: book,
        chapter: chapter,
      );

      expect(requested, ['/c1', '/c1/real']);
      expect(content, 'Resolved Body');
    });

    test(
      'exposes chapter title to multiline content js postprocessor',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((request) async {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'data': {'content': 'Chapter 1 ACTUAL CONTENT'},
            }),
          );
          await request.response.close();
        });

        final base = 'http://${server.address.host}:${server.port}';
        final source = BookSource()
          ..bookSourceName = 'Chapter JS Context Source'
          ..bookSourceUrl = base
          ..ruleContent = jsonEncode({
            'content': r'''$.data.content
<js>
a=String(chapter.title).replace(/\s/g,"");
result.substring(0,90).includes(a)?result=result.split(a,2)[1]:result;
result.toLowerCase()
</js>''',
          });
        final book = Book(
          title: 'Demo Book',
          author: '',
          filePath: '$base/book/1',
          fileType: 'online',
          isFromSource: true,
        );
        final chapter = Chapter(
          bookId: 1,
          title: 'Chapter 1',
          index: 0,
          url: '$base/c1',
          content: '$base/c1',
        );

        final content = await LegadoParser.getChapterContent(
          source,
          chapter.url!,
          book: book,
          chapter: chapter,
        );

        expect(content, 'actual content');
      },
    );

    test('keeps embedded request config from templated nextContentUrl', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final observed = <String>[];
      server.listen((request) async {
        observed.add('${request.method} ${request.uri.path}');
        request.response.headers.contentType = ContentType.html;
        switch (request.uri.path) {
          case '/c1':
            request.response.write('''
                <div id="content"><p>Part 1</p></div>
                <a class="PagesLink" href="/c1p2">next</a>
              ''');
            break;
          case '/c1p2':
            request.response.write('<div id="content"><p>Part 2</p></div>');
            break;
          default:
            request.response.statusCode = HttpStatus.notFound;
            request.response.write('');
        }
        await request.response.close();
      });

      final base = 'http://${server.address.host}:${server.port}';
      final source = BookSource()
        ..bookSourceName = 'Templated Paged Content Source'
        ..bookSourceUrl = base
        ..ruleContent = jsonEncode({
          'content': '#content@html',
          'nextContentUrl':
              '{{@css:a.PagesLink @href}},{"method":"POST","body":"from=next"}',
        });

      final content = await LegadoParser.getChapterContent(source, '$base/c1');

      expect(content, contains('Part 1'));
      expect(content, contains('Part 2'));
      expect(observed, ['GET /c1', 'POST /c1p2']);
    });

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

    test('supports global html helper functions', () {
      if (!LegadoJsEngine().canEvaluate) return;
      const html = '''
<div class="book"><a href="/b1"><span class="title">Book One</span></a></div>
<div class="book"><a href="/b2"><span class="title">Book Two</span></a></div>
''';

      final value = LegadoJsEngine().evaluate(
        r'''@js:JSON.stringify({
  count: select(result, ".book").length,
  firstTitle: selectFirst(result, ".title"),
  href: getAttr(result, ".book a", "href"),
  cleaned: clean("<p>A</p><p>B</p>")
})''',
        variables: {'result': html},
      );
      final decoded = jsonDecode(value) as Map<String, dynamic>;

      expect(decoded['count'], 2);
      expect(decoded['firstTitle'], 'Book One');
      expect(decoded['href'], '/b1');
      expect(decoded['cleaned'], 'A\nB');
    });

    test('supports global MR style helper aliases', () {
      if (!LegadoJsEngine().canEvaluate) return;
      final value = LegadoJsEngine().evaluate(r'''@js:
put("token", "abc");
JSON.stringify({
  token: getStr("token"),
  md5: md5Encode("abc"),
  sha256: sha256Encode("abc"),
  b64: base64Decode(base64Encode("hello")),
  ua: getWebViewUA().indexOf("Mozilla") >= 0
})''');
      final decoded = jsonDecode(value) as Map<String, dynamic>;

      expect(decoded['token'], 'abc');
      expect(decoded['md5'], '900150983cd24fb0d6963f7d28e17f72');
      expect(
        decoded['sha256'],
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(decoded['b64'], 'hello');
      expect(decoded['ua'], isTrue);
    });

    test('supports java jsoup namespace and content rule overloads', () {
      if (!LegadoJsEngine().canEvaluate) return;
      const html = '''
<div class="book"><a href="/b1"><span class="title">Book One</span></a></div>
<div class="book"><a href="/b2"><span class="title">Book Two</span></a></div>
''';

      final value = LegadoJsEngine().evaluate(
        r'''@js:JSON.stringify({
  title: java.jsoup.selectFirst(result, ".title"),
  href: java.jsoup.getAttr(result, ".book a", "href"),
  text: java.getString(result, ".book@text"),
  links: java.getStringList(result, ".book a@href")
})''',
        variables: {'result': html},
      );
      final decoded = jsonDecode(value) as Map<String, dynamic>;

      expect(decoded['title'], 'Book One');
      expect(decoded['href'], '/b1');
      expect(decoded['text'], 'Book One\nBook Two');
      expect(decoded['links'], ['/b1', '/b2']);
    });

    test('supports java regex and utility aliases', () {
      if (!LegadoJsEngine().canEvaluate) return;
      final value = LegadoJsEngine().evaluate(r'''@js:
var data = java.getJson('{"a":1}');
java.putJson("json", {b:2});
JSON.stringify({
  a: data.a,
  stored: java.getStr("json"),
  hex: java.hexDecodeToString(java.hexEncodeToString("abc")),
  bytes: java.bytesToStr(java.strToBytes("abc")),
  replaced: java.regex.replace("A12B34", "\\d+", "#"),
  matches: java.regex.matchAll("A12B34", "\\d+"),
  tested: java.regex.test("A12", "\\d+"),
  hmac: java.hmacSHA256("abc", "key")
})''');
      final decoded = jsonDecode(value) as Map<String, dynamic>;

      expect(decoded['a'], 1);
      expect(decoded['stored'], '{"b":2}');
      expect(decoded['hex'], 'abc');
      expect(decoded['bytes'], 'abc');
      expect(decoded['replaced'], 'A#B#');
      expect(decoded['matches'], ['12', '34']);
      expect(decoded['tested'], isTrue);
      expect(decoded['hmac'], isNotEmpty);
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

    test('supports org.jsoup.Jsoup connect ajax chain', () async {
      if (!LegadoJsEngine().isAvailable) return;
      final output = await LegadoJsEngine().evaluateWithAjax(
        r'''@js:
var doc = org.jsoup.Jsoup.connect("https://api.example/search")
  .requestBody("{\"key\":\"abc\"}")
  .header("Content-Type", "application/json")
  .ignoreContentType(true)
  .post();
JSON.parse(String(doc).match(/body>\s*(.*)\s*<\/bo/)[1]).data.rows[0].name;
''',
        ajax: (request) async {
          expect(request, contains('https://api.example/search'));
          expect(request, contains('"method":"POST"'));
          expect(request, contains('"body":"{\\"key\\":\\"abc\\"}"'));
          return '{"data":{"rows":[{"name":"Book"}]}}';
        },
      );

      expect(output, 'Book');
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

    test('exposes jsoup arrays as element wrappers in js bridge', () {
      if (!LegadoJsEngine().isAvailable) return;
      final html = '''
<div class="book"><a href="/b1">Book One</a></div>
<div class="book"><a href="/b2">Book Two</a></div>
''';

      final mapped = LegadoJsEngine().evaluate(
        r'''@js:
java.getElements(".book").toArray().map(function(el) {
  return el.select("a").attr("href") + ":" + el.text();
}).join("|");
''',
        variables: {'result': html},
      );
      final forIn = LegadoJsEngine().evaluate(
        r'''@js:
var nodes = java.getElements(".book");
var out = [];
for (var i in nodes) {
  out.push(nodes[i].select("a").attr("href"));
}
out.join(",");
''',
        variables: {'result': html},
      );

      expect(mapped, '/b1:Book One|/b2:Book Two');
      expect(forIn, '/b1,/b2');
    });

    test('supports jsoup dom mutation helpers in js bridge', () {
      if (!LegadoJsEngine().isAvailable) return;
      final cleaned = LegadoJsEngine().evaluate(
        r'''@js:
var doc = org.jsoup.Jsoup.parse(result).select(".novelText");
doc.select("[style]").remove();
doc.html();
''',
        variables: {
          'result':
              '<div class="novelText"><p>A</p><p style="display:none">ADS</p><p>B</p></div>',
        },
      );
      final inserted = LegadoJsEngine().evaluate(r'''@js:
var doc = org.jsoup.Jsoup.parse('<ul><li id="x">X</li></ul>');
doc.select("#x").before("<li>A</li>").remove();
doc.select("li").text();
''');
      final hasClass = LegadoJsEngine().evaluate(
        r'''@js:org.jsoup.Jsoup.parse('<a class="vip lock">C</a>').select("a").hasClass("vip")''',
      );
      final imported = LegadoJsEngine().evaluate(r'''@js:
importClass(org.jsoup.Jsoup);
var doc = Jsoup.parse('<body><p class="non">卷一</p><p>A</p><p>B</p></body>');
doc.select("p").eachText().join("|") + "::" + doc.body().text();
''');
      final children = LegadoJsEngine().evaluate(r'''@js:
var el = org.jsoup.Jsoup.parse('<div><span>A</span><b>B</b></div>').select("div");
el.child(1).text() + "::" + el.children().size();
''');
      final htmlParts = LegadoJsEngine().evaluate(r'''@js:
var el = org.jsoup.Jsoup.parse('<div><span>A</span></div>').select("div");
el.html() + "::" + String(el);
''');
      final list = LegadoJsEngine().evaluate(r'''@js:
var list = new Packages.util.ArrayList();
list.add("A");
list.add("B");
list.join(",");
''');
      final textNodes = LegadoJsEngine().evaluate(r'''@js:
var doc = org.jsoup.Jsoup.parse('<div id="intro">Lead <span>Skip</span> Tail</div>');
doc.selectFirst("#intro").textNodes().toArray().join("|");
''');

      expect(cleaned, contains('A'));
      expect(cleaned, contains('B'));
      expect(cleaned, isNot(contains('ADS')));
      expect(inserted, 'A');
      expect(hasClass, 'true');
      expect(imported, startsWith('卷一|A|B::'));
      expect(imported, contains('卷一'));
      expect(children, 'B::2');
      expect(htmlParts, '<span>A</span>::<div><span>A</span></div>');
      expect(list, 'A,B');
      expect(textNodes, 'Lead|Tail');
    });

    test('supports jsoup parent and index helpers in js bridge', () {
      if (!LegadoJsEngine().isAvailable) return;
      final value = LegadoJsEngine().evaluate(r'''@js:
var doc = org.jsoup.Jsoup.parse('<body><div class="vol"><p class="vip">V</p><p id="c">C</p></div></body>');
var selected = doc.select("#c");
[
  selected.parentNode().className(),
  selected.parentNode().selectFirst(".vip").text(),
  doc.select("p").eq(-1).id(),
  doc.select("p").get(-2).className(),
  doc.select("p").last().tagName()
].join("|");
''');

      expect(value, 'vol|V|c|vip|p');
    });

    test('supports java android compatibility shims in js bridge', () async {
      if (!LegadoJsEngine().isAvailable) return;

      final gbkBytes = LegadoJsEngine().evaluate(
        r'''@js:Packages.java.lang.String("\u4e2d").getBytes("gb2312").map(function(x) {
  return "%" + (x & 0xff).toString(16).toUpperCase();
}).join("")''',
      );
      final base64 = LegadoJsEngine().evaluate(
        r'''@js:String(Packages.java.lang.String(android.util.Base64.encode(Packages.java.lang.String("abc").getBytes(), 2)))''',
      );
      final decoded = LegadoJsEngine().evaluate(
        r'''@js:java.base64Decoder("SGVsbG8=")''',
      );
      final aliases = LegadoJsEngine().evaluate(r'''@js:
var javaImport = new JavaImporter(
  Packages.java.lang.Integer,
  Packages.java.lang.Long,
  Packages.java.net.URLEncoder,
  Packages.android.util.Base64
);
with (javaImport) {
  [
    Integer.parseInt("10"),
    Long.parseLong("11"),
    URLEncoder.encode("a b", "UTF-8"),
    URLDecoder.decode("a%20b", "UTF-8"),
    Base64.encodeToString(String("x").getBytes(), Base64.NO_WRAP)
  ].join("|");
}
''');
      final fetched = await LegadoJsEngine().evaluateWithAjax(
        r'''@js:java.fetch("https://example.test/api", {method:"post", body:"a=1"}).body().string()''',
        ajax: (request) async {
          expect(request, contains('https://example.test/api'));
          expect(request, contains('"body":"a=1"'));
          return '{"ok":true}';
        },
      );
      final posted = await LegadoJsEngine().evaluateWithAjax(
        r'''@js:java.postForm("https://example.test/form", "q=1")''',
        ajax: (request) async {
          expect(request, contains('https://example.test/form'));
          expect(
            request,
            contains('"Content-Type":"application/x-www-form-urlencoded"'),
          );
          return 'posted';
        },
      );

      expect(gbkBytes, '%D6%D0');
      expect(base64, 'YWJj');
      expect(decoded, 'Hello');
      expect(aliases, '10|11|a%20b|a b|eA==');
      expect(fetched, '{"ok":true}');
      expect(posted, 'posted');
    });

    test('supports java aes and des base64 decode argument order', () {
      if (!LegadoJsEngine().isAvailable) return;
      final aes = LegadoJsEngine().evaluate(
        r'''@js:java.aesBase64DecodeToString("ZM6V+N4TrIblhrpN+FfkYw==", "1234567890123456", "AES/CBC/PKCS5Padding", "abcdefghijklmnop")''',
      );
      final des = LegadoJsEngine().evaluate(
        r'''@js:java.aesBase64DecodeToString("0XUfPCehJ3Q=", "6CB1E21E", "DES/CBC/PKCS5Padding", "1F0FB845")''',
      );

      expect(aes, 'hello');
      expect(des, 'hello');
    });

    test('supports CryptoJS AES and DES decrypt shims', () {
      if (!LegadoJsEngine().isAvailable) return;
      final aes = LegadoJsEngine().evaluate(r'''@js:
var key = CryptoJS.enc.Utf8.parse("1234567890123456");
var iv = CryptoJS.enc.Utf8.parse("abcdefghijklmnop");
CryptoJS.AES.decrypt("ZM6V+N4TrIblhrpN+FfkYw==", key, {
  iv: iv,
  mode: CryptoJS.mode.CBC,
  padding: CryptoJS.pad.Pkcs7
}).toString(CryptoJS.enc.Utf8);
''');
      final des = LegadoJsEngine().evaluate(r'''@js:
CryptoJS.DES.decrypt("0XUfPCehJ3Q=", CryptoJS.enc.Utf8.parse("6CB1E21E"), {
  iv: CryptoJS.enc.Utf8.parse("1F0FB845"),
  mode: CryptoJS.mode.CBC,
  padding: CryptoJS.pad.Pkcs7
}).toString(CryptoJS.enc.Utf8);
''');

      expect(aes, 'hello');
      expect(des, 'hello');
    });

    test('supports JavaImporter AES byte decrypt and inflater shims', () {
      if (!LegadoJsEngine().isAvailable) return;
      final decoded = LegadoJsEngine().evaluate(
        r'''@js:
var javaImport = new JavaImporter();
javaImport.importPackage(
  Packages.java.lang,
  Packages.javax.crypto,
  Packages.javax.crypto.spec,
  Packages.java.io,
  Packages.java.util,
  Packages.java.util.zip
);
with (javaImport) {
  function decrypt(str) {
    var bytes = java.aesBase64DecodeToByteArray(
      str,
      "Shuew237HSFH242s",
      "AES/CBC/PKCS5Padding",
      "abcdefghijklmnop"
    );
    var inflaterInputStream = new InflaterInputStream(new ByteArrayInputStream(bytes));
    var byteArrayOutputStream = new ByteArrayOutputStream(512);
    while (true) {
      var read = inflaterInputStream.read();
      if (read != -1) {
        byteArrayOutputStream.write(read);
      } else {
        byteArrayOutputStream.close();
        return byteArrayOutputStream.toString();
      }
    }
  }
}
decrypt(result);
''',
        variables: {'result': '9XGKV+gLPbg9nhpsZ/+4AvfGGarQ3vqnSbYUtZx29vU='},
      );

      expect(decoded, 'hello inflater');
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
        expect(report.steps.first.message, contains('JS 搜索 URL 执行失败'));
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

  group('SimpleJsExpressionEvaluator', () {
    test('evaluates simple string concatenation with variables', () async {
      final source = BookSource()
        ..bookSourceName = 'Test Qbxsw'
        ..bookSourceType = 0
        ..bookSourceUrl = 'https://www.qbxsw.com';
      final url = await LegadoParser.buildSearchUrl(
        source
          ..searchUrl =
              '@js:"https://www.qbxsw.com/search.html?searchkey=" + encodeURIComponent(key)',
        '斗破苍穹',
      );
      expect(
        url,
        'https://www.qbxsw.com/search.html?searchkey=%E6%96%97%E7%A0%B4%E8%8B%8D%E7%A9%B9',
      );
    });

    test('evaluates variable assignment and multiple statements', () async {
      final source = BookSource()
        ..bookSourceName = 'Test Variable Assignment'
        ..bookSourceType = 0
        ..bookSourceUrl = 'https://www.qbxsw.com';
      final url = await LegadoParser.buildSearchUrl(
        source
          ..searchUrl = r'''
            @js:
            var path = "/search.html?searchkey=";
            var full = baseUrl + path + encodeURIComponent(key) + "&page=" + page;
            full;
          ''',
        '斗破苍穹',
        page: 2,
      );
      expect(
        url,
        'https://www.qbxsw.com/search.html?searchkey=%E6%96%97%E7%A0%B4%E8%8B%8D%E7%A9%B9&page=2',
      );
    });

    test('evaluates java.encodeURI with gbk and simple arithmetic', () async {
      final source = BookSource()
        ..bookSourceName = 'Test GBK'
        ..bookSourceType = 0
        ..bookSourceUrl = 'http://a.lc1001.com';
      final url = await LegadoParser.buildSearchUrl(
        source
          ..searchUrl = r'''
            @js:
            var gbkKey = java.encodeURI(key, "gbk");
            var pn = (page - 1) * 20;
            baseUrl + "/query?kw=" + gbkKey + "&pn=" + pn;
          ''',
        '斗破',
        page: 3,
      );
      expect(url, 'http://a.lc1001.com/query?kw=%B6%B7%C6%C6&pn=40');
    });

    test('evaluates if statements and boolean controls', () async {
      final source = BookSource()
        ..bookSourceName = 'Test If Statement'
        ..bookSourceType = 0
        ..bookSourceUrl = 'https://example.com';
      final url = await LegadoParser.buildSearchUrl(
        source
          ..searchUrl = r'''
            @js:
            var skip = true;
            var resultUrl = "https://example.com/search?q=" + key;
            if (skip) {
              resultUrl = resultUrl + "&skip=1";
            }
            resultUrl;
          ''',
        'abc',
      );
      expect(url, 'https://example.com/search?q=abc&skip=1');
    });
  });
}
