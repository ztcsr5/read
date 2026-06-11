import 'dart:convert';
import 'package:isar/isar.dart';

part 'book_source.g.dart';

@collection
class BookSource {
  Id id = Isar.autoIncrement;

  /// 书源名称
  @Index(type: IndexType.value)
  late String bookSourceName;

  /// 书源基础 URL
  @Index(unique: true, replace: true)
  late String bookSourceUrl;

  /// 分组
  String? bookSourceGroup;

  /// 书源类型 (0: 文本, 1: 音频, 2: 图片)
  int bookSourceType = 0;

  /// 搜索 URL
  String? searchUrl;

  /// 是否启用
  bool enabled = true;

  /// 权重（排序用）
  int weight = 0;

  /// 探索（发现）URL
  String? exploreUrl;

  // --- 规则部分 (JSON 字符串形式保存，以防字段过多) ---

  /// 搜索规则 JSON
  String? ruleSearch;

  /// 书籍详情规则 JSON
  String? ruleBookInfo;

  /// 目录规则 JSON
  String? ruleToc;

  /// 正文规则 JSON
  String? ruleContent;

  /// 发现规则 JSON
  String? ruleExplore;

  /// 其他自定义配置（如 Header 等）
  String? customConfig;

  BookSource();

  /// 从 Legado JSON 解析
  factory BookSource.fromJson(Map<String, dynamic> json) {
    final customConfig = <String, dynamic>{};
    final rawCustomConfig = json['customConfig'];
    if (rawCustomConfig is Map) {
      customConfig.addAll(
        rawCustomConfig.map((key, value) => MapEntry(key.toString(), value)),
      );
    } else if (rawCustomConfig is String && rawCustomConfig.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawCustomConfig);
        if (decoded is Map) {
          customConfig.addAll(
            decoded.map((key, value) => MapEntry(key.toString(), value)),
          );
        } else {
          customConfig['raw'] = rawCustomConfig;
        }
      } catch (_) {
        customConfig['raw'] = rawCustomConfig;
      }
    }
    for (final key in [
      'header',
      'headers',
      'cookie',
      'method',
      'type',
      'body',
      'charset',
      'loginUrl',
      'loginUi',
      'jsLib',
      'js',
      'webJs',
      'bodyJs',
      'bookUrlPattern',
      'enabledCookieJar',
      'enabledExplore',
      'loadWithBaseUrl',
      'singleUrl',
      'webView',
      'webViewDelayTime',
      'bookSourceComment',
      'bookSourceHeader',
      'loginCheckJs',
      'coverDecodeJs',
      'variableComment',
      'respondTime',
    ]) {
      if (json.containsKey(key) && json[key] != null) {
        customConfig[key] = json[key];
      }
    }
    if (!customConfig.containsKey('bookUrlPattern') &&
        json['ruleBookUrlPattern'] != null) {
      customConfig['bookUrlPattern'] = json['ruleBookUrlPattern'];
    }
    if (!customConfig.containsKey('header')) {
      final userAgent = _firstString(json, const ['httpUserAgent']);
      if (userAgent != null) {
        customConfig['header'] = jsonEncode({'User-Agent': userAgent});
      }
    }

    final searchUrl =
        _firstString(json, const ['searchUrl', 'searchURL']) ??
        _toNewLegacyUrl(_firstString(json, const ['ruleSearchUrl']));
    final exploreUrl =
        _firstString(json, const ['exploreUrl', 'exploreURL']) ??
        _toNewLegacyUrls(_firstString(json, const ['ruleFindUrl']));
    final ruleSearchValue =
        _firstValue(json, const ['ruleSearch', 'rulesSearch']) ??
        _legacyRuleMap(json, const {
          'bookList': 'ruleSearchList',
          'name': 'ruleSearchName',
          'author': 'ruleSearchAuthor',
          'intro': 'ruleSearchIntroduce',
          'kind': 'ruleSearchKind',
          'bookUrl': 'ruleSearchNoteUrl',
          'coverUrl': 'ruleSearchCoverUrl',
          'lastChapter': 'ruleSearchLastChapter',
        });
    final ruleBookInfoValue =
        _firstValue(json, const [
          'ruleBookInfo',
          'rulesBookInfo',
          'ruleBook',
        ]) ??
        _legacyRuleMap(json, const {
          'init': 'ruleBookInfoInit',
          'name': 'ruleBookName',
          'author': 'ruleBookAuthor',
          'intro': 'ruleIntroduce',
          'kind': 'ruleBookKind',
          'coverUrl': 'ruleCoverUrl',
          'lastChapter': 'ruleBookLastChapter',
          'tocUrl': 'ruleChapterUrl',
        });
    final ruleTocValue =
        _firstValue(json, const ['ruleToc', 'rulesToc']) ??
        _legacyRuleMap(json, const {
          'chapterList': 'ruleChapterList',
          'chapterName': 'ruleChapterName',
          'chapterUrl': 'ruleContentUrl',
          'nextTocUrl': 'ruleChapterUrlNext',
        });
    final modernRuleContent = _firstValue(json, const [
      'ruleContent',
      'rulesContent',
    ]);
    final legacyRuleBookContent = _firstValue(json, const ['ruleBookContent']);
    final ruleContentValue =
        modernRuleContent ??
        (legacyRuleBookContent is Map
            ? legacyRuleBookContent
            : _legacyContentRuleMap(json));
    final ruleExploreValue =
        _firstValue(json, const ['ruleExplore', 'rulesExplore']) ??
        _legacyRuleMap(json, const {
          'bookList': 'ruleFindList',
          'name': 'ruleFindName',
          'author': 'ruleFindAuthor',
          'intro': 'ruleFindIntroduce',
          'kind': 'ruleFindKind',
          'bookUrl': 'ruleFindNoteUrl',
          'coverUrl': 'ruleFindCoverUrl',
          'lastChapter': 'ruleFindLastChapter',
        });

    return BookSource()
      ..bookSourceName =
          _firstString(json, const ['bookSourceName', 'sourceName', 'name']) ??
          '未知书源'
      ..bookSourceUrl =
          _firstString(json, const ['bookSourceUrl', 'sourceUrl', 'url']) ?? ''
      ..bookSourceGroup = _firstString(json, const [
        'bookSourceGroup',
        'sourceGroup',
        'group',
      ])
      ..bookSourceType = _firstInt(json, const ['bookSourceType', 'sourceType'])
      ..searchUrl = searchUrl
      ..exploreUrl = exploreUrl
      ..enabled = _firstBool(json, const [
        'enabled',
        'enable',
      ], defaultValue: true)
      ..weight = _firstInt(json, const [
        'weight',
        'serialNumber',
        'customOrder',
      ])
      ..ruleSearch = ruleSearchValue != null
          ? _jsonEncode(ruleSearchValue)
          : null
      ..ruleBookInfo = ruleBookInfoValue != null
          ? _jsonEncode(ruleBookInfoValue)
          : null
      ..ruleToc = ruleTocValue != null ? _jsonEncode(ruleTocValue) : null
      ..ruleContent = ruleContentValue != null
          ? _jsonEncode(ruleContentValue)
          : null
      ..ruleExplore = ruleExploreValue != null
          ? _jsonEncode(ruleExploreValue)
          : null
      ..customConfig = customConfig.isEmpty ? null : jsonEncode(customConfig);
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'bookSourceName': bookSourceName,
      'bookSourceUrl': bookSourceUrl,
      'bookSourceType': bookSourceType,
      'enabled': enabled,
      'weight': weight,
    };
    void putString(String key, String? value) {
      if (value != null && value.trim().isNotEmpty) map[key] = value;
    }

    void putJsonField(String key, String? value) {
      if (value == null || value.trim().isEmpty) return;
      try {
        map[key] = jsonDecode(value);
      } catch (_) {
        map[key] = value;
      }
    }

    putString('bookSourceGroup', bookSourceGroup);
    putString('searchUrl', searchUrl);
    putString('exploreUrl', exploreUrl);
    putJsonField('ruleSearch', ruleSearch);
    putJsonField('ruleBookInfo', ruleBookInfo);
    putJsonField('ruleToc', ruleToc);
    putJsonField('ruleContent', ruleContent);
    putJsonField('ruleExplore', ruleExplore);
    putJsonField('customConfig', customConfig);
    return map;
  }

  BookSource duplicate() {
    return BookSource()
      ..id = id
      ..bookSourceName = bookSourceName
      ..bookSourceUrl = bookSourceUrl
      ..bookSourceGroup = bookSourceGroup
      ..bookSourceType = bookSourceType
      ..searchUrl = searchUrl
      ..enabled = enabled
      ..weight = weight
      ..exploreUrl = exploreUrl
      ..ruleSearch = ruleSearch
      ..ruleBookInfo = ruleBookInfo
      ..ruleToc = ruleToc
      ..ruleContent = ruleContent
      ..ruleExplore = ruleExplore
      ..customConfig = customConfig;
  }
}

dynamic _firstValue(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    if (json.containsKey(key) && json[key] != null) return json[key];
  }
  return null;
}

String? _firstString(Map<String, dynamic> json, List<String> keys) {
  final value = _firstValue(json, keys);
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int _firstInt(Map<String, dynamic> json, List<String> keys) {
  final value = _firstValue(json, keys);
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool _firstBool(
  Map<String, dynamic> json,
  List<String> keys, {
  required bool defaultValue,
}) {
  final value = _firstValue(json, keys);
  if (value == null) return defaultValue;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value.toString().trim().toLowerCase();
  if (text.isEmpty) return defaultValue;
  if (const {
    'true',
    '1',
    'yes',
    'y',
    'on',
    'enable',
    'enabled',
  }.contains(text)) {
    return true;
  }
  if (const {
    'false',
    '0',
    'no',
    'n',
    'off',
    'disable',
    'disabled',
  }.contains(text)) {
    return false;
  }
  return defaultValue;
}

Map<String, dynamic>? _legacyRuleMap(
  Map<String, dynamic> json,
  Map<String, String> fields,
) {
  final map = <String, dynamic>{};
  fields.forEach((newKey, oldKey) {
    final value = _toNewLegacyRule(_firstString(json, [oldKey]));
    if (value != null && value.trim().isNotEmpty) {
      map[newKey] = value;
    }
  });
  return map.isEmpty ? null : map;
}

Map<String, dynamic>? _legacyContentRuleMap(Map<String, dynamic> json) {
  var content = _toNewLegacyRule(_firstString(json, const ['ruleBookContent']));
  if (content != null &&
      content.startsWith(r'$') &&
      !content.startsWith(r'$.')) {
    content = content.substring(1);
  }
  final map = <String, dynamic>{};
  if (content != null && content.trim().isNotEmpty) {
    map['content'] = content;
  }
  final replaceRegex = _toNewLegacyRule(
    _firstString(json, const ['ruleBookContentReplace']),
  );
  if (replaceRegex != null && replaceRegex.trim().isNotEmpty) {
    map['replaceRegex'] = replaceRegex;
  }
  final nextContentUrl = _toNewLegacyRule(
    _firstString(json, const ['ruleContentUrlNext']),
  );
  if (nextContentUrl != null && nextContentUrl.trim().isNotEmpty) {
    map['nextContentUrl'] = nextContentUrl;
  }
  return map.isEmpty ? null : map;
}

String? _toNewLegacyRule(String? oldRule) {
  if (oldRule == null || oldRule.trim().isEmpty) return null;
  var newRule = oldRule.trim();
  var reverse = false;
  var allInOne = false;
  if (newRule.startsWith('-')) {
    reverse = true;
    newRule = newRule.substring(1);
  }
  if (newRule.startsWith('+')) {
    allInOne = true;
    newRule = newRule.substring(1);
  }
  final lower = newRule.toLowerCase();
  final shouldConvertSeparators =
      !lower.startsWith('@css:') &&
      !lower.startsWith('@xpath:') &&
      !newRule.startsWith('//') &&
      !newRule.startsWith('##') &&
      !newRule.startsWith(':') &&
      !lower.contains('@js:') &&
      !lower.contains('<js>');
  if (shouldConvertSeparators) {
    if (newRule.contains('#') && !newRule.contains('##')) {
      newRule = newRule.replaceAll('#', '##');
    }
    if (newRule.contains('|') && !newRule.contains('||')) {
      if (newRule.contains('##')) {
        final parts = newRule.split('##');
        final first = parts.first.replaceAll('|', '||');
        newRule = [first, ...parts.skip(1)].join('##');
      } else {
        newRule = newRule.replaceAll('|', '||');
      }
    }
    if (newRule.contains('&') &&
        !newRule.contains('&&') &&
        !newRule.contains('http') &&
        !newRule.startsWith('/')) {
      newRule = newRule.replaceAll('&', '&&');
    }
  }
  if (allInOne) newRule = '+$newRule';
  if (reverse) newRule = '-$newRule';
  return newRule;
}

String? _toNewLegacyUrls(String? oldUrls) {
  if (oldUrls == null || oldUrls.trim().isEmpty) return null;
  final text = oldUrls.trim();
  if (text.startsWith('@js:') || text.startsWith('<js>')) return text;
  if (!text.contains('\n') && !text.contains('&&')) {
    return _toNewLegacyUrl(text);
  }
  final urls = text
      .split(RegExp(r'(?:&&|\r?\n)+'))
      .map((url) => _toNewLegacyUrl(url)?.replaceAll(RegExp(r'\n\s*'), ''))
      .whereType<String>()
      .where((url) => url.trim().isNotEmpty)
      .toList();
  return urls.isEmpty ? null : urls.join('\n');
}

String? _toNewLegacyUrl(String? oldUrl) {
  if (oldUrl == null || oldUrl.trim().isEmpty) return null;
  var url = oldUrl.trim();
  if (url.toLowerCase().startsWith('<js>')) {
    return url
        .replaceAll('=searchKey', '={{key}}')
        .replaceAll('=searchPage', '={{page}}');
  }

  final config = <String, dynamic>{};
  final headerMatch = RegExp(
    r'@Header:\{.+?\}',
    caseSensitive: false,
  ).firstMatch(url);
  if (headerMatch != null) {
    final header = headerMatch.group(0) ?? '';
    url = url.replaceFirst(header, '');
    config['headers'] = header.substring(8);
  }

  final charsetParts = url.split('|');
  url = charsetParts.first;
  if (charsetParts.length > 1) {
    final charsetText = charsetParts[1];
    final separator = charsetText.indexOf('=');
    if (separator >= 0 && separator < charsetText.length - 1) {
      config['charset'] = charsetText.substring(separator + 1);
    }
  }

  final scripts = <String>[];
  url = url.replaceAllMapped(RegExp(r'\{\{.+?\}\}'), (match) {
    scripts.add(match.group(0) ?? '');
    return r'$'
        '${scripts.length - 1}';
  });
  url = url.replaceAll('{', '<').replaceAll('}', '>');
  url = url
      .replaceAll('searchKey', '{{key}}')
      .replaceAllMapped(RegExp(r'<searchPage([-+]\d+)>'), (match) {
        return '{{page${match.group(1)}}}';
      })
      .replaceAllMapped(RegExp(r'searchPage([-+]\d+)'), (match) {
        return '{{page${match.group(1)}}}';
      })
      .replaceAll('searchPage', '{{page}}');
  for (var index = 0; index < scripts.length; index++) {
    url = url.replaceAll(
      '\$$index',
      scripts[index]
          .replaceAll('searchKey', 'key')
          .replaceAll('searchPage', 'page'),
    );
  }

  final bodyParts = url.split('@');
  url = bodyParts.first;
  if (bodyParts.length > 1) {
    config['method'] = 'POST';
    config['body'] = bodyParts.sublist(1).join('@');
  }
  return config.isEmpty ? url : '$url,${jsonEncode(config)}';
}

String _jsonEncode(dynamic data) {
  if (data == null) return '';
  if (data is String) return data;
  return jsonEncode(data);
}
