import 'package:isar/isar.dart';

part 'book.g.dart'; // Isar 自动生成的代码

@collection
class Book {
  Id id = Isar.autoIncrement;

  String title;
  String author;
  String? coverPath;
  String filePath;
  
  /// 文件类型：epub, txt, pdf
  @Index()
  String fileType;

  int totalChapters;
  int currentChapter;
  double currentPosition;

  /// 阅读进度 (0.0 - 1.0)
  double readingProgress;
  
  DateTime? lastReadTime;
  DateTime dateAdded = DateTime.now();

  List<String> tags;
  bool isFavorite;

  /// 是否来自于在线书源
  bool isFromSource;
  String? sourceUrl;

  int fileSize;

  /// 所属分组 ID (0 或 null 为未分组)
  int? groupId;

  Book({
    this.title = '',
    this.author = '未知作者',
    this.coverPath,
    required this.filePath,
    required this.fileType,
    this.totalChapters = 0,
    this.currentChapter = 0,
    this.currentPosition = 0.0,
    this.readingProgress = 0.0,
    this.lastReadTime,
    this.tags = const [],
    this.isFavorite = false,
    this.isFromSource = false,
    this.sourceUrl,
    this.fileSize = 0,
    this.groupId,
  });

  Book copyWith({
    Id? id,
    String? title,
    String? author,
    String? coverPath,
    String? filePath,
    String? fileType,
    int? totalChapters,
    int? currentChapter,
    double? currentPosition,
    double? readingProgress,
    DateTime? lastReadTime,
    DateTime? dateAdded,
    List<String>? tags,
    bool? isFavorite,
    bool? isFromSource,
    String? sourceUrl,
    int? fileSize,
    int? groupId,
  }) {
    return Book(
      title: title ?? this.title,
      author: author ?? this.author,
      coverPath: coverPath ?? this.coverPath,
      filePath: filePath ?? this.filePath,
      fileType: fileType ?? this.fileType,
      totalChapters: totalChapters ?? this.totalChapters,
      currentChapter: currentChapter ?? this.currentChapter,
      currentPosition: currentPosition ?? this.currentPosition,
      readingProgress: readingProgress ?? this.readingProgress,
      lastReadTime: lastReadTime ?? this.lastReadTime,
      tags: tags ?? this.tags,
      isFavorite: isFavorite ?? this.isFavorite,
      isFromSource: isFromSource ?? this.isFromSource,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      fileSize: fileSize ?? this.fileSize,
      groupId: groupId ?? this.groupId,
    )
      ..id = id ?? this.id
      ..dateAdded = dateAdded ?? this.dateAdded;
  }
}
