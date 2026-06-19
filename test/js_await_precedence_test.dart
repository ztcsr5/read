import 'package:flutter_test/flutter_test.dart';
import 'package:read/data/parsers/legado/legado_js_engine.dart';

void main() {
  group('JsCompatibilityTransformer await precedence', () {
    test('wraps java.ajax(url).match(...) with parentheses', () {
      final code = r'''
var url = "https://example.com";
header = {
  "headers": {"Referer": url},
  "method": "POST",
  "body": "kw=test&_token="+java.ajax(url).match(/=\"_token\" value=\"(.*?)\"/)[1]
}
url + "," + JSON.stringify(header)
''';
      final result = JsCompatibilityTransformer.transform(code);
      // The ajax call should be wrapped: (await java.ajax(url))
      expect(result, contains('(await java.ajax(url))'));
      // .match should chain AFTER the parenthesized await
      expect(result, contains('(await java.ajax(url)).match'));
      // Should NOT have bare await java.ajax(url).match
      expect(result, isNot(contains('await java.ajax(url).match')));
    });

    test('does not double-wrap already awaited calls', () {
      final code = 'var x = await java.ajax(url)';
      final result = JsCompatibilityTransformer.transform(code, wrapScript: false);
      // Should not have (await await ...
      expect(result, isNot(contains('await await')));
    });

    test('wraps java.post(...) with chained method', () {
      final code = 'java.post(url, body).match(/result=(.*?)&/)[1]';
      final result = JsCompatibilityTransformer.transform(code, wrapScript: false);
      expect(result, contains('(await java.post(url, body)).match'));
    });

    test('wraps simple java.ajax call without chaining', () {
      final code = 'var html = java.ajax(url)';
      final result = JsCompatibilityTransformer.transform(code, wrapScript: false);
      expect(result, contains('(await java.ajax(url))'));
    });

    test('handles nested parentheses inside ajax arguments', () {
      final code = 'java.ajax(base + encodeURI(key)).match(/token/)[0]';
      final result = JsCompatibilityTransformer.transform(code, wrapScript: false);
      expect(result, contains('(await java.ajax(base + encodeURI(key))).match'));
    });
  });
}
