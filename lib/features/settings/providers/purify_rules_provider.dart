import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final purifyRulesProvider = StateNotifierProvider<PurifyRulesNotifier, List<String>>((ref) {
  return PurifyRulesNotifier();
});

class PurifyRulesNotifier extends StateNotifier<List<String>> {
  static const _key = 'purify_rules_list';

  PurifyRulesNotifier() : super([]) {
    _loadRules();
  }

  Future<void> _loadRules() async {
    final prefs = await SharedPreferences.getInstance();
    final rules = prefs.getStringList(_key) ?? [];
    state = rules;
  }

  Future<void> addRule(String rule) async {
    if (rule.trim().isEmpty || state.contains(rule)) return;
    final newState = [...state, rule];
    state = newState;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, newState);
  }

  Future<void> removeRule(String rule) async {
    final newState = state.where((r) => r != rule).toList();
    state = newState;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, newState);
  }
}
