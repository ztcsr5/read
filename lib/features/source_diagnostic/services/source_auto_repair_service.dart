import 'dart:convert';
import '../../../data/models/book_source.dart';

class SourceAutoRepairService {
  static BookSource repair(BookSource source) {
    final repaired = source;

    if (repaired.ruleSearch != null) repaired.ruleSearch = _repairRuleString(repaired.ruleSearch!);
    if (repaired.ruleBookInfo != null) repaired.ruleBookInfo = _repairRuleString(repaired.ruleBookInfo!);
    if (repaired.ruleToc != null) repaired.ruleToc = _repairRuleString(repaired.ruleToc!);
    if (repaired.ruleContent != null) repaired.ruleContent = _repairRuleString(repaired.ruleContent!);

    repaired.ruleSearch = _translateV2Syntax(repaired.ruleSearch);
    repaired.ruleBookInfo = _translateV2Syntax(repaired.ruleBookInfo);
    repaired.ruleToc = _translateV2Syntax(repaired.ruleToc);
    repaired.ruleContent = _translateV2Syntax(repaired.ruleContent);

    return repaired;
  }

  static String? _translateV2Syntax(String? ruleJson) {
    if (ruleJson == null || ruleJson.isEmpty) return ruleJson;
    try {
      final map = jsonDecode(ruleJson);
      if (map is Map<String, dynamic>) {
        final newMap = <String, dynamic>{};
        map.forEach((key, value) {
          if (value is String) {
            newMap[key] = _convertV2Selector(value);
          } else {
            newMap[key] = value;
          }
        });
        return jsonEncode(newMap);
      }
    } catch (_) {}
    return ruleJson;
  }

  static String _convertV2Selector(String selector) {
    var s = selector;
    s = s.replaceAllMapped(RegExp(r'\[id=([a-zA-Z0-9_\-]+)\]'), (m) => '#${m.group(1)}');
    s = s.replaceAllMapped(RegExp(r'\[class=([a-zA-Z0-9_\-]+)\]'), (m) => '.${m.group(1)}');
    return s;
  }

  static String _repairRuleString(String ruleJson) {
    try {
      final decoded = jsonDecode(ruleJson);
      if (decoded is Map<String, dynamic>) {
        final newMap = <String, dynamic>{};
        decoded.forEach((key, value) {
          if (value is String) {
            var val = value.replaceAll('\r', '').replaceAll('\n', '').replaceAll('\t', ' ');
            while (val.contains('  ')) {
              val = val.replaceAll('  ', ' ');
            }
            newMap[key] = val.trim();
          } else {
            newMap[key] = value;
          }
        });
        return jsonEncode(newMap);
      }
    } catch (_) {}
    return ruleJson;
  }

  static BookSource reverseChapters(BookSource source) {
    if (source.ruleToc == null) return source;
    try {
      final map = jsonDecode(source.ruleToc!) as Map<String, dynamic>;
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
        source.ruleToc = jsonEncode(map);
      }
    } catch (_) {}
    return source;
  }
}
