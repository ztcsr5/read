import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

final purifyRulesProvider =
    StateNotifierProvider<PurifyRulesNotifier, List<String>>((ref) {
      return PurifyRulesNotifier();
    });

class PurifyRulesNotifier extends StateNotifier<List<String>> {
  static const _key = 'purify_rules_list';
  static const _subscriptionsKey = 'purify_rules_subscriptions';

  PurifyRulesNotifier() : super([]) {
    _loadRules();
  }

  Future<void> _loadRules() async {
    final prefs = await SharedPreferences.getInstance();
    final rules = prefs.getStringList(_key) ?? [];
    state = rules;
  }

  Future<void> addRule(String rule) async {
    final text = rule.trim();
    if (text.isEmpty || state.contains(text)) return;
    await _saveRules([...state, text]);
  }

  Future<void> removeRule(String rule) async {
    await _saveRules(state.where((r) => r != rule).toList());
  }

  Future<int> importFromUrl(String url, {bool remember = false}) async {
    final normalized = url.trim();
    if (normalized.isEmpty) return 0;
    final response = await http.get(
      Uri.parse(normalized),
      headers: const {
        'User-Agent':
            'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
        'Accept': 'application/json,text/plain,*/*',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    final count = await importFromJsonText(text);
    if (remember) await addSubscription(normalized, refresh: false);
    return count;
  }

  Future<int> importFromJsonText(String text) async {
    final normalized = _extractFirstJsonValue(_stripBom(text).trim()) ?? text;
    final parsed = jsonDecode(normalized);
    final rules = _extractRules(parsed).toSet().toList();
    if (rules.isEmpty) return 0;
    final merged = [...state];
    final oldLength = merged.length;
    for (final rule in rules) {
      if (!merged.contains(rule)) merged.add(rule);
    }
    await _saveRules(merged);
    return merged.length - oldLength;
  }

  Future<List<String>> getSubscriptions() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_subscriptionsKey) ?? [];
  }

  Future<int> addSubscription(String url, {bool refresh = true}) async {
    final normalized = url.trim();
    if (normalized.isEmpty) return 0;
    final prefs = await SharedPreferences.getInstance();
    final subscriptions = prefs.getStringList(_subscriptionsKey) ?? [];
    if (!subscriptions.contains(normalized)) {
      subscriptions.add(normalized);
      await prefs.setStringList(_subscriptionsKey, subscriptions);
    }
    return refresh ? importFromUrl(normalized) : 0;
  }

  Future<void> removeSubscription(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final subscriptions = prefs.getStringList(_subscriptionsKey) ?? [];
    subscriptions.remove(url);
    await prefs.setStringList(_subscriptionsKey, subscriptions);
  }

  Future<int> refreshSubscriptions() async {
    final subscriptions = await getSubscriptions();
    var imported = 0;
    for (final url in subscriptions) {
      imported += await importFromUrl(url);
    }
    return imported;
  }

  Future<void> _saveRules(List<String> rules) async {
    state = rules;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, rules);
  }

  Iterable<String> _extractRules(dynamic value) sync* {
    if (value == null) return;
    if (value is String) {
      final text = value.trim();
      if (text.isNotEmpty) yield text;
      return;
    }
    if (value is List) {
      for (final item in value) {
        yield* _extractRules(item);
      }
      return;
    }
    if (value is Map) {
      final map = value.map((key, item) => MapEntry(key.toString(), item));
      final direct = _firstText(map, const [
        'rule',
        'regex',
        'pattern',
        'replaceRegex',
        'match',
        'search',
        'sourceRegex',
        'content',
      ]);
      if (direct.isNotEmpty) {
        final replacement = _firstText(map, const [
          'replacement',
          'replace',
          'replaceWith',
          'value',
          'target',
        ]);
        yield replacement.isEmpty || direct.contains('##')
            ? direct
            : '$direct##$replacement';
      }
      for (final key in const [
        'rules',
        'data',
        'items',
        'list',
        'replaceRules',
        'purifyRules',
        'contentReplaceRules',
      ]) {
        if (map.containsKey(key)) yield* _extractRules(map[key]);
      }
    }
  }

  String _firstText(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  String _stripBom(String text) {
    return text.startsWith('\ufeff') ? text.substring(1) : text;
  }

  String? _extractFirstJsonValue(String text) {
    final src = _stripBom(text).trim();
    final start = src.indexOf(RegExp(r'[\[{]'));
    if (start < 0) return null;

    final stack = <int>[];
    var inString = false;
    var escaping = false;
    for (var i = start; i < src.length; i++) {
      final code = src.codeUnitAt(i);
      if (inString) {
        if (escaping) {
          escaping = false;
        } else if (code == 0x5c) {
          escaping = true;
        } else if (code == 0x22) {
          inString = false;
        }
        continue;
      }
      if (code == 0x22) {
        inString = true;
      } else if (code == 0x5b) {
        stack.add(0x5d);
      } else if (code == 0x7b) {
        stack.add(0x7d);
      } else if (code == 0x5d || code == 0x7d) {
        if (stack.isEmpty || stack.last != code) return null;
        stack.removeLast();
        if (stack.isEmpty) return src.substring(start, i + 1);
      }
    }
    return null;
  }
}
