/// 阅读App - 阅读进度数据模型
///
/// 使用 Isar 数据库注解进行本地持久化存储。
/// 记录用户在每本书中的精确阅读位置，用于恢复阅读状态。
library;

import 'package:isar/isar.dart';

part 'reading_progress.g.dart';

/// 阅读进度数据模型
///
/// 精确记录用户在某本书中的阅读位置，包括：
/// - 当前章节索引
/// - 章节内的滚动位置
/// - 整本书的阅读百分比
/// - 最后阅读时间
@collection
class ReadingProgress {
  /// Isar 自增主键
  Id id = Isar.autoIncrement;

  /// 关联的书籍ID
  @Index(unique: true, replace: true)
  int bookId;

  /// 当前阅读的章节索引（从0开始）
  int chapterIndex;

  /// 章节内的滚动位置（像素偏移或字符偏移）
  double scrollPosition;

  /// 章节内容中的字符偏移量（用于精确定位）
  int charOffset;

  /// 整本书的阅读进度百分比（0.0 ~ 1.0）
  double percentage;

  /// 上次阅读时间
  @Index()
  DateTime lastReadAt;

  /// 本次阅读会话的开始时间
  DateTime? sessionStartTime;

  /// 本次阅读会话已累计的时长（秒）
  int sessionDurationSeconds;

  /// 构造函数
  ReadingProgress({
    required this.bookId,
    this.chapterIndex = 0,
    this.scrollPosition = 0.0,
    this.charOffset = 0,
    this.percentage = 0.0,
    required this.lastReadAt,
    this.sessionStartTime,
    this.sessionDurationSeconds = 0,
  });

  /// 从 JSON Map 创建 ReadingProgress 实例
  factory ReadingProgress.fromJson(Map<String, dynamic> json) {
    return ReadingProgress(
      bookId: json['bookId'] as int? ?? 0,
      chapterIndex: json['chapterIndex'] as int? ?? 0,
      scrollPosition:
          (json['scrollPosition'] as num?)?.toDouble() ?? 0.0,
      charOffset: json['charOffset'] as int? ?? 0,
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0.0,
      lastReadAt: json['lastReadAt'] != null
          ? DateTime.tryParse(json['lastReadAt'] as String) ??
              DateTime.now()
          : DateTime.now(),
      sessionStartTime: json['sessionStartTime'] != null
          ? DateTime.tryParse(json['sessionStartTime'] as String)
          : null,
      sessionDurationSeconds:
          json['sessionDurationSeconds'] as int? ?? 0,
    )..id = json['id'] as int? ?? Isar.autoIncrement;
  }

  /// 将 ReadingProgress 序列化为 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bookId': bookId,
      'chapterIndex': chapterIndex,
      'scrollPosition': scrollPosition,
      'charOffset': charOffset,
      'percentage': percentage,
      'lastReadAt': lastReadAt.toIso8601String(),
      'sessionStartTime': sessionStartTime?.toIso8601String(),
      'sessionDurationSeconds': sessionDurationSeconds,
    };
  }

  /// 创建当前实例的副本
  ReadingProgress copyWith({
    int? id,
    int? bookId,
    int? chapterIndex,
    double? scrollPosition,
    int? charOffset,
    double? percentage,
    DateTime? lastReadAt,
    DateTime? sessionStartTime,
    int? sessionDurationSeconds,
  }) {
    return ReadingProgress(
      bookId: bookId ?? this.bookId,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      scrollPosition: scrollPosition ?? this.scrollPosition,
      charOffset: charOffset ?? this.charOffset,
      percentage: percentage ?? this.percentage,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      sessionStartTime: sessionStartTime ?? this.sessionStartTime,
      sessionDurationSeconds:
          sessionDurationSeconds ?? this.sessionDurationSeconds,
    )..id = id ?? this.id;
  }

  /// 获取格式化的阅读进度字符串
  String get formattedPercentage =>
      '${(percentage * 100).toStringAsFixed(1)}%';

  /// 获取格式化的最后阅读时间
  String get formattedLastReadTime {
    final now = DateTime.now();
    final diff = now.difference(lastReadAt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${lastReadAt.month}月${lastReadAt.day}日';
  }

  @override
  String toString() =>
      'ReadingProgress(bookId: $bookId, chapter: $chapterIndex, '
      'progress: $formattedPercentage)';
}
