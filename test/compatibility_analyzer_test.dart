import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:read/data/models/book_source.dart';
import 'package:read/features/source_diagnostic/services/compatibility_analyzer.dart';

void main() {
  group('CompatibilityAnalyzer', () {
    test('detects js function source runtime requirements', () {
      final source = BookSource()
        ..bookSourceName = 'JS Function'
        ..bookSourceUrl = 'https://js.example.com'
        ..searchUrl = '/search?q={{key}}'
        ..ruleSearch = jsonEncode({
          'bookList': '<js>search(key, page, result)</js>',
        })
        ..customConfig = jsonEncode({
          'engine': 'quickjs',
          'sourceFormat': 'js',
          'jsLib': 'function search(){}',
        });

      final reasons = CompatibilityAnalyzer.analyze(
        source,
      ).map((issue) => issue.reason).join('\n');

      expect(reasons, contains('JavaScript'));
    });

    test('detects browser and access state dependencies', () {
      final source = BookSource()
        ..bookSourceName = 'Browser'
        ..bookSourceUrl = 'https://browser.example.com'
        ..ruleSearch = '@js:java.startBrowser(baseUrl)'
        ..customConfig = jsonEncode({
          'webJs': 'document.body.innerText',
          'loginUrl': 'https://browser.example.com/login',
          'headers': {'Cookie': 'sid=1', 'User-Agent': 'Mobile'},
        });

      final reasons = CompatibilityAnalyzer.analyze(
        source,
      ).map((issue) => issue.reason).join('\n');

      expect(reasons, contains('JavaScript'));
      expect(reasons, contains('WebView'));
      expect(reasons, contains('Cookie'));
      expect(reasons, contains('请求头'));
    });

    test('detects fetch and request bridge dependencies', () {
      final source = BookSource()
        ..bookSourceName = 'Fetch'
        ..bookSourceUrl = 'https://fetch.example.com'
        ..ruleSearch = jsonEncode({
          'bookList':
              '<js>const html = fetch(source.getUrl() + "/api"); request("/next"); search(key, page, html)</js>',
        });

      final reasons = CompatibilityAnalyzer.analyze(
        source,
      ).map((issue) => issue.reason).join('\n');

      expect(reasons, contains('JavaScript'));
      expect(reasons, contains('java.ajax'));
    });
  });
}
