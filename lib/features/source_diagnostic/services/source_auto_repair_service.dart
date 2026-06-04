import 'dart:convert';

import '../../../data/models/book_source.dart';
import '../../../data/models/diagnostic_report.dart';

class SourceRepairResult {
  final BookSource source;
  final List<String> changes;

  const SourceRepairResult({required this.source, required this.changes});
}

class SourceAutoRepairService {
  static BookSource repair(BookSource source) =>
      repairWithReport(source).source;

  static SourceRepairResult repairWithReport(
    BookSource source, {
    DiagnosticReport? report,
  }) {
    final repaired = source.duplicate();
    final changes = <String>[];

    repaired.ruleSearch = _repairRuleJson(
      repaired.ruleSearch,
      'ruleSearch',
      changes,
      aliases: const {
        'bookListSearch': 'bookList',
        'nameSearch': 'name',
        'titleSearch': 'name',
        'bookNameSearch': 'name',
        'bookUrlSearch': 'bookUrl',
        'urlSearch': 'bookUrl',
        'linkSearch': 'bookUrl',
        'detailUrlSearch': 'bookUrl',
        'bookListRule': 'bookList',
        'nameRule': 'name',
        'titleRule': 'name',
        'bookNameRule': 'name',
        'bookUrlRule': 'bookUrl',
        'urlRule': 'bookUrl',
        'authorSearch': 'author',
        'authorRule': 'author',
        'coverSearch': 'coverUrl',
        'coverUrlSearch': 'coverUrl',
        'coverUrlRule': 'coverUrl',
        'coverRule': 'coverUrl',
        'picUrlSearch': 'coverUrl',
        'introSearch': 'intro',
        'descSearch': 'intro',
        'introRule': 'intro',
        'descRule': 'intro',
        'list': 'bookList',
        'books': 'bookList',
        'items': 'bookList',
        'data': 'bookList',
        'result': 'bookList',
        'results': 'bookList',
        'records': 'bookList',
        'rows': 'bookList',
        'searchList': 'bookList',
        'title': 'name',
        'bookName': 'name',
        'url': 'bookUrl',
        'link': 'bookUrl',
        'detailUrl': 'bookUrl',
        'cover': 'coverUrl',
        'pic': 'coverUrl',
        'picUrl': 'coverUrl',
        'imgUrl': 'coverUrl',
        'desc': 'intro',
      },
    );
    repaired.ruleBookInfo = _repairRuleJson(
      repaired.ruleBookInfo,
      'ruleBookInfo',
      changes,
      aliases: const {
        'nameInfo': 'name',
        'titleInfo': 'name',
        'bookNameInfo': 'name',
        'authorInfo': 'author',
        'coverUrlInfo': 'coverUrl',
        'coverInfo': 'coverUrl',
        'introInfo': 'intro',
        'descInfo': 'intro',
        'tocUrlInfo': 'tocUrl',
        'catalogUrlInfo': 'tocUrl',
        'bookUrlInfo': 'tocUrl',
        'urlInfo': 'tocUrl',
        'detailUrlInfo': 'tocUrl',
        'title': 'name',
        'bookName': 'name',
        'desc': 'intro',
        'cover': 'coverUrl',
        'bookUrl': 'tocUrl',
      },
    );
    repaired.ruleToc = _repairRuleJson(
      repaired.ruleToc,
      'ruleToc',
      changes,
      aliases: const {
        'chapterListTOC': 'chapterList',
        'chapterListToc': 'chapterList',
        'chapterNameTOC': 'chapterName',
        'chapterNameToc': 'chapterName',
        'chapterUrlTOC': 'chapterUrl',
        'chapterUrlToc': 'chapterUrl',
        'nextTocUrlTOC': 'nextTocUrl',
        'nextTocUrlToc': 'nextTocUrl',
        'chapterListRule': 'chapterList',
        'chapterNameRule': 'chapterName',
        'chapterUrlRule': 'chapterUrl',
        'tocList': 'chapterList',
        'catalogList': 'chapterList',
        'list': 'chapterList',
        'chapters': 'chapterList',
        'chapterListData': 'chapterList',
        'chapterItems': 'chapterList',
        'items': 'chapterList',
        'chapterTitle': 'chapterName',
        'chapter_name': 'chapterName',
        'chapter_title': 'chapterName',
        'title': 'chapterName',
        'name': 'chapterName',
        'chapter_url': 'chapterUrl',
        'contentUrl': 'chapterUrl',
        'path': 'chapterUrl',
        'url': 'chapterUrl',
        'link': 'chapterUrl',
      },
    );
    repaired.ruleContent = _repairRuleJson(
      repaired.ruleContent,
      'ruleContent',
      changes,
      aliases: const {
        'contentText': 'content',
        'contentHtml': 'content',
        'contentRule': 'content',
        'contentUrl': 'content',
        'body': 'content',
        'text': 'content',
        'html': 'content',
        'nextContentUrlContent': 'nextContentUrl',
        'nextUrl': 'nextContentUrl',
      },
    );
    repaired.ruleExplore = _repairRuleJson(
      repaired.ruleExplore,
      'ruleExplore',
      changes,
    );
    repaired.customConfig = _repairRuleJson(
      repaired.customConfig,
      'customConfig',
      changes,
    );

    repaired.searchUrl = _repairUrlRule(
      repaired.searchUrl,
      'searchUrl',
      changes,
    );
    repaired.exploreUrl = _repairUrlRule(
      repaired.exploreUrl,
      'exploreUrl',
      changes,
    );

    if (report != null) {
      _applyDiagnosticSuggestions(repaired, report.issues, changes);
    }

    return SourceRepairResult(source: repaired, changes: changes);
  }

  static BookSource reverseChapters(BookSource source) {
    final repaired = source.duplicate();
    if (repaired.ruleToc == null) return repaired;
    try {
      final decoded = jsonDecode(repaired.ruleToc!);
      if (decoded is! Map) return repaired;
      final map = decoded.map((key, value) => MapEntry(key.toString(), value));
      var chapterListRule = map['chapterList']?.toString() ?? '';
      if (chapterListRule.isNotEmpty) {
        if (chapterListRule.startsWith('-')) {
          map['chapterList'] = chapterListRule.substring(1).trim();
        } else {
          if (chapterListRule.startsWith('+')) {
            chapterListRule = chapterListRule.substring(1);
          }
          map['chapterList'] = '-$chapterListRule';
        }
        repaired.ruleToc = jsonEncode(map);
      }
    } catch (_) {}
    return repaired;
  }

  static String? _repairRuleJson(
    String? ruleJson,
    String fieldName,
    List<String> changes, {
    Map<String, String> aliases = const {},
  }) {
    if (ruleJson == null || ruleJson.trim().isEmpty) return ruleJson;
    try {
      final decoded = jsonDecode(ruleJson);
      if (decoded is! Map) return _normalizeControlWhitespace(ruleJson);

      final map = decoded.map((key, value) => MapEntry(key.toString(), value));
      final repaired = <String, dynamic>{};
      var changed = false;

      for (final entry in map.entries) {
        final targetKey = aliases[entry.key] ?? entry.key;
        if (targetKey != entry.key) {
          changed = true;
          changes.add('$fieldName: ${entry.key} -> $targetKey');
        }

        final value = _repairRuleValue(entry.value);
        if (value != entry.value) changed = true;

        if (!repaired.containsKey(targetKey) ||
            _isEmptyValue(repaired[targetKey])) {
          repaired[targetKey] = value;
        }
      }

      if (_applyFieldDefaults(fieldName, repaired, changes)) {
        changed = true;
      }

      final encoded = jsonEncode(repaired);
      if (encoded != ruleJson) changed = true;
      if (changed &&
          !changes.any((change) => change.startsWith('$fieldName: 规范化'))) {
        changes.add('$fieldName: 规范化 JSON 与规则空白');
      }
      return encoded;
    } catch (_) {
      final normalized = _normalizeControlWhitespace(ruleJson);
      if (normalized != ruleJson) {
        changes.add('$fieldName: 清理不可见控制字符');
      }
      return normalized;
    }
  }

  static dynamic _repairRuleValue(dynamic value) {
    if (value is Map) {
      return value.map(
        (key, child) => MapEntry(key.toString(), _repairRuleValue(child)),
      );
    }
    if (value is List) {
      return value.map(_repairRuleValue).toList();
    }
    if (value is! String) return value;

    if (_containsJavascript(value)) {
      return value.trim();
    }

    var repaired = _normalizeControlWhitespace(value);
    repaired = _convertV2Selector(repaired);
    repaired = _normalizeLegacyClassSelector(repaired);
    repaired = _prefixLikelyXPath(repaired);
    return repaired.trim();
  }

  static bool _applyFieldDefaults(
    String fieldName,
    Map<String, dynamic> map,
    List<String> changes,
  ) {
    var changed = false;

    bool isEmpty(String key) => _isEmptyValue(map[key]);
    void putIfEmpty(String key, String value) {
      if (!isEmpty(key)) return;
      map[key] = value;
      changed = true;
      changes.add('$fieldName: 补齐 $key 默认规则');
    }

    if (fieldName == 'ruleSearch') {
      final listRule = map['bookList']?.toString() ?? '';
      if (listRule.trim().isNotEmpty) {
        if (_looksLikeJsonRule(listRule)) {
          putIfEmpty('name', 'name');
          putIfEmpty('bookUrl', 'bookUrl');
        } else {
          putIfEmpty('name', 'a@text');
          putIfEmpty('bookUrl', 'a@href');
        }
      }
    } else if (fieldName == 'ruleBookInfo') {
      if (isEmpty('tocUrl') && !_isEmptyValue(map['bookUrl'])) {
        map['tocUrl'] = map['bookUrl'];
        changed = true;
        changes.add('$fieldName: bookUrl -> tocUrl');
      }
    } else if (fieldName == 'ruleToc') {
      final listRule = map['chapterList']?.toString() ?? '';
      if (listRule.trim().isNotEmpty) {
        if (_looksLikeJsonRule(listRule)) {
          putIfEmpty('chapterName', 'title');
          putIfEmpty('chapterUrl', 'url');
        } else {
          putIfEmpty('chapterName', '@text');
          putIfEmpty('chapterUrl', '@href');
        }
      }
    }

    return changed;
  }

  static String? _repairUrlRule(
    String? rule,
    String fieldName,
    List<String> changes,
  ) {
    if (rule == null) return null;
    if (_containsJavascript(rule)) return rule.trim();
    final normalized = _normalizeControlWhitespace(rule);
    if (normalized != rule) {
      changes.add('$fieldName: 清理换行和不可见控制字符');
    }
    return normalized;
  }

  static void _applyDiagnosticSuggestions(
    BookSource source,
    List<DiagnosticIssue> issues,
    List<String> changes,
  ) {
    for (final issue in issues) {
      final target = _targetFromIssue(issue);
      if (target == null) continue;

      final candidates = _extractSuggestedSelectors(issue);
      if (candidates.isEmpty) continue;
      final candidate = candidates.first;

      if (target == _RepairTarget.bookList) {
        source.ruleSearch = _writeRuleField(
          source.ruleSearch,
          'ruleSearch',
          'bookList',
          candidate,
          changes,
        );
      } else if (target == _RepairTarget.chapterList) {
        source.ruleToc = _writeRuleField(
          source.ruleToc,
          'ruleToc',
          'chapterList',
          candidate,
          changes,
        );
      } else if (target == _RepairTarget.content) {
        source.ruleContent = _writeRuleField(
          source.ruleContent,
          'ruleContent',
          'content',
          candidate,
          changes,
        );
      }
    }
  }

  static _RepairTarget? _targetFromIssue(DiagnosticIssue issue) {
    final field = (issue.field ?? '').trim();
    final stage = issue.stage.trim();
    final text = '${issue.reason}\n${issue.suggestion}'.toLowerCase();
    if (field == 'bookList' ||
        field == 'ruleSearch' ||
        stage == 'search' ||
        text.contains('booklist') ||
        text.contains('列表选择器')) {
      return _RepairTarget.bookList;
    }
    if (field == 'chapterList' ||
        field == 'ruleToc' ||
        stage == 'toc' ||
        text.contains('chapterlist') ||
        text.contains('目录选择器')) {
      return _RepairTarget.chapterList;
    }
    if (field == 'content' ||
        field == 'ruleContent' ||
        stage == 'content' ||
        text.contains('rulecontent') ||
        text.contains('正文选择器')) {
      return _RepairTarget.content;
    }
    return null;
  }

  static List<String> _extractSuggestedSelectors(DiagnosticIssue issue) {
    final combined = '${issue.suggestion}\n${issue.htmlSnippet ?? ''}';
    final candidates = <String>[];

    void add(String? raw) {
      final value = _sanitizeSelectorCandidate(raw);
      if (value == null || !_looksLikeSelectorCandidate(value)) return;
      if (!candidates.contains(value)) candidates.add(value);
    }

    final replaceMatch = RegExp(
      r'''(?:替换为|新规则候选[:：]|备选规则[:：])\s*["“]?([^"”\n(（，,;；]+)''',
    ).firstMatch(combined);
    add(replaceMatch?.group(1));
    final withMatch = RegExp(
      r'''\bwith\s+["“]?([^"”\n(（，,;；]+)''',
      caseSensitive: false,
    ).firstMatch(combined);
    add(withMatch?.group(1));

    for (final match in RegExp(r'''["“]([^"”]+)["”]''').allMatches(combined)) {
      add(match.group(1));
    }

    final listPart = RegExp(
      r'''(?:列表选择器|目录选择器|正文选择器|候补 CSS 规则|可能替代)[^:：]*[:：]\s*([^\n]+)''',
    ).firstMatch(combined);
    if (listPart != null) {
      for (final part in listPart.group(1)!.split(RegExp(r'[，,;；]'))) {
        add(part);
      }
    }

    final generic = RegExp(
      r'''(@xpath:[^\s，,;；]+|//[^\s，,;；]+|[.#][A-Za-z_][A-Za-z0-9_\-]*(?:[ >+~]+(?:[.#]?[A-Za-z_][A-Za-z0-9_\-]*|\[[^\]]+\]))*(?:\s+[a-z][A-Za-z0-9_\-]*)?|(?:class|id|tag)\.[A-Za-z0-9_\-][A-Za-z0-9_.\-\s]*(?:@[A-Za-z0-9_()\-]+)?)''',
    ).allMatches(combined);
    for (final match in generic) {
      add(match.group(1));
    }

    final oldRule = issue.rule?.trim();
    if (oldRule != null && oldRule.isNotEmpty) {
      candidates.removeWhere((value) => value == oldRule);
    }
    return candidates;
  }

  static String? _sanitizeSelectorCandidate(String? raw) {
    if (raw == null) return null;
    var value = raw.trim();
    if (value.isEmpty) return null;
    value = value
        .replaceAll(RegExp(r'^(建议|使用|将|旧规则|新规则|候选)\s*'), '')
        .replaceAll(RegExp(r'\s*\(得分[:：]?\s*\d+.*$'), '')
        .replaceAll(RegExp(r'\s*（得分[:：]?\s*\d+.*$'), '')
        .replaceAll(RegExp(r'["“”]+'), '')
        .trim();
    while (value.endsWith('.') ||
        value.endsWith('。') ||
        value.endsWith(',') ||
        value.endsWith('，') ||
        value.endsWith(';') ||
        value.endsWith('；') ||
        value.endsWith(':') ||
        value.endsWith('：')) {
      value = value.substring(0, value.length - 1).trim();
    }
    if (value.contains(' -> ')) value = value.split(' -> ').last.trim();
    if (value.contains('=>')) value = value.split('=>').last.trim();
    return value;
  }

  static String? _writeRuleField(
    String? ruleJson,
    String fieldName,
    String key,
    String value,
    List<String> changes,
  ) {
    final map = <String, dynamic>{};
    if (ruleJson != null && ruleJson.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(ruleJson);
        if (decoded is Map) {
          map.addAll(decoded.map((k, v) => MapEntry(k.toString(), v)));
        }
      } catch (_) {
        return ruleJson;
      }
    }
    final old = map[key]?.toString() ?? '';
    if (old == value) return ruleJson;
    map[key] = value;
    changes.add('$fieldName: 应用诊断候选 $key=$value');
    return jsonEncode(map);
  }

  static bool _containsJavascript(String text) {
    final lower = text.toLowerCase();
    return lower.contains('<js') ||
        lower.contains('@js') ||
        lower.contains('java.') ||
        lower.contains('function') ||
        lower.contains('=>');
  }

  static bool _isEmptyValue(dynamic value) =>
      value == null || (value is String && value.trim().isEmpty);

  static String _normalizeControlWhitespace(String text) {
    var value = text
        .replaceAll('\r', '')
        .replaceAll('\n', '')
        .replaceAll('\t', ' ')
        .replaceAll('\u0000', '')
        .replaceAll('\u200b', '');
    while (value.contains('  ')) {
      value = value.replaceAll('  ', ' ');
    }
    return value;
  }

  static String _convertV2Selector(String selector) {
    var s = selector;
    s = s.replaceAllMapped(
      RegExp(r'\[id=([a-zA-Z0-9_\-]+)\]'),
      (m) => '#${m.group(1)}',
    );
    s = s.replaceAllMapped(
      RegExp(r'\[class=([a-zA-Z0-9_\-]+)\]'),
      (m) => '.${m.group(1)}',
    );
    return s;
  }

  static String _normalizeLegacyClassSelector(String rule) {
    final parts = rule.split('@');
    if (parts.isEmpty) return rule;
    final selector = parts.first.trim();
    final match = RegExp(
      r'^class\.([A-Za-z0-9_\-]+)\s+(.+)$',
    ).firstMatch(selector);
    if (match == null) return rule;

    final tail = match.group(2)?.trim() ?? '';
    final classTokens = tail
        .split(RegExp(r'\s+'))
        .where((token) => RegExp(r'^[A-Za-z0-9_\-]+$').hasMatch(token))
        .toList();
    if (classTokens.isEmpty || classTokens.join(' ') != tail) return rule;

    parts[0] = 'class.${match.group(1)}.${classTokens.join('.')}';
    return parts.join('@');
  }

  static String _prefixLikelyXPath(String rule) {
    final text = rule.trim();
    if (text.startsWith('@xpath:') || text.startsWith('xpath:')) return rule;
    final looksXPath =
        text.startsWith('//') ||
        text.startsWith('./') ||
        text.contains('/text()') ||
        text.contains('/@') ||
        RegExp(r'\b(contains|position|last)\s*\(').hasMatch(text);
    return looksXPath ? '@xpath:$text' : rule;
  }

  static bool _looksLikeJsonRule(String rule) {
    final text = rule.trim();
    if (text.startsWith('@json:') ||
        text.startsWith(r'$.') ||
        text.startsWith(r'$[')) {
      return true;
    }
    if (text.startsWith('.') ||
        text.startsWith('#') ||
        text.startsWith('class.') ||
        text.startsWith('id.') ||
        text.startsWith('tag.') ||
        text.contains('@href') ||
        text.contains('@text')) {
      return false;
    }
    return RegExp(r'^[A-Za-z_][A-Za-z0-9_]*(\.|\[)').hasMatch(text);
  }

  static bool _looksLikeSelectorCandidate(String text) {
    if (text.isEmpty || text.length > 120 || text.contains('\n')) return false;
    if (text.contains('@js') || text.contains('<js>')) return false;
    if (RegExp(r'^#[0-9]+$').hasMatch(text)) return false;
    return text.startsWith('.') ||
        text.startsWith('#') ||
        text.startsWith('class.') ||
        text.startsWith('id.') ||
        text.startsWith('tag.') ||
        text.startsWith('@xpath:') ||
        text.startsWith('//');
  }
}

enum _RepairTarget { bookList, chapterList, content }
