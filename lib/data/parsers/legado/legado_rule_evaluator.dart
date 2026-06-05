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
    'html',
    'outerHtml',
    'href',
    'src',
    'data-src',
    'data-original',
    'content',
    'value',
    'title',
    'alt',
  };

  static String extractJsonValue(dynamic json, String rule) {
    if (rule.isEmpty) return '';
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
    if (rule.contains('||')) {
      final parts = rule.split('||');
      for (final part in parts) {
        final val = extractJsonValue(json, part.trim());
        if (val.isNotEmpty) return val;
      }
      return '';
    }

    // Handle && (splicing)
    if (rule.contains('&&')) {
      final parts = rule.split('&&');
      final results = <String>[];
      for (final part in parts) {
        final val = extractJsonValue(json, part.trim());
        if (val.isNotEmpty) results.add(val);
      }
      return results.join('\n');
    }

    // Handle %% (cross merge)
    if (rule.contains('%%')) {
      final parts = rule.split('%%');
      final results = <String>[];
      for (final part in parts) {
        final val = extractJsonValue(json, part.trim());
        if (val.isNotEmpty) results.add(val);
      }
      return results.join('\n');
    }

    var ruleText = rule;
    if (json is Map || json is List) {
      if (_containsJsonTemplate(ruleText)) {
        return applyPostProcessors(
          _interpolateJsonTemplate(json, ruleText),
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
    if (rule.contains('||')) {
      final parts = rule.split('||');
      for (final part in parts) {
        final val = extractJsonNodes(json, part.trim());
        if (val.isNotEmpty) return val;
      }
      return const [];
    }

    // Handle && (splicing)
    if (rule.contains('&&')) {
      final parts = rule.split('&&');
      final results = <dynamic>[];
      for (final part in parts) {
        results.addAll(extractJsonNodes(json, part.trim()));
      }
      return results;
    }

    // Handle %% (cross merge)
    if (rule.contains('%%')) {
      final parts = rule.split('%%');
      final results = <dynamic>[];
      for (final part in parts) {
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

    // Handle || (fallback)
    if (rule.contains('||')) {
      final parts = rule.split('||');
      for (final part in parts) {
        final val = extractHtmlValue(node, part.trim());
        if (val.isNotEmpty) return val;
      }
      return '';
    }

    // Handle && (splicing)
    if (rule.contains('&&')) {
      final parts = rule.split('&&');
      final results = <String>[];
      for (final part in parts) {
        final val = extractHtmlValue(node, part.trim());
        if (val.isNotEmpty) results.add(val);
      }
      return results.join('\n');
    }

    // Handle %% (cross merge)
    if (rule.contains('%%')) {
      final parts = rule.split('%%');
      final results = <String>[];
      for (final part in parts) {
        final val = extractHtmlValue(node, part.trim());
        if (val.isNotEmpty) results.add(val);
      }
      return results.join('\n');
    }

    return _extractSingleHtmlValue(node, rule);
  }

  static String _extractSingleHtmlValue(Element node, String rule) {
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
        final result = HtmlXPath.node(node).query(xpathRule(rule));
        final attr = result.attr;
        if (attr != null) return applyPostProcessors(attr.trim(), rule);
        return applyPostProcessors(result.node?.text?.trim() ?? '', rule);
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

    // Handle || (fallback)
    if (rule.contains('||')) {
      final parts = rule.split('||');
      for (final part in parts) {
        final val = queryAll(document, part.trim());
        if (val.isNotEmpty) return val;
      }
      return [];
    }

    // Handle && (splicing)
    if (rule.contains('&&')) {
      final parts = rule.split('&&');
      final results = <Element>[];
      for (final part in parts) {
        results.addAll(queryAll(document, part.trim()));
      }
      return results;
    }

    // Handle %% (cross merge)
    if (rule.contains('%%')) {
      final parts = rule.split('%%');
      final results = <Element>[];
      for (final part in parts) {
        results.addAll(queryAll(document, part.trim()));
      }
      return results;
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

    // Handle || (fallback)
    if (rule.contains('||')) {
      final parts = rule.split('||');
      for (final part in parts) {
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
    if (cleaned.startsWith('@json:') || cleaned.startsWith('json:')) {
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
    final closeJs = text.lastIndexOf('</js>');
    if (closeJs >= 0) {
      final suffix = text.substring(closeJs + '</js>'.length).trim();
      if (suffix.isNotEmpty) text = suffix;
    }
    return text
        .split('\n')
        .first
        .split('@js:')
        .first
        .split('@put:')
        .first
        .split('@get:')
        .first
        .split('##')
        .first
        .trim();
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

      if (line.contains('@get:')) {
        final key = line.split('@get:')[1].split(RegExp(r'[@#]')).first.trim();
        try {
          final cached = LegadoJsEngine().evaluate('java.get("$key")');
          if (cached.trim().isNotEmpty) output = cached;
        } catch (_) {}
      }

      if (line.startsWith('<js>') ||
          line.contains('</js>') ||
          line.startsWith('@js:')) {
        try {
          final jsPart = line.startsWith('@js:')
              ? line
              : '<js>${line.split('<js>')[1].split('</js>').first}</js>';
          final evaluated = LegadoJsEngine().evaluate(
            jsPart,
            variables: {'result': output},
          );
          if (evaluated.trim().isNotEmpty) output = evaluated;
        } catch (_) {}
      } else if (line.contains('@put:')) {
        final key = line.split('@put:')[1].split(RegExp(r'[@#]')).first.trim();
        try {
          LegadoJsEngine().evaluate(
            'java.put("$key", result)',
            variables: {'result': output},
          );
        } catch (_) {}
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
          try {
            if (onlyFirst) {
              output = output.replaceFirst(_compileFlexibleRegExp(pattern), replacement);
            } else {
              output = output.replaceAll(_compileFlexibleRegExp(pattern), replacement);
            }
          } catch (_) {
            if (onlyFirst) {
              output = output.replaceFirst(pattern, replacement);
            } else {
              output = output.replaceAll(pattern, replacement);
            }
          }
        }
      } else {
        if (line.contains('{result}') || line.contains('{' '{result}' '}')) {
          output = line
              .replaceAll('{result}', output)
              .replaceAll('{' '{result}' '}', output);
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
    final marker = rule.indexOf('@js:');
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
    if (rule.contains('@get:')) {
      final key = rule.split('@get:')[1].split(RegExp(r'[@#]')).first.trim();
      try {
        final cached = LegadoJsEngine().evaluate('java.get("$key")');
        if (cached.trim().isNotEmpty) output = cached;
      } catch (_) {}
    }

    if (rule.contains('@js:') || rule.contains('<js>')) {
      try {
        final jsPart = rule.contains('@js:')
            ? '@js:${rule.split('@js:')[1].split('##').first}'
            : '<js>${rule.split('<js>')[1].split('</js>').first}</js>';
        final evaluated = LegadoJsEngine().evaluate(
          jsPart,
          variables: {'result': output},
        );
        if (evaluated.trim().isNotEmpty) output = evaluated;
      } catch (_) {}
    }

    if (rule.contains('@put:')) {
      final key = rule.split('@put:')[1].split(RegExp(r'[@#]')).first.trim();
      try {
        LegadoJsEngine().evaluate(
          'java.put("$key", result)',
          variables: {'result': output},
        );
      } catch (_) {}
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
        try {
          if (onlyFirst) {
            output = output.replaceFirst(_compileFlexibleRegExp(pattern), replacement);
          } else {
            output = output.replaceAll(_compileFlexibleRegExp(pattern), replacement);
          }
        } catch (_) {
          if (onlyFirst) {
            output = output.replaceFirst(pattern, replacement);
          } else {
            output = output.replaceAll(pattern, replacement);
          }
        }
      }
    }
    output = _applyJsPostProcessors(output, rule);
    return output.trim();
  }

  static bool isJsOnlyRule(String rule) {
    final trimmed = rule.trim();
    return trimmed.startsWith('@js:') || trimmed.startsWith('<js>');
  }

  static bool containsJsRule(String? rule) {
    if (rule == null || rule.isEmpty) return false;
    return rule.contains('@js:') ||
        rule.contains('<js>') ||
        rule.contains('</js>') ||
        rule.contains('java.ajax') ||
        rule.contains('java.connect') ||
        rule.contains('java.get') ||
        rule.contains('java.post') ||
        rule.contains('esoTools.') ||
        rule.contains('httpByte(') ||
        rule.contains('http.get(') ||
        rule.contains('http.post(');
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
            .replaceAll('@css:', '')
            .replaceAll('@get:', '')
            .replaceAll(RegExp(r'@[a-zA-Z0-9_\-:]+$'), '')
            .trim(),
      ),
    );
  }

  static bool isXPathRule(String rule) {
    final value = rule.trim();
    return value.startsWith('@xpath:') ||
        value.startsWith('xpath:') ||
        value.startsWith('//') ||
        value.startsWith('./') ||
        value.startsWith('/');
  }

  static String xpathRule(String rule) {
    return rule.replaceFirst('@xpath:', '').replaceFirst('xpath:', '').trim();
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
    var output = rule.replaceAllMapped(RegExp(r'\{\{([^}]+)\}\}'), (match) {
      final key = match.group(1)?.trim() ?? '';
      if (key.isEmpty) return '';
      return _extractSingleJsonValue(json, key);
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

  static bool _containsJsonTemplate(String rule) {
    return rule.contains('{{') ||
        RegExp(r'\{(\$[^{}]+|[A-Za-z_][A-Za-z0-9_\.\[\]\*]*)\}').hasMatch(rule);
  }

  static List<dynamic> _extractNodesByJsonPath(dynamic json, String rule) {
    try {
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
    for (final part in path.split('.')) {
      if (part.isEmpty) continue;
      final next = <dynamic>[];
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

  static String _cleanJsonRule(String rule) {
    return stripPostProcessors(
      rule,
    ).replaceFirst('@json:', '').replaceFirst('json:', '').trim();
  }

  static String sanitizeCssSelector(String selector) {
    var output = selector.trim();
    if (output.isEmpty) return output;

    // Convert :eq(n) to .n
    output = output.replaceAllMapped(RegExp(r':eq\((-?\d+)\)'), (match) {
      final val = int.tryParse(match.group(1) ?? '') ?? 0;
      return '.$val';
    });

    // Convert standalone .number to *.number
    output = output.replaceAllMapped(
      RegExp(r'(?<=^|\s)\.(\d+)\b'),
      (match) => '*.' + match.group(1)!,
    );

    return output;
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
    var cleaned = stripPostProcessors(
      rule,
    ).replaceAll('@css:', '').replaceAll('@get:', '').trim();
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
    final text = selector.trim();
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

    return text
        .split(RegExp(r'\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s != '>')
        .toList();
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
    if (_looksLikeHtmlTagToken(token)) return false;
    return _knownAttrs.contains(token) ||
        RegExp(r'^[a-zA-Z_][a-zA-Z0-9_\-:]*$').hasMatch(token);
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
    final parsed = _parseIndexConfig(rawSelector);
    final selector = _normalizeCssSelector(parsed.baseSelector);
    if (selector.isEmpty || selector == 'this') return [node];

    final nodes = _safeQuerySelectorStep(node, selector);

    if (parsed.isSlice) {
      return _slice(nodes, parsed.sliceStart, parsed.sliceEnd);
    }
    if (parsed.isMulti && parsed.multiIndexes != null) {
      final result = <Element>[];
      for (final idx in parsed.multiIndexes!) {
        final nIdx = _normalizeIndex(idx, nodes.length);
        if (nIdx >= 0 && nIdx < nodes.length) {
          result.add(nodes[nIdx]);
        }
      }
      return result;
    }
    if (parsed.index != null) {
      final idx = _normalizeIndex(parsed.index!, nodes.length);
      return idx >= 0 && idx < nodes.length ? [nodes[idx]] : const [];
    }
    return nodes;
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
    bool isSlice,
    int? index,
    int? sliceStart,
    int? sliceEnd,
    bool isMulti,
    List<int>? multiIndexes,
  })
  _parseIndexConfig(String selector) {
    // Slice: base!start:end
    final slice = RegExp(r'^(.+)!(-?\d*)?(?::(-?\d*)?)?$').firstMatch(selector);
    if (slice != null) {
      return (
        baseSelector: slice.group(1)?.trim() ?? selector,
        isSlice: true,
        index: null,
        sliceStart: int.tryParse(slice.group(2) ?? ''),
        sliceEnd: int.tryParse(slice.group(3) ?? ''),
        isMulti: false,
        multiIndexes: null,
      );
    }

    // Multi: base.i1,i2,i3
    final multi = RegExp(r'^(.+)\.((?:\d+)(?:,\d+)*)$').firstMatch(selector);
    if (multi != null) {
      return (
        baseSelector: multi.group(1)?.trim() ?? selector,
        isSlice: false,
        index: null,
        sliceStart: null,
        sliceEnd: null,
        isMulti: true,
        multiIndexes: multi.group(2)!.split(',').map(int.parse).toList(),
      );
    }

    // Index: base.i
    final index = RegExp(r'^(.+)\.(-?\d+)$').firstMatch(selector);
    if (index != null) {
      final base = index.group(1)?.trim() ?? selector;
      final number = int.tryParse(index.group(2) ?? '');
      if (number != null) {
        return (
          baseSelector: base,
          isSlice: false,
          index: number,
          sliceStart: null,
          sliceEnd: null,
          isMulti: false,
          multiIndexes: null,
        );
      }
    }
    return (
      baseSelector: selector,
      isSlice: false,
      index: null,
      sliceStart: null,
      sliceEnd: null,
      isMulti: false,
      multiIndexes: null,
    );
  }

  static List<Element> _slice(List<Element> nodes, int? start, int? end) {
    if (nodes.isEmpty) return const [];
    final from = _normalizeIndex(
      start ?? 0,
      nodes.length,
    ).clamp(0, nodes.length);
    var to = end == null ? nodes.length : _normalizeIndex(end, nodes.length);
    to = to.clamp(0, nodes.length);
    if (to < from) return const [];
    return nodes.sublist(from, to);
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
        output = '.' + classes.join('.');
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
    } else {
      for (final child in node.nodes) {
        _collectTextNodes(child, result);
      }
    }
  }

  static String _htmlValue(Element target, String attrName) {
    switch (attrName) {
      case 'text':
        return target.text.trim();
      case 'textNodes':
        final list = <String>[];
        _collectTextNodes(target, list);
        return list.join('\n');
      case 'ownText':
        return target.nodes
            .whereType<Text>()
            .map((node) => node.text)
            .join('')
            .trim();
      case 'html':
        return target.innerHtml.trim();
      case 'outerHtml':
        return target.outerHtml.trim();
      default:
        final direct = target.attributes[attrName];
        if (direct != null && direct.isNotEmpty) return direct;

        // Fallback: search descendants
        if (attrName == 'href') {
          final childHref = target.querySelector('a')?.attributes['href'];
          if (childHref != null && childHref.isNotEmpty) return childHref;
        }
        if (const [
          'src',
          'data-src',
          'data-original',
          'alt',
        ].contains(attrName)) {
          final childSrc = target.querySelector('img')?.attributes[attrName];
          if (childSrc != null && childSrc.isNotEmpty) return childSrc;
        }
        for (final desc in target.querySelectorAll('*')) {
          final val = desc.attributes[attrName];
          if (val != null && val.isNotEmpty) return val;
        }
        return '';
    }
  }

  static String _applyJsPostProcessors(String value, String rule) {
    if (!rule.contains('@js:') && !rule.contains('<js>')) return value;
    var output = value;
    final simpleOutput = _evaluateSimpleJsPostProcessor(output, rule);
    if (simpleOutput.isNotEmpty) output = simpleOutput;

    final aesMatch = RegExp(
      r'''java\.aesBase64DecodeToString\(\s*result\s*,\s*["']([^"']+)["']\s*,\s*["']([^"']+)["']\s*,\s*["']([^"']*)["']''',
    ).firstMatch(rule);
    if (aesMatch != null) {
      final key = aesMatch.group(1) ?? '';
      final iv = aesMatch.group(3) ?? '';
      final decoded = _aesBase64Decode(output, key, iv);
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
      r'''^result\.replace\(\s*/(.+?)/([gimsuy]*)\s*,\s*(["'])(.*?)\3\s*\)$''',
      dotAll: true,
    ).firstMatch(expression);
    if (regexMatch != null) {
      try {
        final pattern = regexMatch.group(1) ?? '';
        final flags = regexMatch.group(2) ?? '';
        final replacement = _decodeJsEscaped(regexMatch.group(4) ?? '');
        final regex = RegExp(
          pattern,
          caseSensitive: !flags.contains('i'),
          multiLine: flags.contains('m'),
          dotAll: flags.contains('s'),
        );
        return flags.contains('g')
            ? result.replaceAll(regex, replacement)
            : result.replaceFirst(regex, replacement);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static String _extractJsPostProcessorScript(String rule) {
    if (rule.contains('@js:')) {
      return rule.split('@js:')[1].split('##').first.trim();
    }
    if (rule.contains('<js>')) {
      return rule.split('<js>')[1].split('</js>').first.trim();
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

  static String _aesBase64Decode(String value, String key, String iv) {
    try {
      final keyBytes = Uint8List.fromList(utf8.encode(key));
      if (keyBytes.length != 16 &&
          keyBytes.length != 24 &&
          keyBytes.length != 32) {
        return '';
      }
      var ivBytes = Uint8List.fromList(utf8.encode(iv));
      if (ivBytes.length != 16) {
        ivBytes = Uint8List(16);
      }

      final cipher = PaddedBlockCipherImpl(
        PKCS7Padding(),
        CBCBlockCipher(AESEngine()),
      );
      cipher.init(
        false,
        PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
          ParametersWithIV<KeyParameter>(KeyParameter(keyBytes), ivBytes),
          null,
        ),
      );
      final input = base64Decode(value.trim());
      final output = cipher.process(Uint8List.fromList(input));
      return utf8.decode(output, allowMalformed: true).trim();
    } catch (_) {
      return '';
    }
  }

  static bool _isPureJsonPath(String rule) {
    final trimmed = stripPostProcessors(rule).trim();
    return (trimmed.startsWith(r'$') ||
            trimmed.startsWith('@json:') ||
            trimmed.startsWith('json:')) &&
        !trimmed.contains(' ') &&
        !trimmed.contains('/') &&
        !trimmed.contains('{') &&
        !trimmed.contains('}');
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
