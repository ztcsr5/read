/// 阅读App - 阅读统计数据模型
///
/// 使用 Isar 数据库注解进行本地持久化存储。
/// 按日期记录用户的阅读时长、页数、字数等统计数据。
library;

import 'package:isar/isar.dart';

part 'reading_stats.g.dart';

/// 阅读统计数据模型（按日统计）
///
/// 每天生成一条统计记录，记录当天的阅读活动数据。
/// 用于生成阅读统计报告、计算连续阅读天数等。
@collection
class ReadingStats {
  /// Isar 自增主键
  Id id = Isar.autoIncrement;

  /// 统计日期（精确到天，时分秒为0）
  @Index(unique: true, replace: true)
  DateTime date;

  /// 当天总阅读时长（秒）
  int readingDurationSeconds;

  /// 当天阅读的页数（估算值）
  int pagesRead;

  /// 当天阅读的字数（估算值）
  int wordsRead;

  /// 当天开始阅读的新书数量
  int booksStarted;

  /// 当天读完的书籍数量
  int booksFinished;

  /// 当天打开过的书籍ID列表（JSON数组字符串）
  List<int> booksOpened;

  /// 当天的阅读会话次数
  int sessionCount;

  /// 构造函数
  ReadingStats({
    required DateTime date,
    this.readingDurationSeconds = 0,
    this.pagesRead = 0,
    this.wordsRead = 0,
    this.booksStarted = 0,
    this.booksFinished = 0,
    this.booksOpened = const [],
    this.sessionCount = 0,
  }) : date = DateTime(date.year, date.month, date.day);

  /// 从 JSON Map 创建 ReadingStats 实例
  factory ReadingStats.fromJson(Map<String, dynamic> json) {
    return ReadingStats(
      date: json['date'] != null
          ? DateTime.tryParse(json['date'] as String) ?? DateTime.now()
          : DateTime.now(),
      readingDurationSeconds:
          json['readingDurationSeconds'] as int? ?? 0,
      pagesRead: json['pagesRead'] as int? ?? 0,
      wordsRead: json['wordsRead'] as int? ?? 0,
      booksStarted: json['booksStarted'] as int? ?? 0,
      booksFinished: json['booksFinished'] as int? ?? 0,
      booksOpened: (json['booksOpened'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [],
      sessionCount: json['sessionCount'] as int? ?? 0,
    )..id = json['id'] as int? ?? Isar.autoIncrement;
  }

  /// 将 ReadingStats 序列化为 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'readingDurationSeconds': readingDurationSeconds,
      'pagesRead': pagesRead,
      'wordsRead': wordsRead,
      'booksStarted': booksStarted,
      'booksFinished': booksFinished,
      'booksOpened': booksOpened,
      'sessionCount': sessionCount,
    };
  }

  /// 创建当前实例的副本
  ReadingStats copyWith({
    int? id,
    DateTime? date,
    int? readingDurationSeconds,
    int? pagesRead,
    int? wordsRead,
    int? booksStarted,
    int? booksFinished,
    List<int>? booksOpened,
    int? sessionCount,
  }) {
    return ReadingStats(
      date: date ?? this.date,
      readingDurationSeconds:
          readingDurationSeconds ?? this.readingDurationSeconds,
      pagesRead: pagesRead ?? this.pagesRead,
      wordsRead: wordsRead ?? this.wordsRead,
      booksStarted: booksStarted ?? this.booksStarted,
      booksFinished: booksFinished ?? this.booksFinished,
      booksOpened: booksOpened ?? List.from(this.booksOpened),
      sessionCount: sessionCount ?? this.sessionCount,
    )..id = id ?? this.id;
  }

  /// 获取格式化的阅读时长字符串
  ///
  /// 将秒数转换为 "X小时Y分钟" 的可读格式。
  String get formattedDuration {
    if (readingDurationSeconds < 60) {
      return '$readingDurationSeconds秒';
    }
    final hours = readingDurationSeconds ~/ 3600;
    final minutes = (readingDurationSeconds % 3600) ~/ 60;
    if (hours > 0) {
      return minutes > 0 ? '$hours小时$minutes分钟' : '$hours小时';
    }
    return '$minutes分钟';
  }

  /// 获取格式化的日期字符串
  String get formattedDate {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    if (date == today) return '今天';
    if (date == yesterday) return '昨天';
    return '${date.month}月${date.day}日';
  }

  /// 累加阅读时长
  void addDuration(int seconds) {
    readingDurationSeconds += seconds;
  }

  /// 累加阅读字数
  void addWords(int words) {
    wordsRead += words;
  }

  /// 累加阅读页数
  void addPages(int pages) {
    pagesRead += pages;
  }

  /// 记录打开的书籍
  void recordBookOpened(int bookId) {
    if (!booksOpened.contains(bookId)) {
      booksOpened = [...booksOpened, bookId];
    }
  }

  /// 增加阅读会话计数
  void incrementSessionCount() {
    sessionCount++;
  }

  @override
  String toString() =>
      'ReadingStats(date: $formattedDate, duration: $formattedDuration, '
      'words: $wordsRead)';
}
