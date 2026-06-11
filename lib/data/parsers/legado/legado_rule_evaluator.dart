import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:json_path/json_path.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

import 'legado_js_engine.dart';

class LegadoRuleEvaluator {
  static const _knownAttrs = {
    'text',
    'textNodes',
    'ownText',
    'html',
    'outerHtml',
    'all',
    'attr',
    'href',
    'src',
    'data-src',
    'data-original',
    'content',
    'value',
    'title',
    'alt',
  };

  static List<String>? _splitTopLevelOperator(String rule, String operator) {
    final parts = <String>[];
    var start = 0;
    var parenDepth = 0;
    var bracketDepth = 0;
    var braceDepth = 0;
    var inJsBlock = false;
    var inPostProcessor = false;
    String? quote;

    for (var i = 0; i < rule.length; i++) {
      if (inJsBlock) {
        if (rule.startsWith('</js>', i)) {
          inJsBlock = false;
          i += 4;
        }
        continue;
      }
      if (rule.startsWith('<js>', i)) {
        inJsBlock = true;
        i += 3;
        continue;
      }
      if (inPostProcessor) continue;
      if (quote != null) {
        if (rule[i] == '\\') {
          i++;
        } else if (rule[i] == quote) {
          quote = null;
        }
        continue;
      }
      final ch = rule[i];
      if (ch == '"' || ch == "'" || ch == '`') {
        quote = ch;
        continue;
      }
      if (rule.startsWith('@js:', i) || rule.startsWith('##', i)) {
        inPostProcessor = true;
        continue;
      }
      switch (ch) {
        case '(':
          parenDepth++;
          break;
        case ')':
          if (parenDepth > 0) parenDepth--;
          break;
        case '[':
          bracketDepth++;
          break;
        case ']':
          if (bracketDepth > 0) bracketDepth--;
          break;
        case '{':
          braceDepth++;
          break;
        case '}':
          if (braceDepth > 0) braceDepth--;
          break;
      }
      if (parenDepth == 0 &&
          bracketDepth == 0 &&
          braceDepth == 0 &&
          rule.startsWith(operator, i)) {
        parts.add(rule.substring(start, i).trim());
        i += operator.length - 1;
        start = i + 1;
      }
    }

    if (parts.isEmpty) return null;
    parts.add(rule.substring(start).trim());
    return parts.where((part) => part.isNotEmpty).toList();
  }

  static String extractJsonValue(dynamic json, String rule) {
    return _extractJsonValueInternal(json, rule);
  }

  static String _extractJsonValueInternal(
    dynamic json,
    String rule, {
    bool applyPut = true,
  }) {
    if (rule.isEmpty) return '';
    if (applyPut) {
      rule = _applyJsonPutDirectives(json, rule);
    }
    rule = _replaceGetDirectives(rule);
    if (isJsOnlyRule(rule)) {
      try {
        final jsonStr = json is String ? json : jsonEncode(json);
        final value = LegadoJsEngine().evaluate(
          rule,
          variables: {'result': jsonStr},
        );
        if (value.trim().isNotEmpty) return value.trim();
      } catch (_) {
        return '';
      }
    }

    // Handle || (fallback)
    final fallbackParts = _splitTopLevelOperator(rule, '||');
    if (fallbackParts != null) {
      for (final part in fallbackParts) {
        final val = _extractJsonValueInternal(json, part.trim());
        if (val.isNotEmpty) return val;
      }
      return '';
    }

    // Handle && (splicing)
    final spliceParts = _splitTopLevelOperator(rule, '&&');
    if (spliceParts != null) {
      final results = <String>[];
      for (final part in spliceParts) {
        final val = _extractJsonValueInternal(json, part.trim());
        if (val.isNotEmpty) results.add(val);
      }
      return results.join('\n');
    }

    // Handle %% (cross merge)
    final mergeParts = _splitTopLevelOperator(rule, '%%');
    if (mergeParts != null) {
      final results = <String>[];
      for (final part in mergeParts) {
        final val = _extractJsonValueInternal(json, part.trim());
        if (val.isNotEmpty) results.add(val);
      }
      return results.join('\n');
    }

    var ruleText = rule;
    if (json is Map || json is List) {
      if (_containsJsonTemplate(ruleText)) {
        final templateRule = _stripJsonRulePrefix(ruleText);
        return applyPostProcessors(
          _interpolateJsonTemplate(json, templateRule),
          ruleText,
          originalJson: json,
        );
      }
      if (_containsNonBracketJsonPath(ruleText)) {
        ruleText = _interpolateNonBracketJsonPath(json, ruleText);
      }
    }

    final cleaned = stripPostProcessors(ruleText);
    if (cleaned.isEmpty) return '';
    var value = applyPostProcessors(
      _extractSingleJsonValue(json, cleaned),
      ruleText,
      originalJson: json,
    );
    if (value.isEmpty && !cleaned.contains(r'$')) {
      value = applyPostProcessors(cleaned, ruleText, originalJson: json);
    }
    return value;
  }

  static List<dynamic> extractJsonNodes(dynamic json, String rule) {
    if (rule.isEmpty) return const [];
    rule = _applyJsonPutDirectives(json, rule);
    rule = _replaceGetDirectives(rule);
    if (isJsOnlyRule(rule)) {
      try {
        final jsonStr = json is String ? json : jsonEncode(json);
        final value = LegadoJsEngine().evaluate(
          rule,
          variables: {'result': jsonStr},
        );
        final decoded = jsonDecode(value);
        if (decoded is List) return decoded;
        return decoded == null ? const [] : [decoded];
      } catch (_) {
        return const [];
      }
    }

    // Handle || (fallback)
    final fallbackParts = _splitTopLevelOperator(rule, '||');
    if (fallbackParts != null) {
      for (final part in fallbackParts) {
        final val = extractJsonNodes(json, part.trim());
        if (val.isNotEmpty) return val;
      }
      return const [];
    }

    // Handle && (splicing)
    final spliceParts = _splitTopLevelOperator(rule, '&&');
    if (spliceParts != null) {
      final results = <dynamic>[];
      for (final part in spliceParts) {
        results.addAll(extractJsonNodes(json, part.trim()));
      }
      return results;
    }

    // Handle %% (cross merge)
    final mergeParts = _splitTopLevelOperator(rule, '%%');
    if (mergeParts != null) {
      final results = <dynamic>[];
      for (final part in mergeParts) {
        results.addAll(extractJsonNodes(json, part.trim()));
      }
      return results;
    }

    final cleaned = stripPostProcessors(rule);
    if (cleaned.isEmpty) return const [];
    final nodes = <dynamic>[];
    nodes.addAll(_extractNodesByJsonPath(json, cleaned));
    if (nodes.isEmpty) nodes.addAll(_extractNodesManually(json, cleaned));
    return nodes;
  }

  static String extractHtmlValue(Element node, String rule) {
    if (rule.isEmpty) return '';
    rule = _applyHtmlPutDirectives(node, rule);
    final materializedRule = _replaceGetDirectives(rule);
    if (_isHtmlLiteralWithGet(rule, materializedRule) ||
        _isHtmlLiteralRule(materializedRule)) {
      final base = _literalBeforePostProcessors(materializedRule);
      return applyPostProcessors(base, materializedRule);
    }
    rule = materializedRule;

    // Handle || (fallback)
    final fallbackParts = _splitTopLevelOperator(rule, '||');
    if (fallbackParts != null) {
      for (final part in fallbackParts) {
        final val = extractHtmlValue(node, part.trim());
        if (val.isNotEmpty) return val;
      }
      return '';
    }

    // Handle && (splicing)
    final spliceParts = _splitTopLevelOperator(rule, '&&');
    if (spliceParts != null) {
      final results = <String>[];
      for (final part in spliceParts) {
        final val = extractHtmlValue(node, part.trim());
        if (val.isNotEmpty) results.add(val);
      }
      return results.join('\n');
    }

    // Handle %% (cross merge)
    final mergeParts = _splitTopLevelOperator(rule, '%%');
    if (mergeParts != null) {
      final lists = mergeParts
          .map((part) => _extractHtmlValueList(node, part.trim()))
          .where((list) => list.isNotEmpty)
          .toList();
      return _interleaveLists(lists).join('\n');
    }

    return _extractSingleHtmlValue(node, rule);
  }

  static List<String> _extractHtmlValueList(Element node, String rule) {
    if (rule.isEmpty) return const [];
    rule = _applyHtmlPutDirectives(node, rule);
    final materializedRule = _replaceGetDirectives(rule);
    if (_isHtmlLiteralWithGet(rule, materializedRule) ||
        _isHtmlLiteralRule(materializedRule)) {
      final value = applyPostProcessors(
        _literalBeforePostProcessors(materializedRule),
        materializedRule,
      );
      return value.trim().isEmpty ? const [] : [value];
    }
    rule = materializedRule;
    final fallbackParts = _splitTopLevelOperator(rule, '||');
    if (fallbackParts != null) {
      for (final part in fallbackParts) {
        final values = _extractHtmlValueList(node, part.trim());
        if (values.isNotEmpty) return values;
      }
      return const [];
    }
    final spliceParts = _splitTopLevelOperator(rule, '&&');
    if (spliceParts != null) {
      return spliceParts
          .expand((part) => _extractHtmlValueList(node, part.trim()))
          .toList();
    }
    final mergeParts = _splitTopLevelOperator(rule, '%%');
    if (mergeParts != null) {
      final lists = mergeParts
          .map((part) => _extractHtmlValueList(node, part.trim()))
          .where((list) => list.isNotEmpty)
          .toList();
      return _interleaveLists(lists);
    }
    if (_containsHtmlTemplate(rule)) {
      final interpolated = _interpolateHtmlTemplate(node, rule);
      final value = applyPostProcessors(
        _literalBeforePostProcessors(interpolated),
        interpolated,
      );
      return value.isEmpty ? const [] : [value];
    }
    if (rule.contains('@@')) {
      final value = _extractSingleHtmlValue(node, rule);
      return value.isEmpty ? const [] : [value];
    }
    if (isXPathRule(rule)) {
      return _extractXPathValueList(node, rule)
          .map((value) => applyPostProcessors(value, rule))
          .where((value) => value.trim().isNotEmpty)
          .toList();
    }

    final parsed = _parseHtmlRule(rule);
    final targets = _queryChain(node, parsed.selectors);
    if (targets.isEmpty) return const [];
    return targets
        .map(
          (target) =>
              applyPostProcessors(_htmlValue(target, parsed.attr), rule),
        )
        .where((value) => value.trim().isNotEmpty)
        .toList();
  }

  static String _extractSingleHtmlValue(Element node, String rule) {
    rule = _applyHtmlPutDirectives(node, rule);
    final materializedRule = _replaceGetDirectives(rule);
    if (_isHtmlLiteralWithGet(rule, materializedRule) ||
        _isHtmlLiteralRule(materializedRule)) {
      return applyPostProcessors(
        _literalBeforePostProcessors(materializedRule),
        materializedRule,
      );
    }
    rule = materializedRule;
    if (rule.trimLeft().startsWith('@@')) {
      return _extractSingleHtmlValue(
        node,
        rule.trimLeft().substring(2).trimLeft(),
      );
    }
    if (_containsHtmlTemplate(rule)) {
      final interpolated = _interpolateHtmlTemplate(node, rule);
      return applyPostProcessors(
        _literalBeforePostProcessors(interpolated),
        interpolated,
      );
    }
    if (rule.contains('@@')) {
      final parts = rule.split('@@');
      final rawValue = _extractSingleHtmlValue(node, parts[0].trim());
      if (rawValue.isEmpty) return '';
      final doc = Document.html(rawValue);
      final root = doc.body ?? doc.documentElement;
      if (root == null) return '';
      final remainingRule = parts.skip(1).join('@@');
      return _extractSingleHtmlValue(root, remainingRule);
    }

    if (isXPathRule(rule)) {
      try {
        final values = _extractXPathValueList(node, rule);
        return applyPostProcessors(values.join('\n'), rule);
      } catch (_) {
        return '';
      }
    }

    final parsed = _parseHtmlRule(rule);
    final targets = _queryChain(node, parsed.selectors);
    if (targets.isEmpty) return '';
    final values = targets
        .map((target) => _htmlValue(target, parsed.attr))
        .where((value) => value.trim().isNotEmpty)
        .toList();
    final value = values.join('\n');
    return applyPostProcessors(value, rule);
  }

  static List<Element> queryAll(Document document, String rule) {
    if (rule.isEmpty) return [];
    final rootForSideEffects = document.documentElement ?? document.body;
    if (rootForSideEffects != null) {
      rule = _applyHtmlPutDirectives(rootForSideEffects, rule);
    }
    rule = _replaceGetDirectives(rule);
    if (rule.trimLeft().startsWith('@@')) {
      return queryAll(document, rule.trimLeft().substring(2).trimLeft());
    }

    // Handle || (fallback)
    final fallbackParts = _splitTopLevelOperator(rule, '||');
    if (fallbackParts != null) {
      for (final part in fallbackParts) {
        final val = queryAll(document, part.trim());
        if (val.isNotEmpty) return val;
      }
      return [];
    }

    // Handle && (splicing)
    final spliceParts = _splitTopLevelOperator(rule, '&&');
    if (spliceParts != null) {
      final results = <Element>[];
      for (final part in spliceParts) {
        results.addAll(queryAll(document, part.trim()));
      }
      return results;
    }

    // Handle %% (cross merge)
    final mergeParts = _splitTopLevelOperator(rule, '%%');
    if (mergeParts != null) {
      final lists = mergeParts
          .map((part) => queryAll(document, part.trim()))
          .where((list) => list.isNotEmpty)
          .toList();
      return _interleaveLists(lists);
    }

    if (isXPathRule(rule)) {
      try {
        final root = document.documentElement;
        if (root == null) return [];
        final result = HtmlXPath.node(root).query(xpathRule(rule));
        return result.nodes
            .map((node) => node.node)
            .whereType<Element>()
            .toList();
      } catch (_) {
        return [];
      }
    }
    try {
      final root = document.documentElement ?? document.body;
      if (root == null) return [];
      return _queryChain(
        root,
        _parseHtmlRule(rule, attrAllowed: false).selectors,
      );
    } catch (_) {
      return [];
    }
  }

  static Element? queryOne(dynamic node, String rule) {
    if (rule.isEmpty) return null;
    final sideEffectRoot = node is Document
        ? node.documentElement ?? node.body
        : node as Element?;
    if (sideEffectRoot != null) {
      rule = _applyHtmlPutDirectives(sideEffectRoot, rule);
    }
    rule = _replaceGetDirectives(rule);
    if (rule.trimLeft().startsWith('@@')) {
      return queryOne(node, rule.trimLeft().substring(2).trimLeft());
    }

    // Handle || (fallback)
    final fallbackParts = _splitTopLevelOperator(rule, '||');
    if (fallbackParts != null) {
      for (final part in fallbackParts) {
        final val = queryOne(node, part.trim());
        if (val != null) return val;
      }
      return null;
    }

    if (isXPathRule(rule)) {
      try {
        final result = HtmlXPath.node(node as Node).query(xpathRule(rule));
        return result.nodes
            .map((node) => node.node)
            .whereType<Element>()
            .firstOrNull;
      } catch (_) {
        return null;
      }
    }
    try {
      final root = node is Document
          ? node.documentElement ?? node.body
          : node as Element?;
      if (root == null) return null;
      final targets = _queryChain(
        root,
        _parseHtmlRule(rule, attrAllowed: false).selectors,
      );
      return targets.firstOrNull;
    } catch (_) {
      return null;
    }
  }

  static bool isJsonRule(String rule) {
    final cleaned = stripPostProcessors(rule);
    if (_hasJsonRulePrefix(cleaned)) {
      return true;
    }
    if (cleaned.startsWith(r'$.') || cleaned.startsWith(r'$[')) return true;
    if (cleaned.startsWith('@') || cleaned.startsWith('<')) return false;
    if (cleaned.startsWith('.') || cleaned.startsWith('#')) return false;
    return RegExp(r'^[A-Za-z_][A-Za-z0-9_]*(\.|\[)').hasMatch(cleaned) ||
        RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(cleaned);
  }

  static String jsonPathRule(String rule) {
    final cleaned = _cleanJsonRule(rule);
    if (cleaned.startsWith(r'$')) return cleaned;
    return '\$.$cleaned';
  }

  static String stripPostProcessors(String rule) {
    var text = rule.trim();
    final closeJs = text.toLowerCase().lastIndexOf('</js>');
    if (closeJs >= 0) {
      final suffix = text.substring(closeJs + '</js>'.length).trim();
      if (suffix.isNotEmpty) text = suffix;
    }
    final matchMarker = text.toLowerCase().indexOf('@match->');
    if (matchMarker >= 0) text = text.substring(0, matchMarker);
    return text
        .split('\n')
        .first
        .split(RegExp(r'@js:|@put:|@get:', caseSensitive: false))
        .first
        .split('##')
        .first
        .trim();
  }

  static String _applyJsonPutDirectives(dynamic json, String rule) {
    final parsed = _splitPutDirectives(rule);
    if (parsed.puts.isEmpty) return rule;
    parsed.puts.forEach((key, valueRule) {
      if (key.isEmpty) return;
      final value = _extractJsonValueInternal(
        json,
        _replaceGetDirectives(valueRule),
        applyPut: false,
      );
      LegadoJsEngine().putStoredValue(key, value);
    });
    return parsed.rule.trim();
  }

  static String _applyHtmlPutDirectives(Element node, String rule) {
    final parsed = _splitPutDirectives(rule);
    if (parsed.puts.isEmpty) return rule;
    parsed.puts.forEach((key, valueRule) {
      if (key.isEmpty) return;
      final value = _extractSingleHtmlValueNoDirectives(
        node,
        _replaceGetDirectives(valueRule),
      );
      LegadoJsEngine().putStoredValue(key, value);
    });
    return parsed.rule.trim();
  }

  static ({String rule, Map<String, String> puts}) _splitPutDirectives(
    String rule,
  ) {
    final puts = <String, String>{};
    final output = StringBuffer();
    var index = 0;
    while (index < rule.length) {
      final marker = rule.toLowerCase().indexOf('@put:', index);
      if (marker < 0) {
        output.write(rule.substring(index));
        break;
      }
      output.write(rule.substring(index, marker));
      var open = marker + 5;
      while (open < rule.length && rule.codeUnitAt(open) <= 0x20) {
        open++;
      }
      if (open >= rule.length || rule[open] != '{') {
        output.write(rule.substring(marker, marker + 5));
        index = marker + 5;
        continue;
      }
      final close = _findBalanced(rule, open, 0x7b, 0x7d);
      if (close < 0) {
        output.write(rule.substring(marker));
        index = rule.length;
        break;
      }
      final body = rule.substring(open + 1, close);
      puts.addAll(_parsePutBody(body));
      index = close + 1;
    }
    return (rule: output.toString(), puts: puts);
  }

  static Map<String, String> _parsePutBody(String body) {
    final result = <String, String>{};
    for (final entry in _splitTopLevel(body, 0x2c)) {
      final colon = _findTopLevel(entry, 0x3a);
      if (colon <= 0) continue;
      final key = _unquoteLoose(entry.substring(0, colon).trim());
      final value = _unquoteLoose(entry.substring(colon + 1).trim());
      if (key.isNotEmpty) result[key] = value;
    }
    return result;
  }

  static String _replaceGetDirectives(String rule) {
    return rule.replaceAllMapped(
      RegExp(r'@get:\{([^}]+)\}', caseSensitive: false),
      (match) => LegadoJsEngine().getStoredString(match.group(1)?.trim() ?? ''),
    );
  }

  static String _directiveTail(String rule, String marker) {
    final index = rule.toLowerCase().indexOf(marker.toLowerCase());
    if (index < 0) return '';
    return rule.substring(index + marker.length);
  }

  static String? _jsTagBody(String rule) {
    final lower = rule.toLowerCase();
    final start = lower.indexOf('<js>');
    if (start < 0) return null;
    final bodyStart = start + '<js>'.length;
    final end = lower.indexOf('</js>', bodyStart);
    if (end < 0) return rule.substring(bodyStart);
    return rule.substring(bodyStart, end);
  }

  static bool _isHtmlLiteralWithGet(String original, String materialized) {
    if (!original.toLowerCase().contains('@get:')) return false;
    final base = original
        .split('##')
        .first
        .split(RegExp(r'@js:', caseSensitive: false))
        .first
        .trim();
    final withoutGets = base
        .replaceAll(RegExp(r'@get:\{[^}]+\}', caseSensitive: false), '')
        .trim();
    if (withoutGets.isEmpty) return true;
    final lower = withoutGets.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('/') ||
        lower.contains('://') ||
        withoutGets.contains('<') ||
        withoutGets.contains('>') ||
        withoutGets.contains('?') ||
        withoutGets.contains('&')) {
      return true;
    }
    if (withoutGets.contains('@') ||
        withoutGets.startsWith('.') ||
        withoutGets.startsWith('#') ||
        lower.startsWith('class.') ||
        lower.startsWith('id.') ||
        lower.startsWith('tag.') ||
        lower.startsWith('@css:') ||
        lower.startsWith('@xpath:') ||
        lower.startsWith('xpath:') ||
        _looksLikeHtmlTagToken(withoutGets)) {
      return false;
    }
    return materialized.trim().isNotEmpty;
  }

  static bool _isHtmlLiteralRule(String rule) {
    final text = _literalBeforePostProcessors(rule).trim();
    if (text.isEmpty || text.contains('{{') || text.contains('}}')) {
      return false;
    }
    final lower = text.toLowerCase();
    if (lower.startsWith('@xpath:') ||
        lower.startsWith('xpath:') ||
        (text.startsWith('//') &&
            !RegExp(r'^//[A-Za-z0-9.-]+(?:[:/]|$)').hasMatch(text)) ||
        text.startsWith('./') ||
        text.contains('@') ||
        text.startsWith('.') ||
        text.startsWith('#') ||
        lower.startsWith('class.') ||
        lower.startsWith('id.') ||
        lower.startsWith('tag.') ||
        lower.startsWith('text.') ||
        lower.startsWith('@css:') ||
        _looksLikeHtmlTagToken(text)) {
      return false;
    }
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        RegExp(r'^//[A-Za-z0-9.-]+(?:[:/]|$)').hasMatch(text) ||
        text.startsWith('/') ||
        lower.contains('://') ||
        text.contains('?') ||
        text.contains('&') ||
        text.contains('<') ||
        text.contains('>')) {
      return true;
    }
    return false;
  }

  static String _literalBeforePostProcessors(String rule) {
    var text = rule.trim();
    final jsIndex = text.toLowerCase().indexOf('@js:');
    if (jsIndex >= 0) text = text.substring(0, jsIndex);
    final hashIndex = text.indexOf('##');
    if (hashIndex >= 0) text = text.substring(0, hashIndex);
    return text.trim();
  }

  static String _extractSingleHtmlValueNoDirectives(Element node, String rule) {
    var text = rule.trim();
    while (text.startsWith('@@')) {
      text = text.substring(2).trimLeft();
    }
    if (text.toLowerCase().startsWith('@css:')) {
      text = text.substring(5).trimLeft();
    }
    if (text.isEmpty) return '';
    if (_containsHtmlTemplate(text)) {
      final interpolated = _interpolateHtmlTemplate(node, text);
      return applyPostProcessors(
        _literalBeforePostProcessors(interpolated),
        interpolated,
      );
    }
    if (_isHtmlLiteralRule(text)) {
      return applyPostProcessors(_literalBeforePostProcessors(text), text);
    }
    if (text.contains('@@')) {
      final parts = text.split('@@');
      final rawValue = _extractSingleHtmlValueNoDirectives(
        node,
        parts[0].trim(),
      );
      if (rawValue.isEmpty) return '';
      final doc = Document.html(rawValue);
      final root = doc.body ?? doc.documentElement;
      if (root == null) return '';
      return _extractSingleHtmlValueNoDirectives(
        root,
        parts.skip(1).join('@@'),
      );
    }
    if (isXPathRule(text)) {
      final values = _extractXPathValueList(node, text);
      return applyPostProcessors(values.join('\n'), text);
    }
    final parsed = _parseHtmlRule(text);
    final targets = _queryChain(node, parsed.selectors);
    if (targets.isEmpty) return '';
    final values = targets
        .map((target) => _htmlValue(target, parsed.attr))
        .where((value) => value.trim().isNotEmpty)
        .toList();
    return applyPostProcessors(values.join('\n'), text);
  }

  static int _findBalanced(String text, int start, int open, int close) {
    var depth = 0;
    var quote = 0;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (quote != 0) {
        if (escaped) {
          escaped = false;
        } else if (unit == 0x5c) {
          escaped = true;
        } else if (unit == quote) {
          quote = 0;
        }
        continue;
      }
      if (unit == 0x22 || unit == 0x27 || unit == 0x60) {
        quote = unit;
        continue;
      }
      if (unit == open) {
        depth++;
      } else if (unit == close) {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  static List<String> _splitTopLevel(String text, int separator) {
    final parts = <String>[];
    var start = 0;
    var parenDepth = 0;
    var bracketDepth = 0;
    var braceDepth = 0;
    var quote = 0;
    var escaped = false;
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (quote != 0) {
        if (escaped) {
          escaped = false;
        } else if (unit == 0x5c) {
          escaped = true;
        } else if (unit == quote) {
          quote = 0;
        }
        continue;
      }
      if (unit == 0x22 || unit == 0x27 || unit == 0x60) {
        quote = unit;
        continue;
      }
      if (unit == 0x28) parenDepth++;
      if (unit == 0x29 && parenDepth > 0) parenDepth--;
      if (unit == 0x5b) bracketDepth++;
      if (unit == 0x5d && bracketDepth > 0) bracketDepth--;
      if (unit == 0x7b) braceDepth++;
      if (unit == 0x7d && braceDepth > 0) braceDepth--;
      if (unit == separator &&
          parenDepth == 0 &&
          bracketDepth == 0 &&
          braceDepth == 0) {
        parts.add(text.substring(start, i).trim());
        start = i + 1;
      }
    }
    final tail = text.substring(start).trim();
    if (tail.isNotEmpty) parts.add(tail);
    return parts;
  }

  static int _findTopLevel(String text, int target) {
    var parenDepth = 0;
    var bracketDepth = 0;
    var braceDepth = 0;
    var quote = 0;
    var escaped = false;
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (quote != 0) {
        if (escaped) {
          escaped = false;
        } else if (unit == 0x5c) {
          escaped = true;
        } else if (unit == quote) {
          quote = 0;
        }
        continue;
      }
      if (unit == 0x22 || unit == 0x27 || unit == 0x60) {
        quote = unit;
        continue;
      }
      if (unit == 0x28) parenDepth++;
      if (unit == 0x29 && parenDepth > 0) parenDepth--;
      if (unit == 0x5b) bracketDepth++;
      if (unit == 0x5d && bracketDepth > 0) bracketDepth--;
      if (unit == 0x7b) braceDepth++;
      if (unit == 0x7d && braceDepth > 0) braceDepth--;
      if (unit == target &&
          parenDepth == 0 &&
          bracketDepth == 0 &&
          braceDepth == 0) {
        return i;
      }
    }
    return -1;
  }

  static String _unquoteLoose(String value) {
    final text = value.trim();
    if (text.length >= 2) {
      final first = text.codeUnitAt(0);
      final last = text.codeUnitAt(text.length - 1);
      if ((first == 0x22 || first == 0x27 || first == 0x60) && first == last) {
        return text
            .substring(1, text.length - 1)
            .replaceAll(r'\"', '"')
            .replaceAll(r"\'", "'")
            .replaceAll(r'\`', '`')
            .replaceAll(r'\n', '\n')
            .replaceAll(r'\r', '\r')
            .replaceAll(r'\t', '\t')
            .replaceAll(r'\\', '\\');
      }
    }
    return text;
  }

  static String cleanRuleOutput(String value) {
    return value.replaceAll(RegExp(r'<[^>]+>'), '').trim();
  }

  /// Compiles a regex that may carry Java/Jsoup inline flags (?i)/(?s)/(?m).
  /// Dart RegExp rejects inline flags, so translate to constructor options
  /// and strip them. Without this such patterns throw and callers silently
  /// fall back to literal replacement, breaking ## cleaning and [attr~=re].
  static RegExp _compileFlexibleRegExp(String pattern) {
    var caseSensitive = true;
    var dotAll = false;
    var multiLine = false;
    for (final m in RegExp(r'\(\?([ismxuU]+)\)').allMatches(pattern)) {
      final flags = m.group(1) ?? '';
      if (flags.contains('i')) caseSensitive = false;
      if (flags.contains('s')) dotAll = true;
      if (flags.contains('m')) multiLine = true;
    }
    final stripped = pattern.replaceAll(RegExp(r'\(\?[ismxuU]+\)'), '');
    return RegExp(
      stripped,
      caseSensitive: caseSensitive,
      multiLine: multiLine,
      dotAll: dotAll,
    );
  }

  static String applyPostProcessors(
    String value,
    String rule, {
    dynamic originalJson,
  }) {
    var output = value;
    rule = _replaceGetDirectives(rule);
    final lines = rule
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return output.trim();

    if (lines.length == 1 || _hasMultilineInlineJsPostProcessor(rule)) {
      return _applySingleLinePostProcessors(
        output,
        rule,
        originalJson: originalJson,
      );
    }

    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty) continue;
      final lowerLine = line.toLowerCase();

      if (lowerLine.contains('@get:')) {
        final key = _directiveTail(
          line,
          '@get:',
        ).split(RegExp(r'[@#]')).first.trim();
        try {
          final cached = LegadoJsEngine().evaluate('java.get("$key")');
          if (cached.trim().isNotEmpty) output = cached;
        } catch (_) {}
      }

      if (lowerLine.startsWith('<js>') ||
          lowerLine.contains('</js>') ||
          lowerLine.startsWith('@js:')) {
        try {
          final jsPart = lowerLine.startsWith('@js:')
              ? line
              : '<js>${_jsTagBody(line) ?? ''}</js>';
          final evaluated = LegadoJsEngine().evaluate(
            jsPart,
            variables: {'result': output},
          );
          if (evaluated.trim().isNotEmpty) output = evaluated;
        } catch (_) {}
      } else if (lowerLine.contains('@put:')) {
        final key = _directiveTail(
          line,
          '@put:',
        ).split(RegExp(r'[@#]')).first.trim();
        try {
          LegadoJsEngine().evaluate(
            'java.put("$key", result)',
            variables: {'result': output},
          );
        } catch (_) {}
      } else if (line.toLowerCase().contains('@match->')) {
        output = _applyMatchPostProcessor(output, line);
      } else if (line.startsWith('##')) {
        final bool onlyFirst = line.endsWith('###');
        final String processingLine = onlyFirst
            ? line.substring(0, line.length - 1)
            : line;
        final parts = processingLine.split('##');
        final processors = parts.skip(1).toList();
        for (var idx = 0; idx < processors.length; idx += 2) {
          final pattern = processors[idx];
          if (pattern.isEmpty) continue;
          final replacement = idx + 1 < processors.length
              ? processors[idx + 1]
              : '';
          output = _applyRegexPostProcessor(
            output,
            pattern,
            replacement,
            onlyFirst: onlyFirst,
          );
        }
      } else {
        if (line.contains('{result}') ||
            line.contains(
              '{'
              '{result}'
              '}',
            )) {
          output = line
              .replaceAll('{result}', output)
              .replaceAll(
                '{'
                '{result}'
                '}',
                output,
              );
        } else if (line.contains('{}') || line.contains('{{}}')) {
          output = line.replaceAll('{}', output).replaceAll('{{}}', output);
        } else if (line.contains('{') && originalJson != null) {
          final mappedLine = line.replaceAll('result', output);
          output = _interpolateJsonTemplate(
            originalJson is Map ? originalJson : {},
            mappedLine,
          );
        } else if (line.startsWith('http') ||
            line.startsWith('/') ||
            line.contains('/') ||
            line.contains('=')) {
          if (line.endsWith('=')) {
            output = '$line$output';
          } else if (line.contains('?')) {
            if (line.endsWith('?') || line.endsWith('&')) {
              output = '$line$output';
            } else {
              output = '$line&$output';
            }
          } else {
            output = '$line$output';
          }
        } else {
          output = '$line$output';
        }
      }

      output = _applyJsPostProcessors(output, line);
    }

    return output.trim();
  }

  static bool _hasMultilineInlineJsPostProcessor(String rule) {
    final marker = rule.toLowerCase().indexOf('@js:');
    if (marker < 0) return false;
    final tail = rule.substring(marker + 4);
    final jsBody = tail.split('##').first;
    return jsBody.contains('\n') || jsBody.contains('\r');
  }

  static String _applySingleLinePostProcessors(
    String value,
    String rule, {
    dynamic originalJson,
  }) {
    var output = value;
    final lowerRule = rule.toLowerCase();
    if (lowerRule.contains('@get:')) {
      final key = _directiveTail(
        rule,
        '@get:',
      ).split(RegExp(r'[@#]')).first.trim();
      try {
        final cached = LegadoJsEngine().evaluate('java.get("$key")');
        if (cached.trim().isNotEmpty) output = cached;
      } catch (_) {}
    }

    if (lowerRule.contains('@js:') || lowerRule.contains('<js>')) {
      try {
        final atJs = lowerRule.indexOf('@js:');
        final jsPart = atJs >= 0
            ? '@js:${rule.substring(atJs + 4).split('##').first}'
            : '<js>${_jsTagBody(rule) ?? ''}</js>';
        final evaluated = LegadoJsEngine().evaluate(
          jsPart,
          variables: {'result': output},
        );
        if (evaluated.trim().isNotEmpty) output = evaluated;
      } catch (_) {}
    }

    if (lowerRule.contains('@put:')) {
      final key = _directiveTail(
        rule,
        '@put:',
      ).split(RegExp(r'[@#]')).first.trim();
      try {
        LegadoJsEngine().evaluate(
          'java.put("$key", result)',
          variables: {'result': output},
        );
      } catch (_) {}
    }

    if (rule.toLowerCase().contains('@match->')) {
      output = _applyMatchPostProcessor(output, rule);
    }

    if (rule.contains('##')) {
      final bool onlyFirst = rule.endsWith('###');
      final String processingRule = onlyFirst
          ? rule.substring(0, rule.length - 1)
          : rule;
      final parts = processingRule.split('##');
      final processors = parts.skip(1).toList();
      for (var index = 0; index < processors.length; index += 2) {
        final pattern = processors[index];
        if (pattern.isEmpty) continue;
        final replacement = index + 1 < processors.length
            ? processors[index + 1]
            : '';
        output = _applyRegexPostProcessor(
          output,
          pattern,
          replacement,
          onlyFirst: onlyFirst,
        );
      }
    }
    output = _applyJsPostProcessors(output, rule);
    return output.trim();
  }

  static String _applyMatchPostProcessor(String value, String rule) {
    final lower = rule.toLowerCase();
    final marker = lower.indexOf('@match->');
    if (marker < 0) return value;
    final tail = rule.substring(marker + '@match->'.length).trim();
    if (tail.isEmpty) return value;
    final pattern = tail
        .split(RegExp(r'@js:|<js>|##|@put:|@get:', caseSensitive: false))
        .first
        .trim();
    if (pattern.isEmpty) return value;
    try {
      final match = _compileFlexibleRegExp(pattern).firstMatch(value);
      if (match == null) return '';
      if (match.groupCount > 0) return match.group(1)?.trim() ?? '';
      return match.group(0)?.trim() ?? '';
    } catch (_) {
      return value;
    }
  }

  static String _applyRegexPostProcessor(
    String value,
    String pattern,
    String replacement, {
    required bool onlyFirst,
  }) {
    try {
      final regex = _compileFlexibleRegExp(pattern);
      if (onlyFirst) {
        final match = regex.firstMatch(value);
        if (match == null) return '';
        return _expandRegexReplacement(match, replacement);
      }
      return value.replaceAllMapped(
        regex,
        (match) => _expandRegexReplacement(match, replacement),
      );
    } catch (_) {
      if (onlyFirst) return replacement;
      return value.replaceAll(pattern, replacement);
    }
  }

  static String _expandRegexReplacement(Match match, String replacement) {
    return replacement.replaceAllMapped(
      RegExp(r'\\([\\$])|\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$(\d+)'),
      (token) {
        final escaped = token.group(1);
        if (escaped != null) return escaped;
        final name = token.group(2);
        if (name != null) {
          try {
            return (match as RegExpMatch).namedGroup(name) ?? '';
          } catch (_) {
            return '';
          }
        }
        final index = int.tryParse(token.group(3) ?? '');
        if (index == null || index < 0 || index > match.groupCount) {
          return '';
        }
        return match.group(index) ?? '';
      },
    );
  }

  static bool isJsOnlyRule(String rule) {
    final trimmed = rule.trim().toLowerCase();
    return trimmed.startsWith('@js:') || trimmed.startsWith('<js>');
  }

  static bool containsJsRule(String? rule) {
    if (rule == null || rule.isEmpty) return false;
    final value = rule.toLowerCase();
    return value.contains('@js:') ||
        value.contains('<js>') ||
        value.contains('</js>') ||
        value.contains('java.ajax') ||
        value.contains('java.connect') ||
        value.contains('java.get') ||
        value.contains('java.post') ||
        value.contains('esotools.') ||
        value.contains('httpbyte(') ||
        value.contains('http.get(') ||
        value.contains('http.post(');
  }

  static bool looksLikeJsonData(dynamic data, String? rule) {
    if (rule == null) return true;
    if (data is Map || data is List) return true;
    final text = data.toString().trimLeft();
    return text.startsWith('{') || text.startsWith('[');
  }

  static String cssRule(String rule) {
    return _normalizeCssSelector(
      sanitizeCssSelector(
        rule
            .replaceFirst(RegExp(r'^@css:', caseSensitive: false), '')
            .replaceFirst(RegExp(r'^@get:', caseSensitive: false), '')
            .replaceAll(RegExp(r'@[a-zA-Z0-9_\-:]+$'), '')
            .trim(),
      ),
    );
  }

  static bool isXPathRule(String rule) {
    final value = rule.trim();
    final lowerValue = value.toLowerCase();
    return lowerValue.startsWith('@xpath:') ||
        lowerValue.startsWith('xpath:') ||
        value.startsWith('//') ||
        value.startsWith('./') ||
        value.startsWith('/');
  }

  static String xpathRule(String rule) {
    return rule
        .replaceFirst(RegExp(r'^@xpath:', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^xpath:', caseSensitive: false), '')
        .trim();
  }

  static List<String> _extractXPathValueList(Element node, String rule) {
    try {
      final cleaned = stripPostProcessors(rule);
      final result = HtmlXPath.node(node).query(xpathRule(cleaned));
      final attrValues = result.attrs
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      if (attrValues.isNotEmpty) return attrValues;
      return result.nodes
          .map((node) => node.text?.trim() ?? '')
          .where((value) => value.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static String _extractSingleJsonValue(dynamic json, String rule) {
    try {
      final nodes = _extractNodesByJsonPath(json, rule);
      if (nodes.isNotEmpty) return nodes.first?.toString() ?? '';
      final manual = _extractNodesManually(json, rule);
      if (manual.isNotEmpty) return manual.first?.toString() ?? '';
      final alias = _extractJsonAliasValue(json, rule);
      if (alias.isNotEmpty) return alias;
    } catch (_) {
      final manual = _extractNodesManually(json, rule);
      if (manual.isNotEmpty) return manual.first?.toString() ?? '';
      final alias = _extractJsonAliasValue(json, rule);
      if (alias.isNotEmpty) return alias;
    }
    return '';
  }

  static String _extractJsonAliasValue(dynamic json, String rule) {
    if (json is! Map) return '';
    final cleaned = _cleanJsonRule(
      rule,
    ).replaceAll(RegExp(r'^\$\.?'), '').replaceAll(RegExp(r'^\.+'), '').trim();
    if (cleaned.isEmpty || cleaned.contains('.') || cleaned.contains('[')) {
      return '';
    }
    final aliases = _jsonKeyAliases(cleaned);
    for (final alias in aliases) {
      final value = json[alias] ?? json[alias.toLowerCase()];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString();
      }
    }
    return '';
  }

  static List<String> _jsonKeyAliases(String key) {
    const groups = [
      [
        'novelId',
        'novel_id',
        'bookId',
        'book_id',
        'bookID',
        'articleid',
        'articleId',
        'nid',
        'id',
        'Id',
      ],
      ['chapterId', 'chapter_id', 'cid', 'id', 'Id', 'chapterID'],
      [
        'chapterName',
        'chapter_name',
        'chapterTitle',
        'chapter_title',
        'name',
        'title',
      ],
      ['bookName', 'book_name', 'novelName', 'novel_name', 'name', 'title'],
    ];

    for (final group in groups) {
      if (group.any((item) => item.toLowerCase() == key.toLowerCase())) {
        return group;
      }
    }
    return const [];
  }

  static String _interpolateJsonTemplate(
    Map<dynamic, dynamic> json,
    String rule,
  ) {
    final jsonText = jsonEncode(json);
    var output = rule.replaceAllMapped(RegExp(r'\{\{([^}]+)\}\}'), (match) {
      final expression = match.group(1)?.trim() ?? '';
      if (expression.isEmpty) return '';
      if (_looksLikeJsonTemplateExpression(expression)) {
        final evaluated = _evaluateJsonTemplateExpression(
          json,
          jsonText,
          expression,
        );
        if (evaluated != null) return evaluated;
      }
      return _extractSingleJsonValue(json, expression);
    });
    output = output.replaceAllMapped(
      RegExp(r'\{(\$[^{}]+|[A-Za-z_][A-Za-z0-9_\.\[\]\*]*)\}'),
      (match) {
        final key = match.group(1)?.trim() ?? '';
        if (key.isEmpty) return '';
        return _extractSingleJsonValue(json, key);
      },
    );
    return output;
  }

  static bool _looksLikeJsonTemplateExpression(String expression) {
    final value = expression.trim();
    if (value.startsWith(r'$.') || value.startsWith(r'$..')) {
      return value.contains('java.') ||
          value.contains('Math.') ||
          value.contains('parseInt') ||
          value.contains('String(') ||
          value.contains('&&') ||
          value.contains('||') ||
          value.contains('?');
    }
    return value.contains('java.') ||
        value.contains('Math.') ||
        value.contains('new Date') ||
        value.contains('parseInt') ||
        value.contains('String(') ||
        value.contains('+') ||
        value.contains('*') ||
        value.contains('/') ||
        value.contains('&&') ||
        value.contains('||') ||
        value.contains('?') ||
        value.contains(',');
  }

  static String? _evaluateJsonTemplateExpression(
    Map<dynamic, dynamic> json,
    String jsonText,
    String expression,
  ) {
    try {
      final evaluated = LegadoJsEngine().evaluate(
        '@js:($expression)',
        variables: {'result': jsonText},
      );
      if (evaluated.trim().isNotEmpty) return evaluated.trim();
    } catch (_) {
      // Fall through to deterministic fallbacks used when QuickJS is absent.
    }
    return _evaluateJsonTemplateExpressionFallback(json, expression);
  }

  static String? _evaluateJsonTemplateExpressionFallback(
    Map<dynamic, dynamic> json,
    String expression,
  ) {
    var value = expression.trim();
    final stringWrapper = RegExp(
      r'''^String\(([\s\S]+)\)$''',
      dotAll: true,
    ).firstMatch(value);
    if (stringWrapper != null) {
      value = stringWrapper.group(1)?.trim() ?? value;
    }

    final directGet = RegExp(
      r'''^java\.getString\(\s*(['"])(.*?)\1\s*\)$''',
      dotAll: true,
    ).firstMatch(value);
    if (directGet != null) {
      return _jsonTemplateGetString(json, directGet.group(2) ?? '');
    }

    final parseInt = RegExp(
      r'''^parseInt\(([\s\S]+)\)$''',
      dotAll: true,
    ).firstMatch(value);
    if (parseInt != null) {
      final numeric = _evaluateJsonTemplateNumber(
        json,
        parseInt.group(1) ?? '',
      );
      if (numeric != null) return numeric.truncate().toString();
    }

    final timeFormat = RegExp(
      r'''^java\.timeFormat\(([\s\S]+)\)$''',
      dotAll: true,
    ).firstMatch(value);
    if (timeFormat != null) {
      final millis = _evaluateJsonTemplateNumber(
        json,
        timeFormat.group(1) ?? '',
      );
      if (millis != null) return _formatJavaTime(millis.round());
    }

    return null;
  }

  static double? _evaluateJsonTemplateNumber(
    Map<dynamic, dynamic> json,
    String expression,
  ) {
    var value = expression.replaceAllMapped(
      RegExp(r'''java\.getString\(\s*(['"])(.*?)\1\s*\)'''),
      (match) => _jsonTemplateGetString(json, match.group(2) ?? ''),
    );
    value = value.replaceAll(RegExp(r'\s+'), '');
    return _evalSimpleNumber(value);
  }

  static double? _evalSimpleNumber(String expression) {
    if (expression.isEmpty) return null;
    var depth = 0;
    for (var i = expression.length - 1; i >= 0; i--) {
      final char = expression[i];
      if (char == ')') depth++;
      if (char == '(') depth--;
      if (depth == 0 && (char == '*' || char == '/')) {
        final left = _evalSimpleNumber(expression.substring(0, i));
        final right = _evalSimpleNumber(expression.substring(i + 1));
        if (left == null || right == null) return null;
        return char == '*' ? left * right : left / right;
      }
    }
    final wrapped = RegExp(r'^\(([\s\S]+)\)$').firstMatch(expression);
    if (wrapped != null) {
      return _evalSimpleNumber(wrapped.group(1) ?? '');
    }
    return double.tryParse(expression);
  }

  static String _jsonTemplateGetString(Map<dynamic, dynamic> json, String key) {
    final trimmed = key.trim();
    if (trimmed.startsWith(r'$') || trimmed.contains('.')) {
      return _extractSingleJsonValue(json, trimmed);
    }
    return LegadoJsEngine().getStoredString(trimmed);
  }

  static String _formatJavaTime(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${dt.year}/${two(dt.month)}/${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  static bool _containsJsonTemplate(String rule) {
    return rule.contains('{{') ||
        RegExp(r'\{(\$[^{}]+|[A-Za-z_][A-Za-z0-9_\.\[\]\*]*)\}').hasMatch(rule);
  }

  static bool _containsHtmlTemplate(String rule) {
    return rule.contains('{{') && rule.contains('}}');
  }

  static String _interpolateHtmlTemplate(Element node, String rule) {
    return rule.replaceAllMapped(RegExp(r'\{\{([\s\S]*?)\}\}'), (match) {
      final expression = match.group(1)?.trim() ?? '';
      if (expression.isEmpty) return '';
      return extractHtmlValue(node, expression);
    });
  }

  static List<dynamic> _extractNodesByJsonPath(dynamic json, String rule) {
    try {
      final cleaned = _cleanJsonRule(rule);
      if (cleaned.contains('[?(@.')) {
        final manual = _extractNodesManually(json, cleaned);
        if (manual.isNotEmpty) return manual;
      }
      final values = <dynamic>[];
      for (final match in JsonPath(jsonPathRule(rule)).read(json)) {
        final value = match.value;
        if (value is List) {
          values.addAll(value);
        } else if (value != null) {
          values.add(value);
        }
      }
      return values;
    } catch (_) {
      return const [];
    }
  }

  static List<dynamic> _extractNodesManually(dynamic json, String rule) {
    final cleaned = _cleanJsonRule(
      rule,
    ).replaceAll(RegExp(r'^\$\.?'), '').replaceAll('.*', '').trim();
    if (cleaned.isEmpty) return [json];
    if (cleaned.contains('..')) {
      return _extractNodesRecursively(json, cleaned);
    }

    return _readJsonPathSegments([json], cleaned);
  }

  static List<dynamic> _extractNodesRecursively(dynamic json, String path) {
    final deep = path.indexOf('..');
    final prefix = path.substring(0, deep).replaceAll(RegExp(r'\.$'), '');
    final suffix = path.substring(deep + 2).replaceAll(RegExp(r'^\.+'), '');
    final roots = prefix.isEmpty
        ? <dynamic>[json]
        : _readJsonPathSegments([json], prefix);
    if (suffix.isEmpty) return roots;

    final dot = suffix.indexOf('.');
    final first = dot < 0 ? suffix : suffix.substring(0, dot);
    final rest = dot < 0 ? '' : suffix.substring(dot + 1);
    final result = <dynamic>[];

    void visit(dynamic node) {
      final hits = _readJsonPathSegments([node], first);
      for (final hit in hits) {
        if (rest.isEmpty) {
          result.add(hit);
        } else {
          result.addAll(_readJsonPathSegments([hit], rest));
        }
      }
      if (node is Map) {
        for (final child in node.values) {
          visit(child);
        }
      } else if (node is List) {
        for (final child in node) {
          visit(child);
        }
      }
    }

    for (final root in roots) {
      visit(root);
    }
    return result;
  }

  static List<dynamic> _readJsonPathSegments(List<dynamic> roots, String path) {
    var current = roots;
    for (final part in _splitJsonPathSegments(path)) {
      if (part.isEmpty) continue;
      final next = <dynamic>[];
      final filter = _parseJsonFilterPart(part);
      if (filter != null) {
        for (final value in current) {
          final children = _jsonChildrenForKey(value, filter.key);
          for (final child in children) {
            final candidates = child is List
                ? child
                : child is Map && filter.key.isEmpty
                ? child.values
                : [child];
            for (final candidate in candidates) {
              if (_jsonFilterMatches(
                candidate,
                filter.field,
                filter.operator,
                filter.expected,
              )) {
                next.add(candidate);
              }
            }
          }
        }
        current = next;
        if (current.isEmpty) return const [];
        continue;
      }

      final match = RegExp(r'^([^\[]+)?(?:\[(\*|\d+)\])?$').firstMatch(part);
      final key = (match?.group(1) ?? part).trim();
      final indexToken = match?.group(2);
      final index = int.tryParse(indexToken ?? '');
      final wantsAll = indexToken == '*';
      for (final value in current) {
        final children = <dynamic>[];
        if (key == '*' || key.isEmpty) {
          if (value is List) {
            children.addAll(value);
          } else if (value is Map) {
            children.addAll(value.values);
          }
        } else if (value is Map) {
          final child = value[key] ?? value[key.toString()];
          if (child != null) children.add(child);
        } else if (value is List) {
          final listIndex = int.tryParse(key);
          if (listIndex != null) {
            if (listIndex >= 0 && listIndex < value.length) {
              children.add(value[listIndex]);
            }
          } else {
            for (final element in value) {
              if (element is Map) {
                final child = element[key] ?? element[key.toString()];
                if (child != null) children.add(child);
              }
            }
          }
        }

        for (final child in children) {
          if (wantsAll) {
            if (child is List) {
              next.addAll(child);
            } else if (child is Map) {
              next.addAll(child.values);
            } else {
              next.add(child);
            }
          } else if (index != null) {
            if (child is List && index >= 0 && index < child.length) {
              next.add(child[index]);
            }
          } else if (child is List) {
            next.addAll(child);
          } else {
            next.add(child);
          }
        }
      }
      current = next;
      if (current.isEmpty) return const [];
    }
    return current;
  }

  static List<String> _splitJsonPathSegments(String path) {
    final result = <String>[];
    var start = 0;
    var bracketDepth = 0;
    var quote = 0;
    var escaped = false;
    for (var i = 0; i < path.length; i++) {
      final unit = path.codeUnitAt(i);
      if (quote != 0) {
        if (escaped) {
          escaped = false;
        } else if (unit == 0x5c) {
          escaped = true;
        } else if (unit == quote) {
          quote = 0;
        }
        continue;
      }
      if (unit == 0x22 || unit == 0x27) {
        quote = unit;
        continue;
      }
      if (unit == 0x5b) {
        bracketDepth++;
      } else if (unit == 0x5d && bracketDepth > 0) {
        bracketDepth--;
      } else if (unit == 0x2e && bracketDepth == 0) {
        result.add(path.substring(start, i));
        start = i + 1;
      }
    }
    result.add(path.substring(start));
    return result
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
  }

  static ({String key, String field, String? operator, String? expected})?
  _parseJsonFilterPart(String part) {
    final match = RegExp(
      r'''^([^\[]*)\[\?\(@\.([A-Za-z0-9_\-]+)(?:\s*(==|!=)\s*(?:"([^"]*)"|'([^']*)'|([^)]+)))?\)\]$''',
    ).firstMatch(part.trim());
    if (match == null) return null;
    return (
      key: match.group(1)?.trim() ?? '',
      field: match.group(2)?.trim() ?? '',
      operator: match.group(3),
      expected: (match.group(4) ?? match.group(5) ?? match.group(6))?.trim(),
    );
  }

  static List<dynamic> _jsonChildrenForKey(dynamic value, String key) {
    final children = <dynamic>[];
    if (key == '*' || key.isEmpty) {
      if (value is List) {
        children.addAll(value);
      } else if (value is Map) {
        children.addAll(value.values);
      }
    } else if (value is Map) {
      final child = value[key] ?? value[key.toString()];
      if (child != null) children.add(child);
    } else if (value is List) {
      final listIndex = int.tryParse(key);
      if (listIndex != null) {
        if (listIndex >= 0 && listIndex < value.length) {
          children.add(value[listIndex]);
        }
      } else {
        for (final element in value) {
          if (element is Map) {
            final child = element[key] ?? element[key.toString()];
            if (child != null) children.add(child);
          }
        }
      }
    }
    return children;
  }

  static bool _jsonFilterMatches(
    dynamic node,
    String field,
    String? operator,
    String? expected,
  ) {
    if (node is! Map) return false;
    final actual = node[field] ?? node[field.toString()];
    if (operator == null) return _jsonTruthy(actual);
    final equal = _jsonLooseEquals(actual, expected ?? '');
    return operator == '==' ? equal : !equal;
  }

  static bool _jsonTruthy(dynamic value) {
    if (value == null || value == false) return false;
    if (value is num) return value != 0;
    final text = value.toString().trim();
    return text.isNotEmpty && text != '0' && text.toLowerCase() != 'false';
  }

  static bool _jsonLooseEquals(dynamic actual, String expected) {
    final target = expected.trim();
    if (actual is num) {
      final parsed = num.tryParse(target);
      if (parsed != null) return actual == parsed;
    }
    if (actual is bool) {
      return actual.toString() == target.toLowerCase();
    }
    return (actual?.toString() ?? '') == target;
  }

  static String _cleanJsonRule(String rule) {
    return _stripJsonRulePrefix(stripPostProcessors(rule)).trim();
  }

  static bool _hasJsonRulePrefix(String rule) {
    return RegExp(r'^@?json:', caseSensitive: false).hasMatch(rule.trimLeft());
  }

  static String _stripJsonRulePrefix(String rule) {
    final leading = rule.length - rule.trimLeft().length;
    final prefix = rule.substring(0, leading);
    final body = rule.substring(leading);
    return prefix +
        body.replaceFirst(RegExp(r'^@?json:', caseSensitive: false), '');
  }

  static String sanitizeCssSelector(String selector) {
    var output = selector.trim();
    if (output.isEmpty) return output;

    // Convert :eq(n) to .n
    output = _replaceCssPseudoOutsideFunctions(
      output,
      RegExp(r':eq\((-?\d+)\)'),
      (match) {
        final val = int.tryParse(match.group(1) ?? '') ?? 0;
        return '.$val';
      },
    );
    output = _replaceCssPseudoOutsideFunctions(
      output,
      RegExp(r':lt\((-?\d+)\)'),
      (match) {
        final val = int.tryParse(match.group(1) ?? '') ?? 0;
        if (val <= 0) return '[-999999:-999998]';
        return '[0:${val - 1}]';
      },
    );
    output = _replaceCssPseudoOutsideFunctions(
      output,
      RegExp(r':gt\((-?\d+)\)'),
      (match) {
        final val = (int.tryParse(match.group(1) ?? '') ?? 0) + 1;
        return '[$val:]';
      },
    );

    // Keep a whole-token ".0" as Legado's current-root child index, but make
    // descendant " .0" tokens queryable by Dart's CSS selector engine.
    output = output.replaceAllMapped(
      RegExp(r'(?<=\s)\.(\d+)\b'),
      (match) => '*.${match.group(1)!}',
    );

    return output;
  }

  static String _replaceCssPseudoOutsideFunctions(
    String selector,
    RegExp pattern,
    String Function(Match match) replace,
  ) {
    return selector.replaceAllMapped(pattern, (match) {
      if (_isInsideCssFunction(selector, match.start)) {
        return match.group(0) ?? '';
      }
      return replace(match);
    });
  }

  static bool _isInsideCssFunction(String selector, int offset) {
    var parenDepth = 0;
    var bracketDepth = 0;
    var escaped = false;
    String? quote;
    for (var i = 0; i < offset && i < selector.length; i++) {
      final ch = selector[i];
      if (quote != null) {
        if (escaped) {
          escaped = false;
        } else if (ch == '\\') {
          escaped = true;
        } else if (ch == quote) {
          quote = null;
        }
        continue;
      }
      if (ch == '"' || ch == "'") {
        quote = ch;
        continue;
      }
      if (ch == '[') {
        bracketDepth++;
      } else if (ch == ']' && bracketDepth > 0) {
        bracketDepth--;
      } else if (bracketDepth == 0 && ch == '(') {
        parenDepth++;
      } else if (bracketDepth == 0 && ch == ')' && parenDepth > 0) {
        parenDepth--;
      }
    }
    return parenDepth > 0;
  }

  static bool _isDescendantOf(Element child, Element parent) {
    var curr = child.parent;
    while (curr != null) {
      if (curr == parent) return true;
      curr = curr.parent;
    }
    return false;
  }

  static _HtmlRule _parseHtmlRule(String rule, {bool attrAllowed = true}) {
    var cleaned = stripPostProcessors(rule)
        .replaceFirst(RegExp(r'^@css:', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^@get:', caseSensitive: false), '')
        .trim();
    cleaned = sanitizeCssSelector(cleaned);
    if (cleaned.isEmpty || cleaned == 'this') {
      return const _HtmlRule([], 'text');
    }

    final parts = cleaned
        .split('@')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    var attr = 'text';
    if (attrAllowed && parts.length > 1 && _isAttributeToken(parts.last)) {
      attr = parts.removeLast();
    } else if (!attrAllowed &&
        parts.length > 1 &&
        _isKnownAttributeToken(parts.last)) {
      parts.removeLast();
    } else if (parts.length == 1 && _isAttributeToken(parts.first)) {
      attr = parts.first;
      parts.clear();
    }

    final finalSelectors = <String>[];
    for (final selector in parts) {
      final subParts = _splitHtmlSelectorChain(selector);
      finalSelectors.addAll(subParts);
    }

    return _HtmlRule(finalSelectors, attr);
  }

  static List<String> _splitHtmlSelectorChain(String selector) {
    final text = _spaceHtmlCombinators(selector.trim());
    if (text.isEmpty) return const [];

    final legacyClass = RegExp(r'^class\.([^\[\]@>]+)$').firstMatch(text);
    if (legacyClass != null) {
      final content = legacyClass.group(1)?.trim() ?? '';
      final classTokens = content
          .split(RegExp(r'\s+'))
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList();
      if (classTokens.length > 1 &&
          classTokens.every(_looksLikeLegacyClassToken)) {
        return ['class.${classTokens.join('.')}'];
      }
    }

    return _splitHtmlSelectorSteps(text);
  }

  static List<String> _splitHtmlSelectorSteps(String selector) {
    final steps = <String>[];
    final current = StringBuffer();
    var bracketDepth = 0;
    var parenDepth = 0;
    var escaped = false;
    String? quote;

    void flush() {
      final value = current.toString().trim();
      if (value.isNotEmpty && value != '>') steps.add(value);
      current.clear();
    }

    for (var i = 0; i < selector.length; i++) {
      final ch = selector[i];
      if (quote != null) {
        current.write(ch);
        if (escaped) {
          escaped = false;
        } else if (ch == '\\') {
          escaped = true;
        } else if (ch == quote) {
          quote = null;
        }
        continue;
      }
      if (ch == '"' || ch == "'") {
        quote = ch;
        current.write(ch);
        continue;
      }
      if (ch == '[') {
        bracketDepth++;
        current.write(ch);
        continue;
      }
      if (ch == ']' && bracketDepth > 0) {
        bracketDepth--;
        current.write(ch);
        continue;
      }
      if (bracketDepth == 0 && ch == '(') {
        parenDepth++;
        current.write(ch);
        continue;
      }
      if (bracketDepth == 0 && ch == ')' && parenDepth > 0) {
        parenDepth--;
        current.write(ch);
        continue;
      }
      if (bracketDepth == 0 && parenDepth == 0 && RegExp(r'\s').hasMatch(ch)) {
        flush();
      } else {
        current.write(ch);
      }
    }
    flush();
    return steps;
  }

  static String _spaceHtmlCombinators(String selector) {
    final output = StringBuffer();
    var bracketDepth = 0;
    var parenDepth = 0;
    var escaped = false;
    String? quote;
    for (var i = 0; i < selector.length; i++) {
      final ch = selector[i];
      if (quote != null) {
        output.write(ch);
        if (escaped) {
          escaped = false;
        } else if (ch == '\\') {
          escaped = true;
        } else if (ch == quote) {
          quote = null;
        }
        continue;
      }
      if (ch == '"' || ch == "'") {
        quote = ch;
        output.write(ch);
        continue;
      }
      if (ch == '[') {
        bracketDepth++;
        output.write(ch);
        continue;
      }
      if (ch == ']' && bracketDepth > 0) {
        bracketDepth--;
        output.write(ch);
        continue;
      }
      if (bracketDepth == 0 && ch == '(') {
        parenDepth++;
        output.write(ch);
        continue;
      }
      if (bracketDepth == 0 && ch == ')' && parenDepth > 0) {
        parenDepth--;
        output.write(ch);
        continue;
      }
      if (bracketDepth == 0 &&
          parenDepth == 0 &&
          (ch == '>' || ch == '+' || ch == '~')) {
        output.write(' $ch ');
      } else {
        output.write(ch);
      }
    }
    return output.toString();
  }

  static bool _looksLikeLegacyClassToken(String token) {
    if (token.isEmpty) return false;
    if (token.startsWith('.') ||
        token.startsWith('#') ||
        token.startsWith('[') ||
        token.startsWith('class.') ||
        token.startsWith('id.') ||
        token.startsWith('tag.')) {
      return false;
    }
    return RegExp(r'^[A-Za-z0-9_\-]+(?:\.-?\d+)?$').hasMatch(token);
  }

  static bool _isKnownAttributeToken(String token) {
    return _knownAttrs.contains(token);
  }

  static bool _isAttributeToken(String token) {
    if (token.contains(' ') || token.startsWith('.') || token.startsWith('#')) {
      return false;
    }
    if (_isChildrenSelector(token)) return false;
    if (_looksLikeHtmlTagToken(token)) return false;
    if (_isAttrFunctionToken(token)) return true;
    return _knownAttrs.contains(token) ||
        RegExp(r'^[a-zA-Z_][a-zA-Z0-9_\-:]*$').hasMatch(token);
  }

  static bool _isAttrFunctionToken(String token) {
    return RegExp(r'^attr(?:\.[A-Za-z_][A-Za-z0-9_\-:]*)?$').hasMatch(token) ||
        RegExp(r'^attr\(\s*[^)]+\s*\)$').hasMatch(token);
  }

  static bool _looksLikeHtmlTagToken(String token) {
    final value = token.toLowerCase();
    const tags = {
      'a',
      'article',
      'aside',
      'body',
      'button',
      'dd',
      'div',
      'dl',
      'dt',
      'em',
      'footer',
      'form',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'header',
      'i',
      'img',
      'input',
      'label',
      'li',
      'main',
      'nav',
      'ol',
      'option',
      'p',
      'pre',
      'section',
      'select',
      'small',
      'span',
      'strong',
      'table',
      'tbody',
      'td',
      'textarea',
      'th',
      'thead',
      'tr',
      'ul',
    };
    return tags.contains(value);
  }

  static List<Element> _queryChain(Element root, List<String> selectors) {
    if (selectors.isEmpty) return [root];
    var current = <Element>[root];
    for (final selector in selectors) {
      final next = <Element>[];
      for (final node in current) {
        next.addAll(_querySelectorStep(node, selector));
      }
      current = next;
      if (current.isEmpty) return const [];
    }
    return current;
  }

  static List<Element> _querySelectorStep(Element node, String rawSelector) {
    final selectorText = rawSelector.trim();
    final not = _extractTrailingNotPseudo(selectorText);
    if (not != null) {
      final base = _normalizeCssSelector(not.base.isEmpty ? '*' : not.base);
      return _queryNotPseudo(node, base, not.inner);
    }
    final pseudo = _extractTrailingTextPseudo(selectorText);
    if (pseudo != null) {
      final base = _normalizeCssSelector(
        pseudo.base.isEmpty ? '*' : pseudo.base,
      );
      return _queryTextPseudo(node, base, pseudo.type, pseudo.arg);
    }
    final has = _extractTrailingHasPseudo(selectorText);
    if (has != null) {
      final base = _normalizeCssSelector(has.base.isEmpty ? '*' : has.base);
      return _queryHasPseudo(node, base, has.inner);
    }
    final structural = _extractTrailingStructuralPseudo(selectorText);
    if (structural != null) {
      final base = _normalizeCssSelector(
        structural.base.isEmpty ? '*' : structural.base,
      );
      return _queryStructuralPseudo(
        node,
        base,
        structural.type,
        structural.arg,
      );
    }
    final bracket = _parseBracketIndexConfig(rawSelector);
    if (bracket != null) {
      final baseSelector = bracket.baseSelector.trim();
      final selector = _normalizeCssSelector(baseSelector);
      final nodes = _isLegacyTextSelector(baseSelector)
          ? _queryLegacyTextStep(node, baseSelector.substring(5))
          : _isChildrenSelector(baseSelector)
          ? node.children.whereType<Element>().toList()
          : selector.isEmpty || selector == 'this'
          ? node.children.whereType<Element>().toList()
          : _safeQuerySelectorStep(node, selector);
      return _applyBracketIndexes(nodes, bracket);
    }
    final parsed = _parseIndexConfig(rawSelector);
    final baseSelector = parsed.baseSelector.trim();
    final selector = _normalizeCssSelector(baseSelector);

    final nodes = _isLegacyTextSelector(baseSelector)
        ? _queryLegacyTextStep(node, baseSelector.substring(5))
        : _isChildrenSelector(baseSelector)
        ? node.children.whereType<Element>().toList()
        : (selector.isEmpty || selector == 'this') && parsed.hasIndexFilter
        ? node.children.whereType<Element>().toList()
        : selector.isEmpty || selector == 'this'
        ? [node]
        : _safeQuerySelectorStep(node, selector);

    if (parsed.hasIndexFilter && parsed.indexes != null) {
      return _applyLegacyIndexFilter(
        nodes,
        parsed.indexes!,
        exclude: parsed.exclude,
      );
    }
    return nodes;
  }

  /// Extracts a trailing Jsoup text pseudo-class (:matches/:matchesOwn/
  /// :contains/:containsOwn) that the Dart html package cannot evaluate.
  /// Only activates when the pseudo closes at the end of the token and the
  /// base is a simple selector (no combinator/group/nested pseudo); otherwise
  /// returns null so the caller keeps its existing behavior (no regression).
  static ({String base, String type, String arg})? _extractTrailingTextPseudo(
    String selector,
  ) {
    const types = ['matchesOwn', 'containsOwn', 'matches', 'contains'];
    for (final type in types) {
      final token = ':$type(';
      final idx = selector.indexOf(token);
      if (idx < 0) continue;
      final start = idx + token.length;
      var depth = 1;
      var i = start;
      while (i < selector.length && depth > 0) {
        final ch = selector[i];
        if (ch == '(') {
          depth++;
        } else if (ch == ')') {
          depth--;
          if (depth == 0) break;
        }
        i++;
      }
      if (depth != 0) return null;
      if (i != selector.length - 1) return null;
      final arg = selector.substring(start, i);
      final base = selector.substring(0, idx);
      for (final c in const ['>', '+', '~', ',', ' ', '(', ')', ':']) {
        if (base.contains(c)) return null;
      }
      return (base: base, type: type, arg: arg);
    }
    return null;
  }

  static List<Element> _queryTextPseudo(
    Element node,
    String baseSelector,
    String type,
    String arg,
  ) {
    List<Element> candidates;
    try {
      candidates = node.querySelectorAll(
        baseSelector.isEmpty ? '*' : baseSelector,
      );
    } catch (_) {
      return const [];
    }
    return candidates.where((el) => _matchesTextPseudo(el, type, arg)).toList();
  }

  static bool _isLegacyTextSelector(String selector) {
    return selector.trim().startsWith('text.') && selector.trim().length > 5;
  }

  static bool _isChildrenSelector(String selector) {
    final value = selector.trim().toLowerCase();
    return value == 'children' || value == 'childnodes';
  }

  static List<Element> _queryLegacyTextStep(Element node, String needle) {
    final target = needle.trim();
    if (target.isEmpty) return const [];
    final lowerTarget = target.toLowerCase();
    final result = <Element>[];
    if (_ownText(node).toLowerCase().contains(lowerTarget)) result.add(node);
    result.addAll(
      node
          .querySelectorAll('*')
          .where((el) => _ownText(el).toLowerCase().contains(lowerTarget)),
    );
    return result;
  }

  static bool _matchesTextPseudo(Element el, String type, String arg) {
    final isOwn = type == 'matchesOwn' || type == 'containsOwn';
    final isContains = type == 'contains' || type == 'containsOwn';
    final text = isOwn
        ? el.nodes.whereType<Text>().map((n) => n.text).join('')
        : el.text;
    if (isContains) {
      var needle = arg.trim();
      if (needle.length >= 2) {
        final f = needle[0];
        final l = needle[needle.length - 1];
        if ((f == "'" && l == "'") || (f == '"' && l == '"')) {
          needle = needle.substring(1, needle.length - 1);
        }
      }
      return text.toLowerCase().contains(needle.toLowerCase());
    }
    try {
      return _compileFlexibleRegExp(arg).hasMatch(text);
    } catch (_) {
      return text.contains(arg);
    }
  }

  /// Extracts a trailing Jsoup :has(...) pseudo-class that the Dart html
  /// package cannot evaluate. Same safety rules as _extractTrailingTextPseudo:
  /// the pseudo must close at the end of the token and the base must be a
  /// simple selector; otherwise returns null so the caller keeps its existing
  /// behavior (which already returns empty for :has), ensuring no regression.
  static ({String base, String inner})? _extractTrailingHasPseudo(
    String selector,
  ) {
    const token = ':has(';
    final idx = selector.indexOf(token);
    if (idx < 0) return null;
    final start = idx + token.length;
    var depth = 1;
    var i = start;
    while (i < selector.length && depth > 0) {
      final ch = selector[i];
      if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        depth--;
        if (depth == 0) break;
      }
      i++;
    }
    if (depth != 0) return null;
    if (i != selector.length - 1) return null;
    final inner = selector.substring(start, i).trim();
    final base = selector.substring(0, idx);
    for (final c in const ['>', '+', '~', ',', ' ', '(', ')', ':']) {
      if (base.contains(c)) return null;
    }
    return (base: base, inner: inner);
  }

  static List<Element> _queryHasPseudo(
    Element node,
    String baseSelector,
    String inner,
  ) {
    List<Element> candidates;
    try {
      candidates = node.querySelectorAll(
        baseSelector.isEmpty ? '*' : baseSelector,
      );
    } catch (_) {
      return const [];
    }
    // Dart's CSS engine supports neither :has nor a leading child combinator,
    // so approximate a direct-child argument (>foo) as a descendant match.
    var innerSel = inner;
    if (innerSel.startsWith('>')) innerSel = innerSel.substring(1).trim();
    innerSel = _normalizeCssSelector(innerSel);
    if (innerSel.isEmpty) return candidates;
    return candidates.where((el) {
      try {
        return el.querySelector(innerSel) != null;
      } catch (_) {
        return false;
      }
    }).toList();
  }

  static ({String base, String inner})? _extractTrailingNotPseudo(
    String selector,
  ) {
    const token = ':not(';
    var searchStart = 0;
    while (searchStart < selector.length) {
      final idx = selector.indexOf(token, searchStart);
      if (idx < 0) return null;
      searchStart = idx + token.length;
      if (_isInsideCssFunction(selector, idx)) continue;
      final end = _findClosingParen(selector, idx + token.length - 1);
      if (end == null || end != selector.length - 1) return null;
      final base = selector.substring(0, idx);
      if (!_isSimpleSelectorBase(base)) return null;
      return (base: base, inner: selector.substring(idx + token.length, end));
    }
    return null;
  }

  static List<Element> _queryNotPseudo(
    Element node,
    String baseSelector,
    String inner,
  ) {
    final candidates = baseSelector.isEmpty || baseSelector == 'this'
        ? [node]
        : _safeQuerySelectorStep(node, baseSelector);
    return candidates.where((el) => !_matchesNotInner(el, inner)).toList();
  }

  static bool _matchesNotInner(Element el, String inner) {
    final selector = inner.trim();
    if (selector.isEmpty) return false;

    final nestedNot = _extractTrailingNotPseudo(selector);
    if (nestedNot != null) {
      return _matchesElementSelector(
            el,
            nestedNot.base.isEmpty ? '*' : nestedNot.base,
          ) &&
          !_matchesNotInner(el, nestedNot.inner);
    }

    final textPseudo = _extractTrailingTextPseudo(selector);
    if (textPseudo != null) {
      return _matchesElementSelector(
            el,
            textPseudo.base.isEmpty ? '*' : textPseudo.base,
          ) &&
          _matchesTextPseudo(el, textPseudo.type, textPseudo.arg);
    }

    final hasPseudo = _extractTrailingHasPseudo(selector);
    if (hasPseudo != null) {
      return _matchesElementSelector(
            el,
            hasPseudo.base.isEmpty ? '*' : hasPseudo.base,
          ) &&
          _matchesHasPseudoElement(el, hasPseudo.inner);
    }

    final structural = _extractTrailingStructuralPseudo(selector);
    if (structural != null) {
      return _matchesElementSelector(
            el,
            structural.base.isEmpty ? '*' : structural.base,
          ) &&
          _matchesStructuralPseudoElement(el, structural.type, structural.arg);
    }

    return _matchesElementSelector(el, selector);
  }

  static ({String base, String type, String? arg})?
  _extractTrailingStructuralPseudo(String selector) {
    for (final type in const [
      'first-child',
      'last-child',
      'only-child',
      'first-of-type',
      'last-of-type',
      'only-of-type',
    ]) {
      final token = ':$type';
      if (!selector.endsWith(token)) continue;
      final idx = selector.length - token.length;
      if (_isInsideCssFunction(selector, idx)) continue;
      final base = selector.substring(0, idx);
      if (!_isSimpleSelectorBase(base)) return null;
      return (base: base, type: type, arg: null);
    }

    for (final type in const ['nth-child', 'nth-of-type']) {
      final token = ':$type(';
      var searchStart = 0;
      while (searchStart < selector.length) {
        final idx = selector.indexOf(token, searchStart);
        if (idx < 0) break;
        searchStart = idx + token.length;
        if (_isInsideCssFunction(selector, idx)) continue;
        final end = _findClosingParen(selector, idx + token.length - 1);
        if (end == null || end != selector.length - 1) return null;
        final base = selector.substring(0, idx);
        if (!_isSimpleSelectorBase(base)) return null;
        return (
          base: base,
          type: type,
          arg: selector.substring(idx + token.length, end),
        );
      }
    }
    return null;
  }

  static List<Element> _queryStructuralPseudo(
    Element node,
    String baseSelector,
    String type,
    String? arg,
  ) {
    final candidates = baseSelector.isEmpty || baseSelector == 'this'
        ? [node]
        : _safeQuerySelectorStep(node, baseSelector);
    return candidates
        .where((el) => _matchesStructuralPseudoElement(el, type, arg))
        .toList();
  }

  static bool _matchesStructuralPseudoElement(
    Element el,
    String type,
    String? arg,
  ) {
    switch (type) {
      case 'first-child':
        return el.previousElementSibling == null;
      case 'last-child':
        return el.nextElementSibling == null;
      case 'only-child':
        return el.previousElementSibling == null &&
            el.nextElementSibling == null;
      case 'first-of-type':
        final siblings = _sameTypeSiblings(el);
        return siblings.isNotEmpty && siblings.first == el;
      case 'last-of-type':
        final siblings = _sameTypeSiblings(el);
        return siblings.isNotEmpty && siblings.last == el;
      case 'only-of-type':
        return _sameTypeSiblings(el).length == 1;
      case 'nth-child':
        return _matchesCssNthExpression(_elementSiblingIndex(el), arg ?? '');
      case 'nth-of-type':
        return _matchesCssNthExpression(
          _sameTypeSiblings(el).indexOf(el) + 1,
          arg ?? '',
        );
    }
    return false;
  }

  static List<Element> _sameTypeSiblings(Element el) {
    final parent = el.parent;
    if (parent == null) return [el];
    return parent.children
        .where((sibling) => sibling.localName == el.localName)
        .toList();
  }

  static int _elementSiblingIndex(Element el) {
    final parent = el.parent;
    if (parent == null) return 1;
    return parent.children.indexOf(el) + 1;
  }

  static bool _matchesCssNthExpression(int index, String expression) {
    if (index <= 0) return false;
    final value = expression.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final number = int.tryParse(value);
    if (number != null) return index == number;
    if (value == 'odd') return index.isOdd;
    if (value == 'even') return index.isEven;

    final match = RegExp(r'^([+-]?\d*)n([+-]\d+)?$').firstMatch(value);
    if (match == null) return false;
    final aText = match.group(1) ?? '';
    final a = aText.isEmpty || aText == '+'
        ? 1
        : aText == '-'
        ? -1
        : int.tryParse(aText) ?? 0;
    final b = int.tryParse(match.group(2) ?? '0') ?? 0;
    if (a == 0) return index == b;
    if (a > 0) return index >= b && (index - b) % a == 0;
    return index <= b && (b - index) % -a == 0;
  }

  static bool _matchesHasPseudoElement(Element el, String inner) {
    var innerSel = inner.trim();
    if (innerSel.startsWith('>')) innerSel = innerSel.substring(1).trim();
    innerSel = _normalizeCssSelector(sanitizeCssSelector(innerSel));
    if (innerSel.isEmpty) return false;
    try {
      return el.querySelector(innerSel) != null;
    } catch (_) {
      return false;
    }
  }

  static bool _matchesElementSelector(Element el, String selector) {
    final normalized = _normalizeCssSelector(sanitizeCssSelector(selector));
    if (normalized.isEmpty || normalized == '*' || normalized == 'this') {
      return true;
    }

    final structural = _extractTrailingStructuralPseudo(normalized);
    if (structural != null) {
      return _matchesElementSelector(
            el,
            structural.base.isEmpty ? '*' : structural.base,
          ) &&
          _matchesStructuralPseudoElement(el, structural.type, structural.arg);
    }

    try {
      final parent = el.parent;
      if (parent != null) {
        return parent.querySelectorAll(normalized).contains(el);
      }
      return el.querySelectorAll(normalized).contains(el);
    } catch (_) {
      final fixedSelector = _quoteLooseAttributeSelector(normalized);
      if (fixedSelector != normalized) {
        try {
          final parent = el.parent;
          if (parent != null) {
            return parent.querySelectorAll(fixedSelector).contains(el);
          }
        } catch (_) {}
      }
      return false;
    }
  }

  static int? _findClosingParen(String text, int openIndex) {
    var depth = 0;
    var bracketDepth = 0;
    var escaped = false;
    String? quote;
    for (var i = openIndex; i < text.length; i++) {
      final ch = text[i];
      if (quote != null) {
        if (escaped) {
          escaped = false;
        } else if (ch == '\\') {
          escaped = true;
        } else if (ch == quote) {
          quote = null;
        }
        continue;
      }
      if (ch == '"' || ch == "'") {
        quote = ch;
        continue;
      }
      if (ch == '[') {
        bracketDepth++;
        continue;
      }
      if (ch == ']' && bracketDepth > 0) {
        bracketDepth--;
        continue;
      }
      if (bracketDepth == 0 && ch == '(') {
        depth++;
      } else if (bracketDepth == 0 && ch == ')') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return null;
  }

  static bool _isSimpleSelectorBase(String selector) {
    final value = selector.trim();
    if (value.isEmpty) return true;
    var bracketDepth = 0;
    var escaped = false;
    String? quote;
    for (var i = 0; i < value.length; i++) {
      final ch = value[i];
      if (quote != null) {
        if (escaped) {
          escaped = false;
        } else if (ch == '\\') {
          escaped = true;
        } else if (ch == quote) {
          quote = null;
        }
        continue;
      }
      if (ch == '"' || ch == "'") {
        quote = ch;
        continue;
      }
      if (ch == '[') {
        bracketDepth++;
        continue;
      }
      if (ch == ']' && bracketDepth > 0) {
        bracketDepth--;
        continue;
      }
      if (bracketDepth == 0 &&
          (ch == '>' ||
              ch == '+' ||
              ch == '~' ||
              ch == ',' ||
              ch == '(' ||
              ch == ')' ||
              RegExp(r'\s').hasMatch(ch))) {
        return false;
      }
    }
    return bracketDepth == 0 && quote == null;
  }

  static List<Element> _safeQuerySelectorStep(Element node, String selector) {
    try {
      final parent = node.parent;
      if (parent != null) {
        final allMatches = parent.querySelectorAll(selector);
        return allMatches
            .where((el) => el == node || _isDescendantOf(el, node))
            .toList();
      }
      return node.querySelectorAll(selector);
    } catch (_) {
      final fixedSelector = _quoteLooseAttributeSelector(selector);
      if (fixedSelector != selector) {
        try {
          return node.querySelectorAll(fixedSelector);
        } catch (_) {
          // Fall through to manual attribute matching.
        }
      }
      final manual = _manualAttributeSelector(node, selector);
      return manual ?? const [];
    }
  }

  static String _quoteLooseAttributeSelector(String selector) {
    return selector.replaceAllMapped(
      RegExp(r"""\[([A-Za-z0-9_\-:]+)([~|^$*]?=)([^\]"']+)\]"""),
      (match) {
        final attr = match.group(1) ?? '';
        final op = match.group(2) ?? '=';
        final value = (match.group(3) ?? '').trim();
        if (value.isEmpty ||
            value.startsWith('"') ||
            value.startsWith("'") ||
            RegExp(r'^[A-Za-z0-9_\-]+$').hasMatch(value)) {
          return match.group(0) ?? '';
        }
        final escaped = value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
        return '[$attr$op"$escaped"]';
      },
    );
  }

  static List<Element>? _manualAttributeSelector(
    Element node,
    String selector,
  ) {
    final match = RegExp(
      r'^(?:(\w+))?\[([A-Za-z0-9_\-:]+)([~|^$*]?=)([^\]]+)\]$',
    ).firstMatch(selector.trim());
    if (match == null) return null;
    final tag = match.group(1)?.toLowerCase();
    final attr = match.group(2) ?? '';
    final op = match.group(3) ?? '=';
    var expected = (match.group(4) ?? '').trim();
    if ((expected.startsWith('"') && expected.endsWith('"')) ||
        (expected.startsWith("'") && expected.endsWith("'"))) {
      expected = expected.substring(1, expected.length - 1);
    }

    bool matches(Element element) {
      if (tag != null && element.localName?.toLowerCase() != tag) return false;
      final actual = element.attributes[attr];
      if (actual == null) return false;
      switch (op) {
        case '~=':
          try {
            if (_compileFlexibleRegExp(expected).hasMatch(actual)) return true;
          } catch (_) {}
          return actual.split(RegExp(r'\s+')).contains(expected) ||
              actual.contains(expected);
        case '^=':
          return actual.startsWith(expected);
        case r'$=':
          return actual.endsWith(expected);
        case '*=':
          return actual.contains(expected);
        case '|=':
          return actual == expected || actual.startsWith('$expected-');
        default:
          return actual == expected;
      }
    }

    final result = <Element>[];
    if (matches(node)) result.add(node);
    result.addAll(node.querySelectorAll('*').where(matches));
    return result;
  }

  static ({
    String baseSelector,
    bool hasIndexFilter,
    bool exclude,
    List<int>? indexes,
  })
  _parseIndexConfig(String selector) {
    // Legacy Legado indexes:
    //   base.0       selects index 0
    //   base.0:2:-1  selects listed indexes
    //   base!0:-1    excludes listed indexes
    //
    // Official Legado treats ':' here as an index-list separator, not a
    // range. Ranges belong to bracket syntax, e.g. base[1:-2].
    final legacy = RegExp(
      r'^(.*?)([.!])\s*((?:-?\d+)(?:(?::|,)\s*-?\d+)*)\s*$',
    ).firstMatch(selector);
    if (legacy != null) {
      final rawIndexes = legacy.group(3) ?? '';
      final indexes = rawIndexes
          .split(RegExp(r'[:,]'))
          .map((part) => int.tryParse(part.trim()))
          .whereType<int>()
          .toList();
      if (indexes.isNotEmpty) {
        return (
          baseSelector: legacy.group(1)?.trim() ?? '',
          hasIndexFilter: true,
          exclude: legacy.group(2) == '!',
          indexes: indexes,
        );
      }
    }

    return (
      baseSelector: selector,
      hasIndexFilter: false,
      exclude: false,
      indexes: null,
    );
  }

  static List<Element> _applyLegacyIndexFilter(
    List<Element> nodes,
    List<int> indexes, {
    required bool exclude,
  }) {
    if (nodes.isEmpty) return const [];
    final normalized = <int>{};
    for (final index in indexes) {
      final idx = _normalizeIndex(index, nodes.length);
      if (idx >= 0 && idx < nodes.length) normalized.add(idx);
    }
    if (exclude) {
      return [
        for (var i = 0; i < nodes.length; i++)
          if (!normalized.contains(i)) nodes[i],
      ];
    }
    return [for (final index in normalized) nodes[index]];
  }

  static _BracketIndexConfig? _parseBracketIndexConfig(String selector) {
    final trimmed = selector.trim();
    if (!trimmed.endsWith(']')) return null;
    final open = trimmed.lastIndexOf('[');
    if (open < 0) return null;
    var body = trimmed.substring(open + 1, trimmed.length - 1).trim();
    if (body.isEmpty) return null;
    final exclude = body.startsWith('!');
    if (exclude) body = body.substring(1).trim();
    if (body.isEmpty) return null;

    final items = <_BracketIndexItem>[];
    for (final part in body.split(',')) {
      final token = part.trim();
      if (token.isEmpty) return null;
      final pieces = token.split(':').map((s) => s.trim()).toList();
      if (pieces.length > 3) return null;
      if (pieces.length == 1) {
        final index = int.tryParse(pieces.single);
        if (index == null) return null;
        items.add(_BracketIndexSingle(index));
        continue;
      }
      int? parseOptional(String value) =>
          value.isEmpty ? null : int.tryParse(value);
      final start = parseOptional(pieces[0]);
      final end = parseOptional(pieces[1]);
      if ((pieces[0].isNotEmpty && start == null) ||
          (pieces[1].isNotEmpty && end == null)) {
        return null;
      }
      var step = 1;
      if (pieces.length == 3) {
        final parsedStep = int.tryParse(pieces[2]);
        if (parsedStep == null) return null;
        step = parsedStep;
      }
      items.add(_BracketIndexRange(start, end, step));
    }
    return _BracketIndexConfig(
      baseSelector: trimmed.substring(0, open).trim(),
      exclude: exclude,
      items: items,
    );
  }

  static List<Element> _applyBracketIndexes(
    List<Element> nodes,
    _BracketIndexConfig config,
  ) {
    if (nodes.isEmpty) return const [];
    final indexes = <int>{};
    for (final item in config.items) {
      if (item is _BracketIndexSingle) {
        final index = _normalizeIndex(item.index, nodes.length);
        if (index >= 0 && index < nodes.length) indexes.add(index);
      } else if (item is _BracketIndexRange) {
        indexes.addAll(_expandBracketRange(item, nodes.length));
      }
    }
    if (config.exclude) {
      return [
        for (var i = 0; i < nodes.length; i++)
          if (!indexes.contains(i)) nodes[i],
      ];
    }
    return [for (final index in indexes) nodes[index]];
  }

  static Iterable<int> _expandBracketRange(_BracketIndexRange range, int len) {
    if (len <= 0) return const [];
    var start = range.start ?? 0;
    if (start < 0) start += len;
    var end = range.end ?? (len - 1);
    if (end < 0) end += len;

    if ((start < 0 && end < 0) || (start >= len && end >= len)) {
      return const [];
    }
    start = start.clamp(0, len - 1).toInt();
    end = end.clamp(0, len - 1).toInt();
    if (start == end || range.step >= len) return [start];

    final step = range.step > 0
        ? range.step
        : (-range.step < len ? range.step + len : 1);
    if (step <= 0) return const [];

    final result = <int>[];
    if (end > start) {
      for (var i = start; i <= end; i += step) {
        result.add(i);
      }
    } else {
      for (var i = start; i >= end; i -= step) {
        result.add(i);
      }
    }
    return result;
  }

  static List<T> _interleaveLists<T>(List<List<T>> lists) {
    if (lists.isEmpty) return const [];
    final result = <T>[];
    final maxLength = lists
        .map((list) => list.length)
        .fold<int>(0, (max, length) => length > max ? length : max);
    for (var i = 0; i < maxLength; i++) {
      for (final list in lists) {
        if (i < list.length) result.add(list[i]);
      }
    }
    return result;
  }

  static int _normalizeIndex(int index, int length) {
    return index < 0 ? length + index : index;
  }

  static String _normalizeCssSelector(String selector) {
    var output = selector.trim();
    if (output == 'text') return 'this';

    // Handle class.name1 name2 name3 -> .name1.name2.name3
    if (output.startsWith('class.')) {
      final String classContent = output.substring(6);
      final classes = classContent
          .split(RegExp(r'[\s\.]+'))
          .where((s) => s.trim().isNotEmpty)
          .toList();
      if (classes.isNotEmpty) {
        output = '.${classes.join('.')}';
      }
    }

    output = output.replaceAllMapped(
      RegExp(r'\bid\.([A-Za-z0-9_\-]+)'),
      (match) => '#${match.group(1)}',
    );
    output = output.replaceAllMapped(
      RegExp(r'\bclass\.([A-Za-z0-9_\-]+)'),
      (match) => '.${match.group(1)}',
    );
    output = output.replaceAllMapped(
      RegExp(r'\btag\.([A-Za-z0-9_\-]+)'),
      (match) => match.group(1) ?? '',
    );
    return output;
  }

  static void _collectTextNodes(Node node, List<String> result) {
    if (node is Text) {
      final t = node.text.trim();
      if (t.isNotEmpty) result.add(t);
      return;
    }
    for (final child in node.nodes) {
      if (child is Text) {
        final t = child.text.trim();
        if (t.isNotEmpty) result.add(t);
      }
    }
  }

  static String _htmlValue(Element target, String attrName) {
    final normalizedAttr = _normalizeAttrName(attrName);
    final attrKey = normalizedAttr.toLowerCase();
    switch (attrKey) {
      case 'text':
        return target.text.trim();
      case 'textnodes':
        final list = <String>[];
        _collectTextNodes(target, list);
        return list.join('\n');
      case 'owntext':
        return _ownText(target);
      case 'html':
        return target.innerHtml.trim();
      case 'outerhtml':
      case 'all':
        return target.outerHtml.trim();
      default:
        final direct = target.attributes[normalizedAttr];
        if (direct != null && direct.isNotEmpty) return direct;

        // Fallback: search descendants
        if (normalizedAttr == 'href') {
          final childHref = target.querySelector('a')?.attributes['href'];
          if (childHref != null && childHref.isNotEmpty) return childHref;
        }
        if (const [
          'src',
          'data-src',
          'data-original',
          'alt',
        ].contains(normalizedAttr)) {
          final childSrc = target
              .querySelector('img')
              ?.attributes[normalizedAttr];
          if (childSrc != null && childSrc.isNotEmpty) return childSrc;
        }
        for (final desc in target.querySelectorAll('*')) {
          final val = desc.attributes[normalizedAttr];
          if (val != null && val.isNotEmpty) return val;
        }
        return '';
    }
  }

  static String _normalizeAttrName(String attrName) {
    final trimmed = attrName.trim();
    final fn = RegExp(r'^attr\(\s*([^)]+?)\s*\)$').firstMatch(trimmed);
    if (fn != null) return fn.group(1)?.trim() ?? trimmed;
    if (trimmed.startsWith('attr.')) return trimmed.substring(5).trim();
    return trimmed;
  }

  static String _ownText(Element target) {
    return target.nodes
        .whereType<Text>()
        .map((node) => node.text)
        .join('')
        .trim();
  }

  static String _applyJsPostProcessors(String value, String rule) {
    final lowerRule = rule.toLowerCase();
    if (!lowerRule.contains('@js:') && !lowerRule.contains('<js>')) {
      return value;
    }
    var output = value;
    final simpleOutput = _evaluateSimpleJsPostProcessor(output, rule);
    if (simpleOutput.isNotEmpty) output = simpleOutput;

    final aesMatch = RegExp(
      r'''java\.aesBase64DecodeToString\(\s*result\s*,\s*["']([^"']+)["']\s*,\s*["']([^"']+)["']\s*,\s*["']([^"']*)["']''',
    ).firstMatch(rule);
    if (aesMatch != null) {
      final key = aesMatch.group(1) ?? '';
      final third = aesMatch.group(2) ?? '';
      final fourth = aesMatch.group(3) ?? '';
      final thirdIsTransformation =
          third.contains('/') ||
          RegExp(
            r'^(?:AES|DES|DESede|TripleDES)',
            caseSensitive: false,
          ).hasMatch(third);
      final transformation = thirdIsTransformation
          ? third
          : (fourth.isEmpty ? 'AES/CBC/PKCS5Padding' : fourth);
      final iv = thirdIsTransformation ? fourth : third;
      final decoded = _cipherBase64Decode(output, key, iv, transformation);
      if (decoded.isNotEmpty) output = decoded;
    }

    if (RegExp(
      r'java\.(base64Decode|base64DecodeToString)\(\s*result\s*\)',
    ).hasMatch(rule)) {
      try {
        output = utf8.decode(base64Decode(output), allowMalformed: true);
      } catch (_) {
        // Keep the original value if it is not valid base64.
      }
    }

    if (RegExp(r'java\.md5Encode\(\s*result\s*\)').hasMatch(rule)) {
      output = md5.convert(utf8.encode(output)).toString();
    }

    final matchJoin = RegExp(
      r'''result\.match\(/(.+?)/[gimsu]*\)\.join\(["']([^"']*)["']\)''',
    ).firstMatch(rule);
    if (matchJoin != null) {
      try {
        final pattern = matchJoin.group(1) ?? '';
        final joiner = matchJoin.group(2) ?? '';
        output = _compileFlexibleRegExp(pattern)
            .allMatches(output)
            .map((match) => match.group(0) ?? '')
            .where((text) => text.isNotEmpty)
            .join(joiner);
      } catch (_) {
        // Unsupported JS regex syntax; leave the original value untouched.
      }
    }

    return output;
  }

  static String _evaluateSimpleJsPostProcessor(String result, String rule) {
    final script = _extractJsPostProcessorScript(rule);
    if (script.isEmpty) return '';
    var expression = script.trim();
    expression = expression.replaceFirst(RegExp(r'^return\s+'), '');
    expression = expression.replaceAll(RegExp(r';\s*$'), '').trim();
    if (RegExp(r'^java\.(t2s|s2t)\(\s*result\s*\)$').hasMatch(expression)) {
      return result;
    }

    final stringChain = _evaluateResultStringChain(result, expression);
    if (stringChain != null) return stringChain;

    final assigned = _evaluateResultAssignmentScript(result, expression);
    if (assigned != null) return assigned;

    final replaced = _evaluateResultReplaceExpression(result, expression);
    if (replaced != null) return replaced;

    final startsWithMatch = RegExp(
      r'''^result\.startsWith\(["']([^"']+)["']\)\s*\?\s*result\s*:\s*(.+)$''',
    ).firstMatch(expression);
    if (startsWithMatch != null) {
      final prefix = startsWithMatch.group(1) ?? '';
      if (result.startsWith(prefix)) return result;
      expression = startsWithMatch.group(2)?.trim() ?? '';
    }

    final tokens = _splitJsConcatExpression(expression);
    if (tokens.length <= 1) return '';
    final firstLiteral = tokens
        .map((token) => token.trim())
        .where(_isQuotedJsString)
        .map(_decodeJsStringLiteral)
        .firstWhere((text) => text.isNotEmpty, orElse: () => '');
    if (firstLiteral.isNotEmpty && result.startsWith(firstLiteral)) return '';
    final buffer = StringBuffer();
    var usedResult = false;
    for (final token in tokens) {
      final value = token.trim();
      if (value == 'result' || value == 'String(result)') {
        buffer.write(result);
        usedResult = true;
      } else if (_isQuotedJsString(value)) {
        buffer.write(_decodeJsStringLiteral(value));
      } else if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(value)) {
        buffer.write(value);
      } else {
        return '';
      }
    }
    final output = buffer.toString();
    return usedResult ? output : '';
  }

  static String? _evaluateResultAssignmentScript(
    String result,
    String expression,
  ) {
    final ifElse = RegExp(
      r'''^if\s*\(\s*result\.match\(/((?:\\.|[^/])*)/[a-z]*\)\s*\)\s*\{\s*result\s*=\s*([\s\S]*?)\s*;?\s*\}\s*else\s*\{\s*result\s*=\s*([\s\S]*?)\s*;?\s*\}$''',
      dotAll: true,
    ).firstMatch(expression);
    if (ifElse != null) {
      final conditionPattern = _decodeJsRegexPattern(ifElse.group(1) ?? '');
      final branch = RegExp(conditionPattern).hasMatch(result)
          ? ifElse.group(2)
          : ifElse.group(3);
      return _evaluateResultMatchExpression(result, branch ?? '');
    }

    final assignment = RegExp(
      r'''^result\s*=\s*([\s\S]+)$''',
      dotAll: true,
    ).firstMatch(expression);
    if (assignment != null) {
      return _evaluateResultMatchExpression(result, assignment.group(1) ?? '');
    }
    return null;
  }

  static String? _evaluateResultMatchExpression(String result, String expr) {
    final expression = expr.trim().replaceAll(RegExp(r';\s*$'), '').trim();
    final direct = RegExp(
      r'''^result\.match\(/((?:\\.|[^/])*)/[a-z]*\)\[(\d+)\]$''',
      dotAll: true,
    ).firstMatch(expression);
    if (direct != null) {
      return _matchJsRegexGroup(
        result,
        direct.group(1) ?? '',
        int.tryParse(direct.group(2) ?? '') ?? 0,
      );
    }

    final prefixed = RegExp(
      r'''^(["'`])([\s\S]*?)\1\s*\+\s*result\.match\(/((?:\\.|[^/])*)/[a-z]*\)\[(\d+)\]$''',
      dotAll: true,
    ).firstMatch(expression);
    if (prefixed != null) {
      final matched = _matchJsRegexGroup(
        result,
        prefixed.group(3) ?? '',
        int.tryParse(prefixed.group(4) ?? '') ?? 0,
      );
      if (matched == null) return null;
      return _decodeJsEscaped(prefixed.group(2) ?? '') + matched;
    }
    return null;
  }

  static String? _matchJsRegexGroup(String value, String jsPattern, int index) {
    try {
      final pattern = _decodeJsRegexPattern(jsPattern);
      final match = RegExp(pattern, dotAll: true).firstMatch(value);
      if (match == null || index > match.groupCount) return null;
      return match.group(index) ?? '';
    } catch (_) {
      return null;
    }
  }

  static String _decodeJsRegexPattern(String pattern) {
    return pattern.replaceAll(r'\/', '/');
  }

  static String? _evaluateResultReplaceExpression(
    String result,
    String expression,
  ) {
    final literalMatch = RegExp(
      r'''^result\.replace\(\s*(["'])(.*?)\1\s*,\s*(["'])(.*?)\3\s*\)$''',
      dotAll: true,
    ).firstMatch(expression);
    if (literalMatch != null) {
      return result.replaceFirst(
        _decodeJsEscaped(literalMatch.group(2) ?? ''),
        _decodeJsEscaped(literalMatch.group(4) ?? ''),
      );
    }

    final regexMatch = RegExp(
      r'''^result\.replace\(\s*/((?:\\.|[^/])*)/([gimsuy]*)\s*,\s*(["'])(.*?)\3\s*\)$''',
      dotAll: true,
    ).firstMatch(expression);
    if (regexMatch != null) {
      try {
        final pattern = _decodeJsRegexPattern(regexMatch.group(1) ?? '');
        final flags = regexMatch.group(2) ?? '';
        final replacement = _decodeJsEscaped(regexMatch.group(4) ?? '');
        final regex = RegExp(
          pattern,
          caseSensitive: !flags.contains('i'),
          multiLine: flags.contains('m'),
          dotAll: flags.contains('s'),
        );
        return flags.contains('g')
            ? result.replaceAllMapped(
                regex,
                (match) => _expandJsReplacement(replacement, match),
              )
            : result.replaceFirstMapped(
                regex,
                (match) => _expandJsReplacement(replacement, match),
              );
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static String? _evaluateResultStringChain(String result, String expression) {
    var output = result;
    var rest = expression.trim();
    if (rest.startsWith('String(result)')) {
      rest = rest.substring('String(result)'.length).trimLeft();
    } else if (rest.startsWith('result')) {
      rest = rest.substring('result'.length).trimLeft();
    } else {
      return null;
    }

    if (rest.isEmpty) return output;
    while (rest.isNotEmpty) {
      if (rest.startsWith('.trim()')) {
        output = output.trim();
        rest = rest.substring('.trim()'.length).trimLeft();
        continue;
      }
      if (rest.startsWith('.toLowerCase()')) {
        output = output.toLowerCase();
        rest = rest.substring('.toLowerCase()'.length).trimLeft();
        continue;
      }
      if (rest.startsWith('.toUpperCase()')) {
        output = output.toUpperCase();
        rest = rest.substring('.toUpperCase()'.length).trimLeft();
        continue;
      }
      if (rest.startsWith('.replace(')) {
        final close = _findClosingParen(rest, '.replace'.length);
        if (close == null || close < 0) return null;
        final call = 'result${rest.substring(0, close + 1)}';
        final replaced = _evaluateResultReplaceExpression(output, call);
        if (replaced == null) return null;
        output = replaced;
        rest = rest.substring(close + 1).trimLeft();
        continue;
      }
      if (rest == ';') return output;
      return null;
    }
    return output;
  }

  static String _expandJsReplacement(String replacement, Match match) {
    return replacement.replaceAllMapped(RegExp(r'\$(\$|&|\d{1,2})'), (token) {
      final value = token.group(1) ?? '';
      if (value == r'$') return r'$';
      if (value == '&') return match.group(0) ?? '';
      final index = int.tryParse(value);
      if (index == null || index > match.groupCount)
        return token.group(0) ?? '';
      return match.group(index) ?? '';
    });
  }

  static String _extractJsPostProcessorScript(String rule) {
    final lowerRule = rule.toLowerCase();
    final atJs = lowerRule.indexOf('@js:');
    if (atJs >= 0) {
      return rule.substring(atJs + 4).split('##').first.trim();
    }
    if (lowerRule.contains('<js>')) {
      return (_jsTagBody(rule) ?? '').trim();
    }
    return '';
  }

  static List<String> _splitJsConcatExpression(String expression) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    var quote = 0;
    var escaped = false;
    var depth = 0;
    for (var i = 0; i < expression.length; i++) {
      final unit = expression.codeUnitAt(i);
      if (quote != 0) {
        buffer.writeCharCode(unit);
        if (escaped) {
          escaped = false;
        } else if (unit == 0x5c) {
          escaped = true;
        } else if (unit == quote) {
          quote = 0;
        }
        continue;
      }
      if (unit == 0x22 || unit == 0x27 || unit == 0x60) {
        quote = unit;
        buffer.writeCharCode(unit);
        continue;
      }
      if (unit == 0x28 || unit == 0x5b || unit == 0x7b) {
        depth++;
        buffer.writeCharCode(unit);
        continue;
      }
      if (unit == 0x29 || unit == 0x5d || unit == 0x7d) {
        if (depth > 0) depth--;
        buffer.writeCharCode(unit);
        continue;
      }
      if (unit == 0x2b && depth == 0) {
        tokens.add(buffer.toString());
        buffer.clear();
        continue;
      }
      buffer.writeCharCode(unit);
    }
    tokens.add(buffer.toString());
    return tokens;
  }

  static bool _isQuotedJsString(String value) {
    if (value.length < 2) return false;
    final first = value.codeUnitAt(0);
    final last = value.codeUnitAt(value.length - 1);
    return (first == 0x22 || first == 0x27 || first == 0x60) && first == last;
  }

  static String _decodeJsStringLiteral(String value) {
    final body = value.substring(1, value.length - 1);
    return _decodeJsEscaped(body);
  }

  static String _decodeJsEscaped(String body) {
    return body
        .replaceAll(r'\"', '"')
        .replaceAll(r"\'", "'")
        .replaceAll(r'\`', '`')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\t', '\t')
        .replaceAll(r'\\', '\\');
  }

  static String _cipherBase64Decode(
    String value,
    String key,
    String iv,
    String transformation,
  ) {
    try {
      final upper = transformation.toUpperCase();
      final isDes = upper.contains('DES');
      final mode = upper.contains('/ECB/') ? 'ecb' : 'cbc';
      final engine = isDes ? DESedeEngine() : AESEngine();
      final keyBytes = isDes
          ? _desCompatibleKeyBytes(key)
          : Uint8List.fromList(utf8.encode(key));
      if (!isDes &&
          keyBytes.length != 16 &&
          keyBytes.length != 24 &&
          keyBytes.length != 32) {
        return '';
      }
      final keyParam = isDes
          ? DESedeParameters(keyBytes)
          : KeyParameter(keyBytes);
      final cipher = PaddedBlockCipherImpl(
        PKCS7Padding(),
        mode == 'ecb' ? ECBBlockCipher(engine) : CBCBlockCipher(engine),
      );
      if (mode == 'ecb') {
        cipher.init(
          false,
          PaddedBlockCipherParameters<CipherParameters, Null>(keyParam, null),
        );
      } else {
        var ivBytes = Uint8List.fromList(utf8.encode(iv));
        if (ivBytes.length != engine.blockSize) {
          ivBytes = Uint8List(engine.blockSize);
        }
        cipher.init(
          false,
          PaddedBlockCipherParameters<ParametersWithIV<CipherParameters>, Null>(
            ParametersWithIV<CipherParameters>(keyParam, ivBytes),
            null,
          ),
        );
      }
      final input = base64Decode(value.trim());
      final output = cipher.process(Uint8List.fromList(input));
      return utf8.decode(output, allowMalformed: true).trim();
    } catch (_) {
      return '';
    }
  }

  static Uint8List _desCompatibleKeyBytes(String key) {
    final raw = Uint8List.fromList(utf8.encode(key));
    if (raw.length == 24) return raw;
    if (raw.length == 16) {
      return Uint8List.fromList([...raw, ...raw.sublist(0, 8)]);
    }
    if (raw.length == 8) {
      return Uint8List.fromList([...raw, ...raw, ...raw]);
    }
    throw ArgumentError('Invalid DES key length');
  }

  static bool _isPureJsonPath(String rule) {
    final trimmed = stripPostProcessors(rule).trim();
    final normalized = _stripJsonRulePrefix(trimmed).trim();
    return (trimmed.startsWith(r'$') || _hasJsonRulePrefix(trimmed)) &&
        normalized.isNotEmpty &&
        !normalized.contains(' ') &&
        !normalized.contains('/') &&
        !normalized.contains(':') &&
        !normalized.contains('{') &&
        !normalized.contains('}');
  }

  static bool _containsNonBracketJsonPath(String rule) {
    if (_isPureJsonPath(rule)) return false;
    return rule.contains(r'$.');
  }

  static String _interpolateNonBracketJsonPath(dynamic json, String rule) {
    if (json == null) return rule;
    var output = rule;
    final regex = RegExp(r'\$\.[A-Za-z0-9_\.\[\]\*]+');
    final matches = regex.allMatches(rule).toList();
    for (final match in matches.reversed) {
      final path = match.group(0)!;
      final val = _extractSingleJsonValue(json, path);
      output = output.replaceRange(match.start, match.end, val);
    }
    return output;
  }
}

class _HtmlRule {
  final List<String> selectors;
  final String attr;

  const _HtmlRule(this.selectors, this.attr);
}

class _BracketIndexConfig {
  final String baseSelector;
  final bool exclude;
  final List<_BracketIndexItem> items;

  const _BracketIndexConfig({
    required this.baseSelector,
    required this.exclude,
    required this.items,
  });
}

abstract class _BracketIndexItem {
  const _BracketIndexItem();
}

class _BracketIndexSingle extends _BracketIndexItem {
  final int index;

  const _BracketIndexSingle(this.index);
}

class _BracketIndexRange extends _BracketIndexItem {
  final int? start;
  final int? end;
  final int step;

  const _BracketIndexRange(this.start, this.end, this.step);
}
