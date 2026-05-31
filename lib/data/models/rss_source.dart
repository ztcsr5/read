import 'dart:convert';
import 'package:isar/isar.dart';

part 'rss_source.g.dart';

@collection
class RssSource {
  Id id = Isar.autoIncrement;

  /// 订阅源名称
  @Index(type: IndexType.value)
  late String sourceName;

  /// 订阅源 URL
  @Index(unique: true, replace: true)
  late String sourceUrl;

  /// 订阅源图标
  String? sourceIcon;

  /// 分组
  String? sourceGroup;

  /// 简介/评论
  String? sourceComment;

  /// 是否启用
  bool enabled = true;

  /// 是否启用 Cookie 机制
  bool enabledCookieJar = false;

  /// 排序/分类 URL
  String? sortUrl;

  // --- 规则部分 ---
  String? ruleArticles;
  String? ruleNextPage;
  String? ruleTitle;
  String? rulePubDate;
  String? ruleDescription;
  String? ruleImage;
  String? ruleLink;
  String? ruleContent;
  String? style;

  /// 其他自定义配置
  String? customConfig;

  RssSource();

  /// 从 Legado JSON 解析
  factory RssSource.fromJson(Map<String, dynamic> json) {
    return RssSource()
      ..sourceName = json['sourceName'] ?? '未知订阅源'
      ..sourceUrl = json['sourceUrl'] ?? ''
      ..sourceIcon = json['sourceIcon']
      ..sourceGroup = json['sourceGroup']
      ..sourceComment = json['sourceComment']
      ..enabled = json['enabled'] ?? true
      ..enabledCookieJar = json['enabledCookieJar'] ?? false
      ..sortUrl = json['sortUrl']
      ..ruleArticles = json['ruleArticles']
      ..ruleNextPage = json['ruleNextPage']
      ..ruleTitle = json['ruleTitle']
      ..rulePubDate = json['rulePubDate']
      ..ruleDescription = json['ruleDescription']
      ..ruleImage = json['ruleImage']
      ..ruleLink = json['ruleLink']
      ..ruleContent = json['ruleContent']
      ..style = json['style']
      ..customConfig = json['customConfig'];
  }
}
