import 'package:html/dom.dart';
import 'package:json_path/json_path.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';

class LegadoRuleEvaluator {
  static String extractJsonValue(dynamic json, String rule) {
    if (rule.isEmpty) return '';
    if (json is Map && rule.contains('{{')) {
      return applyPostProcessors(_interpolateJsonTemplate(json, rule), rule);
    }
    try {
      final alternatives = rule.split(RegExp(r'\|\||&&'));
      for (final part in alternatives) {
        final cleaned = stripPostProcessors(part);
        if (cleaned.isEmpty) continue;
        final value = applyPostProcessors(
          _extractSingleJsonValue(json, cleaned),
          part,
        );
        if (value.isNotEmpty) return value;
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  static List<dynamic> extractJsonNodes(dynamic json, String rule) {
    if (rule.isEmpty) return const [];
    final nodes = <dynamic>[];
    try {
      final alternatives = rule.split(RegExp(r'\|\||&&'));
      for (final part in alternatives) {
        final cleaned = stripPostProcessors(part);
        if (cleaned.isEmpty) continue;
        nodes.addAll(_extractNodesByJsonPath(json, cleaned));
        if (nodes.isEmpty) nodes.addAll(_extractNodesManually(json, cleaned));
        if (nodes.isNotEmpty) return nodes;
      }
    } catch (_) {
      return const [];
    }
    return nodes;
  }

  static String extractHtmlValue(Element node, String rule) {
    if (rule.isEmpty) return '';
    final alternatives = rule.split(RegExp(r'\|\||&&'));
    for (final part in alternatives) {
      final value = _extractSingleHtmlValue(node, part);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static String _extractSingleHtmlValue(Element node, String rule) {
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

  static String applyPostProcessors(String value, String rule) {
    var output = value;
    if (rule.contains('##')) {
      final parts = rule.split('##');
      final processors = parts.skip(1).toList();
      for (var index = 0; index < processors.length; index += 2) {
        final pattern = processors[index];
        if (pattern.isEmpty) continue;
        final replacement = index + 1 < processors.length
            ? processors[index + 1]
            : '';
        try {
          output = output.replaceAll(RegExp(pattern), replacement);
        } catch (_) {
          output = output.replaceAll(pattern, replacement);
        }
      }
    }
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
        rule.contains('java.get') ||
        rule.contains('java.post');
  }

  static bool looksLikeJsonData(dynamic data, String? rule) {
    if (rule == null) return true;
    if (data is Map || data is List) return true;
    final text = data.toString().trimLeft();
    return text.startsWith('{') || text.startsWith('[');
  }

  static String cssRule(String rule) {
    return _normalizeCssSelector(
      rule
          .replaceAll('@css:', '')
          .replaceAll('@get:', '')
          .replaceAll(RegExp(r'@[a-zA-Z0-9_\-:]+$'), '')
          .trim(),
    );
  }

  static bool isXPathRule(String rule) {
    final value = rule.trim();
    return value.startsWith('xpath:') ||
        value.startsWith('//') ||
        value.startsWith('./') ||
        value.startsWith('/');
  }

  static String xpathRule(String rule) {
    return rule.replaceFirst('xpath:', '').trim();
  }

  static String _extractSingleJsonValue(dynamic json, String rule) {
    try {
      final nodes = _extractNodesByJsonPath(json, rule);
      if (nodes.isNotEmpty) return nodes.first?.toString() ?? '';
      final manual = _extractNodesManually(json, rule);
      if (manual.isNotEmpty) return manual.first?.toString() ?? '';
    } catch (_) {
      final manual = _extractNodesManually(json, rule);
      if (manual.isNotEmpty) return manual.first?.toString() ?? '';
    }
    return '';
  }

  static String _interpolateJsonTemplate(
    Map<dynamic, dynamic> json,
    String rule,
  ) {
    return rule.replaceAllMapped(RegExp(r'\{\{([^}]+)\}\}'), (match) {
      final key = match.group(1)?.trim() ?? '';
      if (key.isEmpty) return '';
      return _extractSingleJsonValue(json, key);
    });
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
    final cleaned = _cleanJsonRule(rule)
        .replaceAll(RegExp(r'^\$\.?'), '')
        .replaceAll('[*]', '')
        .replaceAll('.*', '')
        .trim();
    if (cleaned.isEmpty) return [json];

    var current = <dynamic>[json];
    for (final part in cleaned.split('.')) {
      if (part.isEmpty) continue;
      final next = <dynamic>[];
      final match = RegExp(r'^([^\[]+)(?:\[(\d+)\])?$').firstMatch(part);
      final key = match?.group(1) ?? part;
      final index = int.tryParse(match?.group(2) ?? '');
      for (final value in current) {
        dynamic child;
        if (value is Map) {
          child = value[key] ?? value[key.toString()];
        } else if (value is List && int.tryParse(key) != null) {
          final listIndex = int.parse(key);
          if (listIndex >= 0 && listIndex < value.length) {
            child = value[listIndex];
          }
        }
        if (child == null) continue;
        if (index != null) {
          if (child is List && index >= 0 && index < child.length) {
            next.add(child[index]);
          }
        } else if (child is List) {
          next.addAll(child);
        } else {
          next.add(child);
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

  static _HtmlRule _parseHtmlRule(String rule, {bool attrAllowed = true}) {
    var cleaned = stripPostProcessors(
      rule,
    ).replaceAll('@css:', '').replaceAll('@get:', '').trim();
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
    }
    return _HtmlRule(parts, attr);
  }

  static bool _isAttributeToken(String token) {
    if (token.contains(' ') || token.startsWith('.') || token.startsWith('#')) {
      return false;
    }
    const knownAttrs = {
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
    return knownAttrs.contains(token) ||
        RegExp(r'^[a-zA-Z_][a-zA-Z0-9_\-:]*$').hasMatch(token);
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
    final parsed = _parseSelectorIndex(rawSelector);
    final selector = _normalizeCssSelector(parsed.selector);
    if (selector.isEmpty || selector == 'this') return [node];
    final nodes = node.querySelectorAll(selector);
    if (parsed.sliceStart != null || parsed.sliceEnd != null) {
      return _slice(nodes, parsed.sliceStart, parsed.sliceEnd);
    }
    if (parsed.index != null) {
      final index = _normalizeIndex(parsed.index!, nodes.length);
      return index >= 0 && index < nodes.length ? [nodes[index]] : const [];
    }
    return nodes;
  }

  static ({String selector, int? index, int? sliceStart, int? sliceEnd})
  _parseSelectorIndex(String selector) {
    final slice = RegExp(r'^(.+)!(-?\d*)?(?::(-?\d*)?)?$').firstMatch(selector);
    if (slice != null) {
      return (
        selector: slice.group(1)?.trim() ?? selector,
        index: null,
        sliceStart: int.tryParse(slice.group(2) ?? ''),
        sliceEnd: int.tryParse(slice.group(3) ?? ''),
      );
    }

    final index = RegExp(r'^(.+)\.(-?\d+)$').firstMatch(selector);
    if (index != null) {
      final base = index.group(1)?.trim() ?? selector;
      final number = int.tryParse(index.group(2) ?? '');
      if (number != null && !_looksLikeClassSelector(base)) {
        return (
          selector: base,
          index: number,
          sliceStart: null,
          sliceEnd: null,
        );
      }
    }
    return (selector: selector, index: null, sliceStart: null, sliceEnd: null);
  }

  static bool _looksLikeClassSelector(String selector) {
    final trimmed = selector.trim();
    return trimmed.startsWith('.') || trimmed.contains(RegExp(r'\.[A-Za-z_-]'));
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
    output = output.replaceAllMapped(
      RegExp(r'\bid\.([A-Za-z0-9_\-]+)'),
      (match) => '#${match.group(1)}',
    );
    output = output.replaceAllMapped(
      RegExp(r'\bclass\.([A-Za-z0-9_\-]+)'),
      (match) => '.${match.group(1)}',
    );
    return output;
  }

  static String _htmlValue(Element target, String attrName) {
    return switch (attrName) {
      'text' => target.text.trim(),
      'textNodes' =>
        target.nodes
            .whereType<Text>()
            .map((node) => node.text.trim())
            .where((text) => text.isNotEmpty)
            .join('\n'),
      'html' => target.innerHtml.trim(),
      'outerHtml' => target.outerHtml.trim(),
      _ => target.attributes[attrName] ?? '',
    };
  }
}

class _HtmlRule {
  final List<String> selectors;
  final String attr;

  const _HtmlRule(this.selectors, this.attr);
}
