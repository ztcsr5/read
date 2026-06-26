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

  List<String> recommendedFocus([int limit = 5]) => topDependencies(limit)
      .map((entry) => _recommendationForDependency(entry.key, entry.value))
      .toList(growable: false);

  Map<String, dynamic> toJson() => {
    'totalSources': totalSources,
    'riskySources': riskySources,
    'riskyRatio': riskyRatio,
    'formatCounts': formatCounts,
    'dependencyCounts': dependencyCounts,
    'stageCounts': stageCounts,
    'reasonCounts': reasonCounts,
    'topReasons': topReasons()
        .map((entry) => {'reason': entry.key, 'count': entry.value})
        .toList(growable: false),
    'recommendedFocus': recommendedFocus(),
    'items': items.map((item) => item.toJson()).toList(growable: false),
  };

  static List<MapEntry<String, int>> _sorted(Map<String, int> map) {
    final entries = map.entries.toList();
    entries.sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
    return entries;
  }

  static String _recommendationForDependency(String dependency, int count) {
    switch (dependency) {
      case 'javascript':
        return 'javascript:$count - expand JS runtime/function compatibility first';
      case 'http-js-bridge':
        return 'http-js-bridge:$count - verify java.ajax/connect/fetch/request bridges and request config parsing';
      case 'webview':
        return 'webview:$count - prioritize Cookie/WebView verification flow instead of treating sources as dead';
      case 'headers-cookie':
        return 'headers-cookie:$count - inspect final headers, Cookie persistence, Referer and User-Agent behavior';
      case 'login':
        return 'login:$count - separate login-required sources from parser failures';
      case 'non-utf8':
        return 'non-utf8:$count - validate GBK/GB2312/GB18030 decoding path';
      case 'jsoup':
        return 'jsoup:$count - compare org.jsoup/java.jsoup helper coverage with source scripts';
      case 'xpath':
        return 'xpath:$count - normalize XPath-prefixed rules before CSS parsing';
      case 'crypto-signature':
        return 'crypto-signature:$count - prioritize RSA/signature bridge fixtures before parser tuning';
      case 'crypto-heavy':
        return 'crypto-heavy:$count - verify AES/DES/HMAC helper parity against real source fixtures';
      case 'asymmetric-crypto':
        return 'asymmetric-crypto:$count - implement or explicitly gate java.createAsymmetricCrypto/createSign support';
      case 'file-system':
        return 'file-system:$count - emulate only source-scoped cache/file APIs and avoid unrestricted storage access';
      case 'archive':
        return 'archive:$count - inspect zip/7z/rar payload role before adding extraction support';
      case 'response-code':
        return 'response-code:$count - expose HTTP status and headers through the JS bridge';
      case 'verification-code':
        return 'verification-code:$count - separate captcha/OCR/manual verification sources from parser failures';
      case 'dynamic-script':
        return 'dynamic-script:$count - capture and cache imported scripts for deterministic compatibility tests';
      default:
        return '$dependency:$count - inspect representative sources';
    }
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

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'format': format,
    'dependencies': dependencies,
    'issueCount': issues.length,
    'issues': issues.map((issue) => issue.toJson()).toList(growable: false),
  };
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
    addIf(
      text.contains('java.createasymmetriccrypto') ||
          text.contains('java.createsign'),
      'asymmetric-crypto',
    );
    addIf(
      RegExp(r'\b(?:rsa|dsa|ecdsa|signature|cryptojs\.rsa)\b').hasMatch(text) ||
          text.contains('java.createasymmetriccrypto') ||
          text.contains('java.createsign'),
      'crypto-signature',
    );
    addIf(
      RegExp(
        r'\b(?:cryptojs\.)?(?:aes|des|tripledes|desede|hmacsha1|hmacsha256|hmacmd5|hmachex)\b',
      ).hasMatch(text),
      'crypto-heavy',
    );
    addIf(text.contains('java.getresponsecode'), 'response-code');
    addIf(
      text.contains('java.readfile') ||
          text.contains('java.readtxtfile') ||
          text.contains('java.deletefile') ||
          text.contains('java.cachefile'),
      'file-system',
    );
    addIf(
      text.contains('java.unzipfile') ||
          text.contains('java.un7zfile') ||
          text.contains('java.unrarfile'),
      'archive',
    );
    addIf(text.contains('java.importscript'), 'dynamic-script');
    addIf(text.contains('java.getverificationcode'), 'verification-code');
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
