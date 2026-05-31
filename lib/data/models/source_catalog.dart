import 'package:isar/isar.dart';

part 'source_catalog.g.dart';

@collection
class SourceCatalog {
  Id id = Isar.autoIncrement;

  @Index(type: IndexType.value)
  late String name;

  @Index(unique: true, replace: true)
  late String url;

  String? importUrl;
  String? icon;
  String? group;
  String? comment;
  bool enabled = true;
  int importedCount = 0;
  String? lastStatus;
  DateTime? lastImportedAt;

  SourceCatalog();

  factory SourceCatalog.fromJson(
    Map<String, dynamic> json, {
    String? originalUrl,
  }) {
    return SourceCatalog()
      ..name =
          json['sourceName']?.toString() ?? json['name']?.toString() ?? '未知书源仓库'
      ..url =
          json['sourceUrl']?.toString() ??
          json['url']?.toString() ??
          originalUrl ??
          ''
      ..importUrl = json['importUrl']?.toString()
      ..icon = json['sourceIcon']?.toString() ?? json['icon']?.toString()
      ..group = json['sourceGroup']?.toString() ?? json['group']?.toString()
      ..comment =
          json['sourceComment']?.toString() ?? json['comment']?.toString()
      ..enabled = json['enabled'] is bool ? json['enabled'] as bool : true;
  }
}
