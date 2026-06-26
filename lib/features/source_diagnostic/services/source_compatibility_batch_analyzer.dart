import '../../../data/models/book_source.dart';
import '../../../data/models/diagnostic_report.dart';
import 'compatibility_analyzer.dart';

class SourceCompatibilityBatchReport {
  final int totalSources;
  final int riskySources;
  final Map<String, int> formatCounts;
  final Map<String, int> dependencyCounts;
  final Map<String, int> stageCounts;
  final Map<String, int> reasonCounts;
  final List<SourceCompatibilityBatchItem> items;

  const SourceCompatibilityBatchReport({
    required this.totalSources,
    required this.riskySources,
    required this.formatCounts,
    required this.dependencyCounts,
    required this.stageCounts,
    required this.reasonCounts,
    required this.items,
  });

  double get riskyRatio => totalSources == 0 ? 0 : riskySources / totalSources;

  List<MapEntry<String, int>> topReasons([int limit = 8]) =>
      _sorted(reasonCounts).take(limit).toList(growable: false);

  List<MapEntry<String, int>> topDependencies([int limit = 8]) =>
      _sorted(dependencyCounts).take(limit).toList(growable: false);

  static List<MapEntry<String, int>> _sorted(Map<String, int> map) {
    final entries = map.entries.toList();
    entries.sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
    return entries;
  }
}

class SourceCompatibilityBatchItem {
  final String name;
  final String url;
  final String format;
  final List<String> dependencies;
  final List<DiagnosticIssue> issues;

  const SourceCompatibilityBatchItem({
    required this.name,
    required this.url,
    required this.format,
    required this.dependencies,
    required this.issues,
  });

  bool get hasRisk => issues.isNotEmpty;
}

class SourceCompatibilityBatchAnalyzer {
  static SourceCompatibilityBatchReport analyze(Iterable<BookSource> sources) {
    final items = <SourceCompatibilityBatchItem>[];
    final formatCounts = <String, int>{};
    final dependencyCounts = <String, int>{};
    final stageCounts = <String, int>{};
    final reasonCounts = <String, int>{};

    for (final source in sources) {
      final issues = CompatibilityAnalyzer.analyze(source);
      final format = _detectFormat(source);
      final dependencies = _detectDependencies(source, issues);
      final item = SourceCompatibilityBatchItem(
        name: source.bookSourceName,
        url: source.bookSourceUrl,
        format: format,
        dependencies: dependencies,
        issues: issues,
      );
      items.add(item);

      _inc(formatCounts, format);
      for (final dependency in dependencies) {
        _inc(dependencyCounts, dependency);
      }
      for (final issue in issues) {
        _inc(stageCounts, issue.stage);
        _inc(reasonCounts, issue.reason);
      }
    }

    return SourceCompatibilityBatchReport(
      totalSources: items.length,
      riskySources: items.where((item) => item.hasRisk).length,
      formatCounts: Map.unmodifiable(formatCounts),
      dependencyCounts: Map.unmodifiable(dependencyCounts),
      stageCounts: Map.unmodifiable(stageCounts),
      reasonCounts: Map.unmodifiable(reasonCounts),
      items: List.unmodifiable(items),
    );
  }

  static void _inc(Map<String, int> map, String key) {
    if (key.trim().isEmpty) return;
    map[key] = (map[key] ?? 0) + 1;
  }

  static String _detectFormat(BookSource source) {
    final text = _joined(source).toLowerCase();
    if (text.contains('"sourceformat":"js"') ||
        text.contains('"sourceformat": "js"') ||
        text.contains('"engine":"quickjs"') ||
        text.contains('"engine": "quickjs"') ||
        text.contains('"jslib"') ||
        RegExp(
          r'(?:async\s+)?function\s+(?:search|explore|bookinfo|toc|content)\s*\(',
          caseSensitive: false,
        ).hasMatch(text)) {
      return 'js-function';
    }
    if (source.ruleSearch?.trim().startsWith('{') == true ||
        source.ruleBookInfo?.trim().startsWith('{') == true ||
        source.ruleToc?.trim().startsWith('{') == true ||
        source.ruleContent?.trim().startsWith('{') == true ||
        source.ruleExplore?.trim().startsWith('{') == true) {
      return 'legado-json';
    }
    if (source.searchUrl?.trim().isNotEmpty == true ||
        source.ruleSearch?.trim().isNotEmpty == true) {
      return 'legado-mixed';
    }
    return 'unknown';
  }

  static List<String> _detectDependencies(
    BookSource source,
    List<DiagnosticIssue> issues,
  ) {
    final text = _joined(source).toLowerCase();
    final values = <String>{};
    void addIf(bool condition, String value) {
      if (condition) values.add(value);
    }

    addIf(
      text.contains('@js') ||
          text.contains('<js') ||
          text.contains('"engine":"quickjs"') ||
          text.contains('"engine": "quickjs"') ||
          text.contains('"jslib"'),
      'javascript',
    );
    addIf(
      text.contains('java.ajax') ||
          text.contains('java.connect') ||
          text.contains('java.get') ||
          text.contains('java.post') ||
          text.contains('java.fetch') ||
          RegExp(r'\bfetch\s*\(').hasMatch(text) ||
          RegExp(r'\brequest\s*\(').hasMatch(text),
      'http-js-bridge',
    );
    addIf(
      text.contains('webview') ||
          text.contains('startbrowser') ||
          text.contains('@webview') ||
          text.contains('webjs'),
      'webview',
    );
    addIf(
      text.contains('loginurl') ||
          text.contains('loginui') ||
          text.contains('logincheckjs'),
      'login',
    );
    addIf(
      text.contains('cookie') ||
          text.contains('cf_clearance') ||
          text.contains('"header"') ||
          text.contains('"headers"') ||
          text.contains('user-agent') ||
          text.contains('httpuseragent'),
      'headers-cookie',
    );
    addIf(
      text.contains('gbk') ||
          text.contains('gb2312') ||
          text.contains('gb18030'),
      'non-utf8',
    );
    addIf(
      text.contains('org.jsoup') ||
          text.contains('jsoup.parse') ||
          text.contains('java.jsoup'),
      'jsoup',
    );
    addIf(
      issues.any((issue) => issue.reason.toLowerCase().contains('xpath')),
      'xpath',
    );
    return values.toList(growable: false)..sort();
  }

  static String _joined(BookSource source) => [
    source.searchUrl,
    source.exploreUrl,
    source.ruleSearch,
    source.ruleExplore,
    source.ruleBookInfo,
    source.ruleToc,
    source.ruleContent,
    source.customConfig,
  ].whereType<String>().join('\n');
}
