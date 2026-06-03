import 'dart:convert';

import '../../../data/models/book_source.dart';

class SourceRepairResult {
  final BookSource source;
  final List<String> changes;

  const SourceRepairResult({required this.source, required this.changes});
}

class SourceAutoRepairService {
  static BookSource repair(BookSource source) =>
      repairWithReport(source).source;

  static SourceRepairResult repairWithReport(BookSource source) {
    final repaired = source.duplicate();
    final changes = <String>[];

    repaired.ruleSearch = _repairRuleJson(
      repaired.ruleSearch,
      'ruleSearch',
      changes,
      aliases: const {
        'bookListSearch': 'bookList',
        'nameSearch': 'name',
        'bookUrlSearch': 'bookUrl',
      },
    );
    repaired.ruleBookInfo = _repairRuleJson(
      repaired.ruleBookInfo,
      'ruleBookInfo',
      changes,
      aliases: const {
        'nameInfo': 'name',
        'authorInfo': 'author',
        'coverUrlInfo': 'coverUrl',
        'introInfo': 'intro',
        'tocUrlInfo': 'tocUrl',
        'catalogUrlInfo': 'tocUrl',
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
      },
    );
    repaired.ruleContent = _repairRuleJson(
      repaired.ruleContent,
      'ruleContent',
      changes,
      aliases: const {
        'contentText': 'content',
        'contentHtml': 'content',
        'nextContentUrlContent': 'nextContentUrl',
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

    if (repaired.searchUrl != null) {
      final normalized = _normalizeControlWhitespace(repaired.searchUrl!);
      if (normalized != repaired.searchUrl) {
        repaired.searchUrl = normalized;
        changes.add('searchUrl: 清理换行和不可见控制字符');
      }
    }
    if (repaired.exploreUrl != null) {
      final normalized = _normalizeControlWhitespace(repaired.exploreUrl!);
      if (normalized != repaired.exploreUrl) {
        repaired.exploreUrl = normalized;
        changes.add('exploreUrl: 清理换行和不可见控制字符');
      }
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

      final encoded = jsonEncode(repaired);
      if (encoded != ruleJson) changed = true;
      if (changed && !changes.any((c) => c.startsWith('$fieldName: 规范化'))) {
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
    return repaired.trim();
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
}
