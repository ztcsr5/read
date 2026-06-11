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
      'variableComment',
      'respondTime',
    ]) {
      if (json.containsKey(key) && json[key] != null) {
        customConfig[key] = json[key];
      }
    }

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
      ..searchUrl = _firstString(json, const ['searchUrl', 'searchURL'])
      ..exploreUrl = _firstString(json, const ['exploreUrl', 'exploreURL'])
      ..enabled = json['enabled'] ?? true
      ..weight = json['weight'] ?? 0
      ..ruleSearch =
          _firstValue(json, const ['ruleSearch', 'rulesSearch']) != null
          ? _jsonEncode(_firstValue(json, const ['ruleSearch', 'rulesSearch']))
          : null
      ..ruleBookInfo =
          _firstValue(json, const [
                'ruleBookInfo',
                'rulesBookInfo',
                'ruleBook',
              ]) !=
              null
          ? _jsonEncode(
              _firstValue(json, const [
                'ruleBookInfo',
                'rulesBookInfo',
                'ruleBook',
              ]),
            )
          : null
      ..ruleToc = _firstValue(json, const ['ruleToc', 'rulesToc']) != null
          ? _jsonEncode(_firstValue(json, const ['ruleToc', 'rulesToc']))
          : null
      ..ruleContent =
          _firstValue(json, const [
                'ruleContent',
                'rulesContent',
                'ruleBookContent',
              ]) !=
              null
          ? _jsonEncode(
              _firstValue(json, const [
                'ruleContent',
                'rulesContent',
                'ruleBookContent',
              ]),
            )
          : null
      ..ruleExplore =
          _firstValue(json, const ['ruleExplore', 'rulesExplore']) != null
          ? _jsonEncode(
              _firstValue(json, const ['ruleExplore', 'rulesExplore']),
            )
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
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _jsonEncode(dynamic data) {
  if (data == null) return '';
  if (data is String) return data;
  return jsonEncode(data);
}
