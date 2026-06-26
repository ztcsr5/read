import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:read/data/models/book_source.dart';
import 'package:read/features/source_diagnostic/services/compatibility_analyzer.dart';
import 'package:read/features/source_diagnostic/services/source_compatibility_batch_analyzer.dart';

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

    test('detects js dependencies in explore rules', () {
      final source = BookSource()
        ..bookSourceName = 'Explore JS'
        ..bookSourceUrl = 'https://explore.example.com'
        ..ruleExplore = jsonEncode({
          'bookList':
              '<js>const html = java.ajax(source.getUrl()); explore(baseUrl, html)</js>',
        });

      final issues = CompatibilityAnalyzer.analyze(source);

      expect(issues.map((issue) => issue.stage), contains('explore'));
      expect(
        issues.map((issue) => issue.reason).join('\n'),
        contains('JavaScript'),
      );
      expect(
        issues.map((issue) => issue.reason).join('\n'),
        contains('java.ajax'),
      );
    });

    test('summarizes source compatibility batches', () {
      final jsSource = BookSource()
        ..bookSourceName = 'JS Source'
        ..bookSourceUrl = 'https://js.example.com'
        ..ruleSearch = jsonEncode({
          'bookList': '<js>fetch("/api"); search(key, page, result)</js>',
        })
        ..customConfig = jsonEncode({
          'engine': 'quickjs',
          'sourceFormat': 'js',
          'jsLib': 'function search(){}',
        });
      final webViewSource = BookSource()
        ..bookSourceName = 'WebView Source'
        ..bookSourceUrl = 'https://web.example.com'
        ..ruleSearch = '@js:java.startBrowser(baseUrl)'
        ..customConfig = jsonEncode({
          'webJs': 'document.body.innerText',
          'headers': {'Cookie': 'sid=1'},
        });
      final plainSource = BookSource()
        ..bookSourceName = 'Plain Source'
        ..bookSourceUrl = 'https://plain.example.com'
        ..searchUrl = '/search?q={{key}}'
        ..ruleSearch = jsonEncode({
          'bookList': '.book',
          'name': 'a@text',
          'bookUrl': 'a@href',
        });

      final report = SourceCompatibilityBatchAnalyzer.analyze([
        jsSource,
        webViewSource,
        plainSource,
      ]);

      expect(report.totalSources, 3);
      expect(report.riskySources, 2);
      expect(report.formatCounts['js-function'], 1);
      expect(report.formatCounts['legado-json'], 1);
      expect(report.dependencyCounts['javascript'], 2);
      expect(report.dependencyCounts['http-js-bridge'], 1);
      expect(report.dependencyCounts['webview'], 1);
      expect(report.dependencyCounts['headers-cookie'], 1);
      expect(report.topDependencies().first.key, 'javascript');
      expect(report.stageCounts.keys, contains('search'));
    });
  });
}
