import 'package:html/dom.dart';
import 'package:html/parser.dart' show parse;
import 'package:json_path/json_path.dart';

import 'legado_request_builder.dart';

class LegadoRuleAnalyzer {
  const LegadoRuleAnalyzer();

  LegadoRulePlan analyze(String rule) {
    final text = rule.trim();
    final parts = text
        .split('&&')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    return LegadoRulePlan(
      raw: rule,
      parts: parts.isEmpty ? (text.isEmpty ? const <String>[] : <String>[text]) : parts,
      hasJs: text.contains('@js:') || text.contains('<js>') || text.startsWith('{{'),
      isJsonPath: text.startsWith(r'$.') || text.startsWith(r'$['),
      isXPath: text.startsWith('//') || text.startsWith('./'),
      isRegex: text.startsWith(':') || text.contains('##') || text.contains('%%'),
      isCssLike: _looksCssLike(text),
    );
  }

  static bool _looksCssLike(String text) {
    if (text.isEmpty) return false;
    if (text.startsWith('@') || text.startsWith(r'$.') || text.startsWith('//')) {
      return false;
    }
    return RegExp(r'[#.>\[\]\w-]').hasMatch(text);
  }
}

class LegadoRulePlan {
  final String raw;
  final List<String> parts;
  final bool hasJs;
  final bool isJsonPath;
  final bool isXPath;
  final bool isRegex;
  final bool isCssLike;

  const LegadoRulePlan({
    required this.raw,
    required this.parts,
    required this.hasJs,
    required this.isJsonPath,
    required this.isXPath,
    required this.isRegex,
    required this.isCssLike,
  });
}

class LegadoURLResolver {
  const LegadoURLResolver();

  String resolve(String baseUrl, String value) {
    final text = value.trim();
    if (text.isEmpty) return baseUrl;
    if (text.startsWith('javascript:') || text == '#') return '';
    if (text.startsWith('//')) {
      final scheme = Uri.tryParse(baseUrl)?.scheme;
      return '${scheme == null || scheme.isEmpty ? 'https' : scheme}:$text';
    }
    if (text.startsWith('/')) {
      final base = Uri.tryParse(baseUrl);
      if (base != null && base.hasScheme && base.host.isNotEmpty) {
        return base.replace(path: text, query: '', fragment: '').toString();
      }
    }
    return LegadoRequestBuilder.resolveUrl(baseUrl, text);
  }

  String bestCandidate(String value) {
    final candidates = value
        .split(RegExp(r'[\r\n\t]+|(?=https?://)'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (candidates.isEmpty) return value.trim();
    if (candidates.length == 1) return candidates.first;
    candidates.sort((a, b) => _score(b).compareTo(_score(a)));
    return candidates.first;
  }

  int _score(String value) {
    final lower = value.toLowerCase();
    var score = 0;
    if (lower.startsWith('http')) score += 10;
    if (RegExp(r'/(book|novel|info|detail|article|shu|xiaoshuo|txt)/').hasMatch(lower)) {
      score += 20;
    }
    if (RegExp(r'\d{2,}').hasMatch(lower)) score += 3;
    if (lower.contains('/search') || lower.contains('/tag/') || lower.contains('/rank')) {
      score -= 20;
    }
    return score - '/'.allMatches(lower).length;
  }
}

class LegadoJsonPathResolver {
  const LegadoJsonPathResolver();

  List<dynamic> resolve(dynamic json, String rule) {
    try {
      return JsonPath(rule).read(json).map((match) => match.value).toList();
    } catch (_) {
      return const <dynamic>[];
    }
  }
}

class LegadoRegexResolver {
  const LegadoRegexResolver();

  List<String> resolve(String input, String pattern) {
    try {
      return RegExp(pattern, dotAll: true)
          .allMatches(input)
          .map((match) => match.groupCount > 0 ? match.group(1) ?? '' : match.group(0) ?? '')
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
  }
}

class LegadoJSoupResolver {
  const LegadoJSoupResolver();

  List<Element> select(String html, String selector) {
    try {
      if (selector.trim().isEmpty) return const <Element>[];
      return parse(html).querySelectorAll(selector);
    } catch (_) {
      return const <Element>[];
    }
  }

  String text(String html, String selector) {
    return select(html, selector).map((element) => element.text.trim()).join('\n');
  }
}

class LegadoXPathResolver {
  const LegadoXPathResolver();

  List<String> resolve(String input, String rule) {
    // The existing parser has its own XPath-like fallback. This adapter keeps the
    // resolver boundary explicit without replacing those battle-tested paths.
    return const <String>[];
  }
}

class LegadoRuleResolver {
  static const analyzer = LegadoRuleAnalyzer();
  static const url = LegadoURLResolver();
  static const jsonPath = LegadoJsonPathResolver();
  static const regex = LegadoRegexResolver();
  static const jsoup = LegadoJSoupResolver();
  static const xpath = LegadoXPathResolver();

  const LegadoRuleResolver();

  LegadoRulePlan analyze(String rule) => analyzer.analyze(rule);

  String resolveUrl(String baseUrl, String value) => url.resolve(baseUrl, value);

  String bestUrlCandidate(String value) => url.bestCandidate(value);

  List<dynamic> resolveJson(dynamic json, String rule) => jsonPath.resolve(json, rule);

  List<Element> select(String html, String selector) => jsoup.select(html, selector);

  List<String> resolveRegex(String input, String pattern) => regex.resolve(input, pattern);
}
