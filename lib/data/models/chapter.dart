import 'package:isar/isar.dart';

part 'chapter.g.dart';

@collection
class Chapter {
  Id id = Isar.autoIncrement;

  @Index()
  int bookId;

  String title;
  int index;

  /// 本地文件书籍为纯文本，在线书籍为HTML
  String? content;
  
  /// 在线书源的章节链接
  String? url;

  bool isDownloaded;
  int wordCount;

  Chapter({
    required this.bookId,
    required this.title,
    required this.index,
    this.content,
    this.url,
    this.isDownloaded = false,
    this.wordCount = 0,
  });
}
