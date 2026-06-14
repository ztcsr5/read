import 'dart:convert';
import 'dart:io';

Future<List<LoadedSource>> loadProbeInputs(List<String> inputs) async {
  final loaded = <LoadedSource>[];
  for (final input in inputs) {
    loaded.addAll(await _loadInput(input));
  }
  return loaded;
}

List<LoadedSource> selectProbeSources(
  List<LoadedSource> loaded,
  ProbeOptions options,
) {
  var selected = loaded
      .where((entry) => !options.novelOnly || readSourceType(entry.raw) == 0)
      .toList();
  if (options.nameFilter != null && options.nameFilter!.trim().isNotEmpty) {
    final needle = options.nameFilter!.trim().toLowerCase();
    selected = selected
        .where(
          (entry) => readSourceName(entry.raw).toLowerCase().contains(needle),
        )
        .toList();
  }
  if (options.urlFilter != null && options.urlFilter!.trim().isNotEmpty) {
    final needle = options.urlFilter!.trim().toLowerCase();
    selected = selected
        .where(
          (entry) => readSourceUrl(entry.raw).toLowerCase().contains(needle),
        )
        .toList();
  }
  if (options.dedupeByUrl) {
    final byUrl = <String, LoadedSource>{};
    for (final entry in selected) {
      final url = readSourceUrl(entry.raw);
      byUrl[url.isEmpty ? '${entry.file}#${entry.rawIndex}' : url] = entry;
    }
    selected = byUrl.values.toList();
  }
  if (options.offset > 0) {
    selected = selected.skip(options.offset).toList();
  }
  if (options.limit != null) {
    selected = selected.take(options.limit!).toList();
  }
  return selected;
}

Future<void> writeProbeReport(ProbeReport report) async {
  await Directory(report.options.outDir).create(recursive: true);
  await File('${report.options.outDir}/source_probe_report.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert(report.toJson()),
    encoding: utf8,
  );
  await File(
    '${report.options.outDir}/source_probe_report.csv',
  ).writeAsString(report.toCsv(), encoding: utf8);
  await File(
    '${report.options.outDir}/source_probe_summary.md',
  ).writeAsString(report.toMarkdown(), encoding: utf8);
  await File(
    '${report.options.outDir}/source_probe_failures.md',
  ).writeAsString(report.toFailureMarkdown(), encoding: utf8);
}

Future<List<LoadedSource>> _loadInput(String input) async {
  final type = await FileSystemEntity.type(input);
  if (type == FileSystemEntityType.notFound) {
    throw FileSystemException('Input not found', input);
  }
  if (type == FileSystemEntityType.directory) {
    final files = await Directory(input)
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    final loaded = <LoadedSource>[];
    for (final file in files) {
      loaded.addAll(await _loadJsonFile(file.path));
    }
    return loaded;
  }
  return _loadJsonFile(input);
}

Future<List<LoadedSource>> _loadJsonFile(String path) async {
  final text = (await File(
    path,
  ).readAsString(encoding: utf8)).replaceFirst('\uFEFF', '').trim();
  if (text.isEmpty) return const [];
  final decoded = jsonDecode(text);
  final items = normalizeImportItems(decoded);
  final result = <LoadedSource>[];
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    if (item is! Map) continue;
    final map = item.map((key, value) => MapEntry(key.toString(), value));
    if (!looksLikeBookSource(map)) continue;
    result.add(LoadedSource(file: path, rawIndex: i, raw: map));
  }
  return result;
}

List<dynamic> normalizeImportItems(dynamic parsed) {
  if (parsed is List) return parsed;
  if (parsed is Map) {
    final data = parsed['data'];
    if (data is List) return data;
    if (data is Map && data['list'] is List) return data['list'] as List;
    for (final key in [
      'list',
      'items',
      'sources',
      'bookSources',
      'bookSource',
    ]) {
      final value = parsed[key];
      if (value is List) return value;
    }
    return [parsed];
  }
  return const [];
}

bool looksLikeBookSource(Map<String, dynamic> map) {
  return map.containsKey('bookSourceName') ||
      map.containsKey('bookSourceUrl') ||
      map.containsKey('sourceName') ||
      map.containsKey('sourceUrl') ||
      map.containsKey('searchUrl') ||
      map.containsKey('ruleSearchUrl') ||
      map.containsKey('ruleSearch') ||
      map.containsKey('rulesSearch') ||
      map.containsKey('ruleToc') ||
      map.containsKey('rulesToc') ||
      map.containsKey('ruleContent') ||
      map.containsKey('rulesContent') ||
      map.containsKey('ruleBookContent');
}

int readSourceType(Map<String, dynamic> raw) {
  final value = raw['bookSourceType'] ?? raw['sourceType'];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String readSourceName(Map<String, dynamic> raw) {
  return (raw['bookSourceName'] ?? raw['sourceName'] ?? raw['name'] ?? '')
      .toString();
}

String readSourceUrl(Map<String, dynamic> raw) {
  return (raw['bookSourceUrl'] ?? raw['sourceUrl'] ?? raw['url'] ?? '')
      .toString();
}

String readSourceGroup(Map<String, dynamic> raw) {
  return (raw['bookSourceGroup'] ?? raw['sourceGroup'] ?? raw['group'] ?? '')
      .toString();
}

List<String> featureTags(Map<String, dynamic> raw) {
  final text = jsonEncode(raw);
  final tags = <String>[];
  void add(String tag, RegExp pattern) {
    if (pattern.hasMatch(text)) tags.add(tag);
  }

  add('@js', RegExp(r'@js:', caseSensitive: false));
  add('<js>', RegExp(r'<js>', caseSensitive: false));
  add('java.ajax', RegExp(r'java\.ajax', caseSensitive: false));
  add('java.get', RegExp(r'java\.get|@get:', caseSensitive: false));
  add('java.put', RegExp(r'java\.put|@put:', caseSensitive: false));
  add('webView', RegExp(r'webview', caseSensitive: false));
  add('cookie', RegExp(r'cookie', caseSensitive: false));
  add('header', RegExp(r'"headers?"|"bookSourceHeader"|httpUserAgent'));
  add('login', RegExp(r'loginUrl|loginUi|loginCheckJs'));
  add('sourceRegex', RegExp(r'sourceRegex'));
  add('replaceRegex', RegExp(r'replaceRegex|ruleBookContentReplace'));
  add('nextContentUrl', RegExp(r'nextContentUrl|ruleContentUrlNext'));
  add('nextTocUrl', RegExp(r'nextTocUrl|ruleChapterUrlNext'));
  add('@textNodes', RegExp(r'@textNodes', caseSensitive: false));
  add('@all', RegExp(r'@all', caseSensitive: false));
  add('jsonPath', RegExp(r'"\s*:?\s*"\$|"\s*:?\s*"\$\.'));
  add('xpath', RegExp(r'xpath:|@xpath:', caseSensitive: false));
  add(':has', RegExp(r':has\(', caseSensitive: false));
  add(':not', RegExp(r':not\(', caseSensitive: false));
  add(':matches', RegExp(r':matches(?:Own)?\(', caseSensitive: false));
  add(':contains', RegExp(r':contains(?:Own)?\(', caseSensitive: false));
  add('[attr~=', RegExp(r'\[[^\]]+~='));
  add('jsLib', RegExp(r'jsLib'));
  add('bodyJs', RegExp(r'bodyJs'));
  tags.sort();
  return tags;
}

bool hasJsFeature(Map<String, dynamic> raw) {
  final features = featureTags(raw);
  return features.any(
    (feature) =>
        feature == '@js' ||
        feature == '<js>' ||
        feature == 'java.ajax' ||
        feature == 'java.get' ||
        feature == 'java.put' ||
        feature == 'jsLib' ||
        feature == 'bodyJs',
  );
}

bool hasWebViewFeature(Map<String, dynamic> raw) {
  return featureTags(raw).contains('webView');
}

String buildCompatHint(
  String? failStep,
  List<String> features,
  String message,
) {
  final lowerMessage = message.toLowerCase();
  if (failStep == null) return '';
  if (failStep == 'JS 环境') return 'quickjs-unavailable';
  if (failStep == 'WebView 环境') return 'webview-unavailable';
  if (failStep == '站点验证') return 'manual-verification';
  if (_looksLikeAuthOrSignatureFailure(lowerMessage)) {
    return 'auth-or-signature';
  }
  if (_looksLikeEmptyResponse(lowerMessage)) {
    return 'empty-response';
  }
  if (_looksLikeJsFallbackUnsupported(lowerMessage)) {
    return 'js-fallback-unsupported';
  }
  if (_looksLikeTransientNetworkFailure(lowerMessage)) {
    return 'network-transient';
  }
  if (failStep == '搜索 URL' &&
      (features.contains('@js') || features.contains('<js>'))) {
    return 'searchUrl-js';
  }
  if (failStep == '请求搜索页' &&
      (features.contains('webView') || lowerMessage.contains('cloudflare'))) {
    return 'network-or-webview';
  }
  if (failStep == '搜索结果' &&
      (features.contains('java.ajax') || features.contains('jsonPath'))) {
    return 'search-rule-js-json';
  }
  if (failStep == '目录' &&
      (features.contains('java.get') || features.contains('@textNodes'))) {
    return 'toc-rule-context';
  }
  if (failStep == '正文' &&
      (features.contains('nextContentUrl') || features.contains('webView'))) {
    return 'content-pagination-or-webview';
  }
  if (features.contains('login') || features.contains('cookie')) {
    return 'auth-or-cookie';
  }
  return '';
}

bool shouldTreatProbeFailureAsBlocked({
  required String? failStep,
  required List<String> features,
  required String message,
}) {
  if (failStep == null) return false;
  final hint = buildCompatHint(failStep, features, message);
  if (const {
    'quickjs-unavailable',
    'webview-unavailable',
    'manual-verification',
    'network-transient',
    'network-or-webview',
    'js-fallback-unsupported',
    'auth-or-signature',
    'empty-response',
    'toc-rule-context',
  }.contains(hint)) {
    return true;
  }
  if (failStep == '搜索结果' &&
      (features.contains('cookie') ||
          features.contains('header') ||
          features.contains('login') ||
          features.contains('webView') ||
          features.contains('@js') ||
          features.contains('<js>') ||
          features.contains('java.ajax') ||
          features.contains('java.get') ||
          features.contains('java.put'))) {
    return true;
  }
  if (failStep == '正文' &&
      (features.contains('cookie') ||
          features.contains('header') ||
          features.contains('login') ||
          features.contains('webView') ||
          features.contains('nextContentUrl'))) {
    return true;
  }
  if ((failStep == '搜索 URL' || failStep == '目录') &&
      (features.contains('@js') ||
          features.contains('<js>') ||
          features.contains('java.ajax') ||
          features.contains('java.get') ||
          features.contains('java.put') ||
          features.contains('jsLib') ||
          features.contains('jsonPath'))) {
    return true;
  }
  return false;
}

bool _looksLikeJsFallbackUnsupported(String lowerMessage) {
  return lowerMessage.contains('node js fallback') ||
      lowerMessage.contains('javaimporter') ||
      lowerMessage.contains('packages.javax') ||
      lowerMessage.contains('packages.java') ||
      lowerMessage.contains('desencodetobase64string') ||
      lowerMessage.contains('aesbase64') ||
      lowerMessage.contains('is not a function') &&
          lowerMessage.contains('java.');
}

bool _looksLikeTransientNetworkFailure(String lowerMessage) {
  return lowerMessage.contains('timeout') ||
      lowerMessage.contains('timed out') ||
      lowerMessage.contains('connection timeout') ||
      lowerMessage.contains('connection terminated') ||
      lowerMessage.contains('handshake') ||
      lowerMessage.contains('socketexception') ||
      lowerMessage.contains('connection reset') ||
      lowerMessage.contains('network is unreachable') ||
      lowerMessage.contains('failed host lookup') ||
      lowerMessage.contains('connection refused');
}

bool _looksLikeAuthOrSignatureFailure(String lowerMessage) {
  return lowerMessage.contains('接口鉴权不合法') ||
      lowerMessage.contains('鉴权不合法') ||
      lowerMessage.contains('签名错误') ||
      lowerMessage.contains('签名失败') ||
      lowerMessage.contains('invalid signature') ||
      lowerMessage.contains('signature error') ||
      lowerMessage.contains('"retcode":2') ||
      lowerMessage.contains("'retcode':2");
}

bool _looksLikeEmptyResponse(String lowerMessage) {
  return lowerMessage.contains('响应体为空') ||
      lowerMessage.contains('empty response') ||
      lowerMessage.contains('response body empty') ||
      lowerMessage.contains('响应内容前缀采样: \n') ||
      lowerMessage.endsWith('响应内容前缀采样:');
}

class LoadedSource {
  final String file;
  final int rawIndex;
  final Map<String, dynamic> raw;

  const LoadedSource({
    required this.file,
    required this.rawIndex,
    required this.raw,
  });
}

class ProbeResult {
  final String file;
  final int rawIndex;
  final String sourceName;
  final String sourceUrl;
  final String sourceGroup;
  final int sourceType;
  final String status;
  final String? failStep;
  final String message;
  final int durationMs;
  final int? booksCount;
  final int? chaptersCount;
  final int? contentLength;
  final List<String> features;
  final String compatHint;
  final List<Map<String, dynamic>> steps;
  final List<String> failLogs;

  const ProbeResult({
    required this.file,
    required this.rawIndex,
    required this.sourceName,
    required this.sourceUrl,
    required this.sourceGroup,
    required this.sourceType,
    required this.status,
    required this.message,
    required this.durationMs,
    required this.features,
    required this.compatHint,
    this.failStep,
    this.booksCount,
    this.chaptersCount,
    this.contentLength,
    this.steps = const [],
    this.failLogs = const [],
  });

  factory ProbeResult.staticOnly(LoadedSource entry) {
    final features = featureTags(entry.raw);
    return ProbeResult(
      file: entry.file,
      rawIndex: entry.rawIndex,
      sourceName: readSourceName(entry.raw),
      sourceUrl: readSourceUrl(entry.raw),
      sourceGroup: readSourceGroup(entry.raw),
      sourceType: readSourceType(entry.raw),
      status: 'static',
      message: 'static feature scan only',
      durationMs: 0,
      features: features,
      compatHint: '',
    );
  }

  factory ProbeResult.error({
    required LoadedSource entry,
    required String status,
    required String failStep,
    required String message,
    required int durationMs,
    List<String> logs = const [],
  }) {
    final features = featureTags(entry.raw);
    return ProbeResult(
      file: entry.file,
      rawIndex: entry.rawIndex,
      sourceName: readSourceName(entry.raw),
      sourceUrl: readSourceUrl(entry.raw),
      sourceGroup: readSourceGroup(entry.raw),
      sourceType: readSourceType(entry.raw),
      status: status,
      failStep: failStep,
      message: message,
      durationMs: durationMs,
      features: features,
      compatHint: buildCompatHint(failStep, features, message),
      failLogs: logs,
    );
  }

  factory ProbeResult.blocked({
    required LoadedSource entry,
    required String failStep,
    required String message,
    required int durationMs,
    List<String> logs = const [],
  }) {
    final features = featureTags(entry.raw);
    return ProbeResult(
      file: entry.file,
      rawIndex: entry.rawIndex,
      sourceName: readSourceName(entry.raw),
      sourceUrl: readSourceUrl(entry.raw),
      sourceGroup: readSourceGroup(entry.raw),
      sourceType: readSourceType(entry.raw),
      status: 'blocked',
      failStep: failStep,
      message: message,
      durationMs: durationMs,
      features: features,
      compatHint: buildCompatHint(failStep, features, message),
      failLogs: logs,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'file': file,
      'rawIndex': rawIndex,
      'sourceName': sourceName,
      'sourceUrl': sourceUrl,
      'sourceGroup': sourceGroup,
      'sourceType': sourceType,
      'status': status,
      'failStep': failStep,
      'message': message,
      'durationMs': durationMs,
      'booksCount': booksCount,
      'chaptersCount': chaptersCount,
      'contentLength': contentLength,
      'features': features,
      'compatHint': compatHint,
      'steps': steps,
      'failLogs': failLogs,
    };
  }
}

class ProbeReport {
  final DateTime startedAt;
  final DateTime finishedAt;
  final ProbeOptions options;
  final int totalRawItems;
  final int selectedSources;
  final List<ProbeResult> results;

  const ProbeReport({
    required this.startedAt,
    required this.finishedAt,
    required this.options,
    required this.totalRawItems,
    required this.selectedSources,
    required this.results,
  });

  Map<String, dynamic> toJson() {
    return {
      'generatedAt': finishedAt.toIso8601String(),
      'durationSeconds': finishedAt.difference(startedAt).inSeconds,
      'options': options.toJson(),
      'summary': summaryJson(),
      'results': results.map((result) => result.toJson()).toList(),
    };
  }

  Map<String, dynamic> summaryJson() {
    return {
      'totalRawItems': totalRawItems,
      'selectedSources': selectedSources,
      'ok': results.where((result) => result.status == 'ok').length,
      'fail': results.where((result) => result.status == 'fail').length,
      'timeout': results.where((result) => result.status == 'timeout').length,
      'error': results.where((result) => result.status == 'error').length,
      'blocked': results.where((result) => result.status == 'blocked').length,
      'static': results.where((result) => result.status == 'static').length,
      'byStatus': countBy(results.map((result) => result.status)),
      'byFailStep': countBy(
        results
            .where((result) => result.failStep != null)
            .map((result) => result.failStep!),
      ),
      'byCompatHint': countBy(
        results
            .where((result) => result.compatHint.isNotEmpty)
            .map((result) => result.compatHint),
      ),
      'featureCounts': featureCounts(results),
      'featureFailureCounts': featureCounts(
        results.where((result) => result.status != 'ok'),
      ),
    };
  }

  String shortSummary() {
    final summary = summaryJson();
    return 'Summary: selected=${summary['selectedSources']} '
        'ok=${summary['ok']} fail=${summary['fail']} '
        'timeout=${summary['timeout']} error=${summary['error']} '
        'blocked=${summary['blocked']} '
        'static=${summary['static']}';
  }

  String toCsv() {
    final buffer = StringBuffer();
    buffer.writeln(
      [
        'status',
        'failStep',
        'compatHint',
        'durationMs',
        'booksCount',
        'chaptersCount',
        'contentLength',
        'features',
        'sourceName',
        'sourceUrl',
        'sourceGroup',
        'sourceType',
        'message',
        'file',
        'rawIndex',
      ].join(','),
    );
    for (final result in results) {
      buffer.writeln(
        [
          result.status,
          result.failStep ?? '',
          result.compatHint,
          result.durationMs.toString(),
          result.booksCount?.toString() ?? '',
          result.chaptersCount?.toString() ?? '',
          result.contentLength?.toString() ?? '',
          result.features.join('|'),
          result.sourceName,
          result.sourceUrl,
          result.sourceGroup,
          result.sourceType.toString(),
          result.message,
          result.file,
          result.rawIndex.toString(),
        ].map(csv).join(','),
      );
    }
    return buffer.toString();
  }

  String toMarkdown() {
    final summary = summaryJson();
    final buffer = StringBuffer();
    buffer.writeln('# Source Probe Summary');
    buffer.writeln();
    buffer.writeln('- Generated: ${finishedAt.toIso8601String()}');
    buffer.writeln('- Inputs: ${options.inputs.join(', ')}');
    buffer.writeln('- Keyword: `${options.keyword}`');
    buffer.writeln('- Mode: ${options.dryRun ? 'static dry-run' : 'live'}');
    buffer.writeln(
      '- Selected: ${summary['selectedSources']} / raw $totalRawItems',
    );
    buffer.writeln(
      '- Result: ok ${summary['ok']}, fail ${summary['fail']}, '
      'timeout ${summary['timeout']}, error ${summary['error']}, '
      'blocked ${summary['blocked']}, '
      'static ${summary['static']}',
    );
    buffer.writeln();
    writeTable(
      buffer,
      'Failure steps',
      summary['byFailStep'] as Map<String, int>,
    );
    writeTable(
      buffer,
      'Compatibility hints',
      summary['byCompatHint'] as Map<String, int>,
    );
    writeTable(
      buffer,
      'Feature counts',
      summary['featureCounts'] as Map<String, int>,
    );
    writeTable(
      buffer,
      'Feature counts among non-ok sources',
      summary['featureFailureCounts'] as Map<String, int>,
    );
    buffer.writeln('## Slowest sources');
    buffer.writeln();
    buffer.writeln('| ms | status | fail step | source |');
    buffer.writeln('|---:|---|---|---|');
    final slowest = [...results]
      ..sort((a, b) => b.durationMs.compareTo(a.durationMs));
    for (final result in slowest.take(20)) {
      buffer.writeln(
        '| ${result.durationMs} | ${md(result.status)} | '
        '${md(result.failStep ?? '')} | ${md(result.sourceName)} |',
      );
    }
    return buffer.toString();
  }

  String toFailureMarkdown() {
    final failures = results
        .where((result) => result.status != 'ok' && result.status != 'static')
        .toList();
    final buffer = StringBuffer();
    buffer.writeln('# Source Probe Failures');
    buffer.writeln();
    buffer.writeln('Total failures: ${failures.length}');
    buffer.writeln();
    for (final result in failures.take(200)) {
      buffer.writeln('## ${result.sourceName}');
      buffer.writeln();
      buffer.writeln('- Status: `${result.status}`');
      buffer.writeln('- Fail step: `${result.failStep ?? ''}`');
      buffer.writeln('- Hint: `${result.compatHint}`');
      buffer.writeln('- URL: `${result.sourceUrl}`');
      buffer.writeln('- Features: `${result.features.join(', ')}`');
      buffer.writeln('- Message: ${result.message}');
      if (result.failLogs.isNotEmpty) {
        buffer.writeln('- Logs:');
        buffer.writeln('```text');
        buffer.writeln(result.failLogs.join('\n'));
        buffer.writeln('```');
      }
      buffer.writeln();
    }
    return buffer.toString();
  }
}

Map<String, int> countBy(Iterable<String> values) {
  final result = <String, int>{};
  for (final value in values) {
    if (value.trim().isEmpty) continue;
    result[value] = (result[value] ?? 0) + 1;
  }
  return Map.fromEntries(
    result.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
  );
}

Map<String, int> featureCounts(Iterable<ProbeResult> results) {
  final values = <String>[];
  for (final result in results) {
    values.addAll(result.features);
  }
  return countBy(values);
}

void writeTable(StringBuffer buffer, String title, Map<String, int> data) {
  buffer.writeln('## $title');
  buffer.writeln();
  if (data.isEmpty) {
    buffer.writeln('_None_');
    buffer.writeln();
    return;
  }
  buffer.writeln('| item | count |');
  buffer.writeln('|---|---:|');
  for (final entry in data.entries.take(30)) {
    buffer.writeln('| ${md(entry.key)} | ${entry.value} |');
  }
  buffer.writeln();
}

String csv(String value) {
  final escaped = value.replaceAll('"', '""');
  return '"$escaped"';
}

String md(String value) {
  return value.replaceAll('|', r'\|').replaceAll('\n', ' ');
}

class ProbeOptions {
  final List<String> inputs;
  final String keyword;
  final int concurrency;
  final int timeoutSeconds;
  final int? limit;
  final int offset;
  final String? nameFilter;
  final String? urlFilter;
  final String outDir;
  final bool dryRun;
  final bool novelOnly;
  final bool dedupeByUrl;
  final bool includeLogs;
  final int failLogLines;
  final bool help;

  const ProbeOptions({
    required this.inputs,
    required this.keyword,
    required this.concurrency,
    required this.timeoutSeconds,
    required this.limit,
    required this.offset,
    required this.nameFilter,
    required this.urlFilter,
    required this.outDir,
    required this.dryRun,
    required this.novelOnly,
    required this.dedupeByUrl,
    required this.includeLogs,
    required this.failLogLines,
    required this.help,
  });

  factory ProbeOptions.parse(List<String> args) {
    final inputs = <String>[];
    final values = <String, String>{};
    final flags = <String>{};
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (!arg.startsWith('--')) {
        inputs.add(arg);
        continue;
      }
      final withoutPrefix = arg.substring(2);
      final eq = withoutPrefix.indexOf('=');
      if (eq >= 0) {
        values[withoutPrefix.substring(0, eq)] = withoutPrefix.substring(
          eq + 1,
        );
        continue;
      }
      const valueKeys = {
        'keyword',
        'concurrency',
        'timeout',
        'limit',
        'offset',
        'name',
        'url',
        'out',
        'fail-log-lines',
      };
      if (valueKeys.contains(withoutPrefix)) {
        if (i + 1 >= args.length) {
          throw FormatException('Missing value for --$withoutPrefix');
        }
        values[withoutPrefix] = args[++i];
      } else {
        flags.add(withoutPrefix);
      }
    }
    return ProbeOptions(
      inputs: inputs,
      keyword: values['keyword'] ?? '斗破苍穹',
      concurrency: intValue(values['concurrency'], 2).clamp(1, 20),
      timeoutSeconds: intValue(values['timeout'], 45).clamp(5, 300),
      limit: values.containsKey('limit') ? intValue(values['limit'], 0) : null,
      offset: intValue(values['offset'], 0).clamp(0, 1 << 30),
      nameFilter: values['name'],
      urlFilter: values['url'],
      outDir: values['out'] ?? 'build/source_probe',
      dryRun: flags.contains('dry-run'),
      novelOnly: !flags.contains('all-types'),
      dedupeByUrl: flags.contains('dedupe'),
      includeLogs: flags.contains('include-logs'),
      failLogLines: intValue(values['fail-log-lines'], 40).clamp(0, 1000),
      help: flags.contains('help') || flags.contains('h'),
    );
  }

  factory ProbeOptions.fromJson(Map<String, dynamic> json) {
    return ProbeOptions(
      inputs: (json['inputs'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      keyword: json['keyword']?.toString() ?? '斗破苍穹',
      concurrency: intValue(json['concurrency']?.toString(), 2).clamp(1, 20),
      timeoutSeconds: intValue(
        json['timeoutSeconds']?.toString(),
        45,
      ).clamp(5, 300),
      limit: json['limit'] == null
          ? null
          : intValue(json['limit'].toString(), 0),
      offset: intValue(json['offset']?.toString(), 0).clamp(0, 1 << 30),
      nameFilter: json['nameFilter']?.toString(),
      urlFilter: json['urlFilter']?.toString(),
      outDir: json['outDir']?.toString() ?? 'build/source_probe',
      dryRun: json['dryRun'] == true,
      novelOnly: json['novelOnly'] != false,
      dedupeByUrl: json['dedupeByUrl'] == true,
      includeLogs: json['includeLogs'] == true,
      failLogLines: intValue(
        json['failLogLines']?.toString(),
        40,
      ).clamp(0, 1000),
      help: json['help'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'inputs': inputs,
      'keyword': keyword,
      'concurrency': concurrency,
      'timeoutSeconds': timeoutSeconds,
      'limit': limit,
      'offset': offset,
      'nameFilter': nameFilter,
      'urlFilter': urlFilter,
      'outDir': outDir,
      'dryRun': dryRun,
      'novelOnly': novelOnly,
      'dedupeByUrl': dedupeByUrl,
      'includeLogs': includeLogs,
      'failLogLines': failLogLines,
    };
  }

  ProbeOptions copyWith({bool? dryRun}) {
    return ProbeOptions(
      inputs: inputs,
      keyword: keyword,
      concurrency: concurrency,
      timeoutSeconds: timeoutSeconds,
      limit: limit,
      offset: offset,
      nameFilter: nameFilter,
      urlFilter: urlFilter,
      outDir: outDir,
      dryRun: dryRun ?? this.dryRun,
      novelOnly: novelOnly,
      dedupeByUrl: dedupeByUrl,
      includeLogs: includeLogs,
      failLogLines: failLogLines,
      help: help,
    );
  }
}

int intValue(String? value, int fallback) {
  return int.tryParse(value ?? '') ?? fallback;
}

const sourceProbeUsage = '''
Usage:
  flutter pub run tool/source_probe.dart [options] <source.json|directory>...

Options:
  --keyword <text>       Test keyword. Default: 斗破苍穹
  --concurrency <n>      Concurrent live tests. Default: 2
  --timeout <seconds>    Timeout per source. Default: 45
  --limit <n>            Test at most n selected sources.
  --offset <n>           Skip n selected sources.
  --name <text>          Only test sources whose name contains text.
  --url <text>           Only test sources whose source URL contains text.
  --out <dir>            Output directory. Default: build/source_probe
  --dry-run              Static feature scan only; no network requests.
  --all-types            Include non-novel sources. Default only bookSourceType 0.
  --dedupe               Keep only one source per bookSourceUrl.
  --include-logs         Store all step logs in JSON.
  --fail-log-lines <n>   Store first n failing-step logs in failure markdown. Default: 40
  --help                 Show this message.

Examples:
  flutter pub run tool/source_probe.dart --dry-run --out build/probe_static C:\\Users\\me\\Desktop\\sources.json
  flutter pub run tool/source_probe.dart --limit 100 --concurrency 2 --timeout 45 C:\\Users\\me\\Desktop\\sources.json
''';
