/// 阅读App - 书签/高亮/笔记 数据模型
///
/// 使用 Isar 数据库注解进行本地持久化存储。
/// 支持三种类型：普通书签、文本高亮、读书笔记。
library;

import 'package:isar/isar.dart';

part 'bookmark.g.dart';

/// 书签类型枚举
enum BookmarkType {
  /// 普通书签（标记位置）
  bookmark,

  /// 文本高亮（选中文本并高亮显示）
  highlight,

  /// 读书笔记（附带用户笔记内容）
  note,
}

/// 高亮颜色枚举
///
/// 提供常用的高亮颜色选项。
enum HighlightColor {
  /// 黄色高亮（默认）
  yellow,

  /// 绿色高亮
  green,

  /// 蓝色高亮
  blue,

  /// 粉色高亮
  pink,

  /// 紫色高亮
  purple,

  /// 橙色高亮
  orange,
}

/// 书签/高亮/笔记 数据模型
///
/// 统一存储用户在阅读过程中创建的书签、高亮和笔记。
/// 每条记录关联到具体的书籍、章节和文本位置。
@collection
class Bookmark {
  /// Isar 自增主键
  Id id = Isar.autoIncrement;

  /// 所属书籍的ID
  @Index()
  int bookId;

  /// 所在章节的索引
  int chapterIndex;

  /// 在章节内容中的字符位置偏移量
  int position;

  /// 选中文本的结束位置（仅高亮和笔记有效）
  int? endPosition;

  /// 书签类型：书签/高亮/笔记
  @Enumerated(EnumType.name)
  BookmarkType type;

  /// 高亮颜色（仅高亮类型有效）
  @Enumerated(EnumType.name)
  HighlightColor color;

  /// 用户笔记内容（仅笔记类型有效）
  String? note;

  /// 被选中/标记的文本内容
  String? selectedText;

  /// 章节标题（冗余存储，便于列表展示）
  String? chapterTitle;

  /// 创建时间
  @Index()
  DateTime createdAt;

  /// 最后修改时间
  DateTime? updatedAt;

  /// 构造函数
  Bookmark({
    required this.bookId,
    required this.chapterIndex,
    required this.position,
    this.endPosition,
    this.type = BookmarkType.bookmark,
    this.color = HighlightColor.yellow,
    this.note,
    this.selectedText,
    this.chapterTitle,
    required this.createdAt,
    this.updatedAt,
  });

  /// 从 JSON Map 创建 Bookmark 实例
  factory Bookmark.fromJson(Map<String, dynamic> json) {
    return Bookmark(
      bookId: json['bookId'] as int? ?? 0,
      chapterIndex: json['chapterIndex'] as int? ?? 0,
      position: json['position'] as int? ?? 0,
      endPosition: json['endPosition'] as int?,
      type: _parseBookmarkType(json['type'] as String?),
      color: _parseHighlightColor(json['color'] as String?),
      note: json['note'] as String?,
      selectedText: json['selectedText'] as String?,
      chapterTitle: json['chapterTitle'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
    )..id = json['id'] as int? ?? Isar.autoIncrement;
  }

  /// 将 Bookmark 序列化为 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bookId': bookId,
      'chapterIndex': chapterIndex,
      'position': position,
      'endPosition': endPosition,
      'type': type.name,
      'color': color.name,
      'note': note,
      'selectedText': selectedText,
      'chapterTitle': chapterTitle,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  /// 创建当前实例的副本
  Bookmark copyWith({
    int? id,
    int? bookId,
    int? chapterIndex,
    int? position,
    int? endPosition,
    BookmarkType? type,
    HighlightColor? color,
    String? note,
    String? selectedText,
    String? chapterTitle,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Bookmark(
      bookId: bookId ?? this.bookId,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      position: position ?? this.position,
      endPosition: endPosition ?? this.endPosition,
      type: type ?? this.type,
      color: color ?? this.color,
      note: note ?? this.note,
      selectedText: selectedText ?? this.selectedText,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    )..id = id ?? this.id;
  }

  /// 解析书签类型
  static BookmarkType _parseBookmarkType(String? type) {
    switch (type) {
      case 'highlight':
        return BookmarkType.highlight;
      case 'note':
        return BookmarkType.note;
      default:
        return BookmarkType.bookmark;
    }
  }

  /// 解析高亮颜色
  static HighlightColor _parseHighlightColor(String? color) {
    switch (color) {
      case 'green':
        return HighlightColor.green;
      case 'blue':
        return HighlightColor.blue;
      case 'pink':
        return HighlightColor.pink;
      case 'purple':
        return HighlightColor.purple;
      case 'orange':
        return HighlightColor.orange;
      default:
        return HighlightColor.yellow;
    }
  }

  /// 获取高亮颜色对应的十六进制颜色值
  int get colorValue {
    switch (color) {
      case HighlightColor.yellow:
        return 0xFFFFEB3B;
      case HighlightColor.green:
        return 0xFF4CAF50;
      case HighlightColor.blue:
        return 0xFF2196F3;
      case HighlightColor.pink:
        return 0xFFE91E63;
      case HighlightColor.purple:
        return 0xFF9C27B0;
      case HighlightColor.orange:
        return 0xFFFF9800;
    }
  }

  /// 格式化的创建时间字符串
  String get formattedTime {
    final now = DateTime.now();
    final diff = now.difference(createdAt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    return '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}';
  }

  @override
  String toString() =>
      'Bookmark(id: $id, bookId: $bookId, type: ${type.name}, chapter: $chapterIndex)';
}
