import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:ui' show Brightness, Color;

import '../../../data/models/book.dart';
import '../../../data/models/chapter.dart';
import '../../../data/models/bookmark.dart';
import '../../../data/repositories/book_repository.dart';
import '../../../data/models/book_source.dart';
import '../../../data/parsers/legado_parser.dart';
import '../services/tts_service.dart';
import '../../settings/providers/purify_rules_provider.dart';

/// 表示阅读内容中的一个单独段落或标题
class ReaderItem {
  final int chapterIndex;
  final Chapter chapter;
  final int paragraphIndex;
  final int charOffset;
  final String text;
  final bool isTitle;
  final bool isDivider;

  ReaderItem({
    required this.chapterIndex,
    required this.chapter,
    required this.paragraphIndex,
    this.charOffset = 0,
    required this.text,
    this.isTitle = false,
    this.isDivider = false,
  });
}

/// 阅读器状态
class ReaderState {
  final Book? book;
  final List<Chapter> chapters;
  final List<Chapter> loadedChapters;
  final List<ReaderItem> items; // Flattened paragraphs for SliverList
  final int currentChapterIndex;
  final double scrollPosition;
  final int charOffset;
  final double readingProgress;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;

  // 阅读设置
  final double fontSize;
  final double lineHeight;
  final double letterSpacing;
  final double titleSpacing;
  final double paragraphSpacing;
  final double topPadding;
  final double bottomPadding;
  final int paragraphIndent;
  final double footerHeight;
  final String fontFamily;
  final int fontWeightIndex; // -1=system, 0=normal, 1=medium, 2=bold
  final double pagePadding; // 页面左右边距
  final bool isJustify; // 是否两端对齐
  final ReaderBackground background;
  final Color customBackgroundColor;
  final ReaderMode mode;
  final bool keepScreenOn; // 屏幕常亮
  final bool volumeKeyTurn; // 音量键翻页
  final List<ReaderTapAction> tapZoneActions;
  final String? customWallpaperPath;

  // 书签
  final List<Bookmark> bookmarks;

  // 自动翻页
  final bool autoScroll;
  final double autoScrollSpeed;

  // TTS 状态
  final bool isPlayingTts;
  final int ttsPlayingItemIndex;

  const ReaderState({
    this.book,
    this.chapters = const [],
    this.loadedChapters = const [],
    this.items = const [],
    this.currentChapterIndex = 0,
    this.scrollPosition = 0,
    this.charOffset = 0,
    this.readingProgress = 0,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.fontSize = 19.0,
    this.lineHeight = 1.72,
    this.letterSpacing = 0.0,
    this.titleSpacing = 24.0,
    this.paragraphSpacing = 18.0,
    this.topPadding = 28.0,
    this.bottomPadding = 18.0,
    this.paragraphIndent = 2,
    this.footerHeight = 26.0,
    this.fontFamily = 'system',
    this.fontWeightIndex = -1,
    this.pagePadding = 24.0,
    this.isJustify = true,
    this.keepScreenOn = true,
    this.volumeKeyTurn = false,
    this.tapZoneActions = ReaderTapAction.defaultZones,
    this.background = ReaderBackground.system,
    this.customBackgroundColor = const Color(0xFFF6F0E4),
    this.mode = ReaderMode.scroll,
    this.bookmarks = const [],
    this.autoScroll = false,
    this.autoScrollSpeed = 1.0,
    this.isPlayingTts = false,
    this.ttsPlayingItemIndex = -1,
    this.customWallpaperPath,
  });

  ReaderState copyWith({
    Book? book,
    List<Chapter>? chapters,
    List<Chapter>? loadedChapters,
    List<ReaderItem>? items,
    int? currentChapterIndex,
    double? scrollPosition,
    int? charOffset,
    double? readingProgress,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    double? fontSize,
    double? lineHeight,
    double? letterSpacing,
    double? titleSpacing,
    double? paragraphSpacing,
    double? topPadding,
    double? bottomPadding,
    int? paragraphIndent,
    double? footerHeight,
    String? fontFamily,
    int? fontWeightIndex,
    double? pagePadding,
    bool? isJustify,
    bool? keepScreenOn,
    bool? volumeKeyTurn,
    List<ReaderTapAction>? tapZoneActions,
    ReaderBackground? background,
    Color? customBackgroundColor,
    ReaderMode? mode,
    List<Bookmark>? bookmarks,
    bool? autoScroll,
    double? autoScrollSpeed,
    bool? isPlayingTts,
    int? ttsPlayingItemIndex,
    String? customWallpaperPath,
  }) {
    return ReaderState(
      book: book ?? this.book,
      chapters: chapters ?? this.chapters,
      loadedChapters: loadedChapters ?? this.loadedChapters,
      items: items ?? this.items,
      currentChapterIndex: currentChapterIndex ?? this.currentChapterIndex,
      scrollPosition: scrollPosition ?? this.scrollPosition,
      charOffset: charOffset ?? this.charOffset,
      readingProgress: readingProgress ?? this.readingProgress,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: error,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      titleSpacing: titleSpacing ?? this.titleSpacing,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      topPadding: topPadding ?? this.topPadding,
      bottomPadding: bottomPadding ?? this.bottomPadding,
      paragraphIndent: paragraphIndent ?? this.paragraphIndent,
      footerHeight: footerHeight ?? this.footerHeight,
      fontFamily: fontFamily ?? this.fontFamily,
      fontWeightIndex: fontWeightIndex ?? this.fontWeightIndex,
      pagePadding: pagePadding ?? this.pagePadding,
      isJustify: isJustify ?? this.isJustify,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      volumeKeyTurn: volumeKeyTurn ?? this.volumeKeyTurn,
      tapZoneActions: tapZoneActions ?? this.tapZoneActions,
      background: background ?? this.background,
      customBackgroundColor:
          customBackgroundColor ?? this.customBackgroundColor,
      mode: mode ?? this.mode,
      bookmarks: bookmarks ?? this.bookmarks,
      autoScroll: autoScroll ?? this.autoScroll,
      autoScrollSpeed: autoScrollSpeed ?? this.autoScrollSpeed,
      isPlayingTts: isPlayingTts ?? this.isPlayingTts,
      ttsPlayingItemIndex: ttsPlayingItemIndex ?? this.ttsPlayingItemIndex,
      customWallpaperPath: customWallpaperPath ?? this.customWallpaperPath,
    );
  }
}

/// 阅读器背景色
enum ReaderBackground {
  system(Color(0xFFF9F9F9), '跟随系统'),
  white(Color(0xFFF9F9F9), '纯白'),
  cream(Color(0xFFF6F0E4), '牛皮纸'),
  green(Color(0xFFE5F1E7), '护眼绿'),
  pink(Color(0xFFFCEFEF), '樱花粉'),
  gray(Color(0xFF333333), '深灰'),
  black(Color(0xFF111111), '极黑'),
  custom(Color(0xFFF6F0E4), '自定义'),
  customImage(Color(0xFFF6F0E4), '自定义壁纸');

  final Color color;
  final String label;
  const ReaderBackground(this.color, this.label);

  /// 获取文字颜色
  Color get textColor {
    switch (this) {
      case ReaderBackground.system:
      case ReaderBackground.white:
      case ReaderBackground.cream:
      case ReaderBackground.green:
      case ReaderBackground.pink:
      case ReaderBackground.custom:
      case ReaderBackground.customImage:
        return const Color(0xFF2C2C2E);
      case ReaderBackground.gray:
        return const Color(0xFFEBEBF5);
      case ReaderBackground.black:
        return const Color(0xFFD1D1D6);
    }
  }
}

extension ReaderBackgroundResolver on ReaderState {
  Color get resolvedBackgroundColor {
    return resolveBackgroundColor(Brightness.light);
  }

  Color resolveBackgroundColor(Brightness brightness) {
    if (background == ReaderBackground.system) {
      return brightness == Brightness.dark
          ? const Color(0xFF111111)
          : const Color(0xFFF9F9F9);
    }
    if (background == ReaderBackground.custom) {
      return customBackgroundColor;
    }
    if (background == ReaderBackground.customImage) {
      return brightness == Brightness.dark
          ? const Color(0xFF111111)
          : const Color(0xFFF9F9F9);
    }
    return background.color;
  }

  Color get resolvedTextColor {
    final color = resolvedBackgroundColor;
    final brightness = color.computeLuminance();
    return brightness > 0.45
        ? const Color(0xFF2C2C2E)
        : const Color(0xFFEDEDF2);
  }

  Color resolveTextColor(Brightness brightness) {
    final color = resolveBackgroundColor(brightness);
    final luminance = color.computeLuminance();
    return luminance > 0.45 ? const Color(0xFF2C2C2E) : const Color(0xFFEDEDF2);
  }
}

/// 阅读模式
enum ReaderMode {
  scroll('上下滑动'),
  pageTurn('左右翻页'),
  cover('覆盖翻页');

  final String label;
  const ReaderMode(this.label);
}

enum ReaderTapAction {
  previousPage('上一页'),
  nextPage('下一页'),
  previousChapter('上一章'),
  nextChapter('下一章'),
  menu('菜单'),
  disabled('关闭');

  final String label;
  const ReaderTapAction(this.label);

  static const defaultZones = <ReaderTapAction>[
    ReaderTapAction.previousPage,
    ReaderTapAction.previousPage,
    ReaderTapAction.nextPage,
    ReaderTapAction.previousPage,
    ReaderTapAction.menu,
    ReaderTapAction.nextPage,
    ReaderTapAction.nextPage,
    ReaderTapAction.nextPage,
    ReaderTapAction.nextPage,
  ];
}

/// 阅读器 ViewModel
class ReaderViewModel extends StateNotifier<ReaderState> {
  final BookRepository _bookRepository;
  final List<String> _purifyRules;
  final TtsService _ttsService = TtsService();

  ReaderViewModel(this._bookRepository, this._purifyRules)
    : super(const ReaderState()) {
    _loadReaderSettings();
    _ttsService.onStateChanged = (status) {
      if (status == 'stopped' || status == 'error') {
        if (mounted) state = state.copyWith(isPlayingTts: false);
      } else if (status == 'playing') {
        if (mounted) state = state.copyWith(isPlayingTts: true);
      }
    };

    _ttsService.onCompletion = () {
      if (mounted && state.isPlayingTts) {
        _playNextTtsItem();
      }
    };
  }

  @override
  void dispose() {
    _ttsService.stop();
    super.dispose();
  }

  /// 加载书籍
  Future<void> loadBook(String bookId) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final id = int.tryParse(bookId);
      if (id == null) throw Exception('Invalid book ID');

      final book = await _bookRepository.getBookById(id);
      if (book == null) throw Exception('书籍不存在');

      book.lastReadTime = DateTime.now();
      try {
        await _bookRepository.saveBook(book);
      } catch (e) {
        print(
          'Database Error saving book in loadBook: $e. Retaining in memory.',
        );
      }

      List<Chapter> chapters = [];
      try {
        chapters = await _bookRepository.getChaptersForBook(id);
      } catch (e) {
        print('Database Error reading chapters: $e. Using empty catalog.');
      }

      List<Bookmark> bookmarks = [];
      try {
        bookmarks = await _bookRepository.getBookmarks(id);
      } catch (e) {
        print('Database Error reading bookmarks: $e. Using empty bookmarks.');
      }

      int charOffset = 0;
      try {
        final progress = await _bookRepository.getReadingProgress(id);
        if (progress != null) {
          charOffset = progress.charOffset;
        }
      } catch (e) {
        print('Database Error reading ReadingProgress: $e. Defaulting to 0.');
      }

      // 在线书籍如果目录为空或明显少于详情页记录，按 Legado 流程先刷新详情页再拉目录。
      if (book.isFromSource && book.sourceUrl != null) {
        final sourceId = int.tryParse(book.sourceUrl!);
        final isar = _bookRepository.isar;
        if (sourceId != null && isar != null) {
          final source = await isar.bookSources.get(sourceId);
          if (source != null && _shouldRefreshOnlineCatalog(book, chapters)) {
            try {
              final refreshed = await _fetchOnlineCatalog(source, book);
              if (refreshed.chapters.isNotEmpty &&
                  refreshed.chapters.length >= chapters.length) {
                _copyBookRuntimeFields(book, refreshed.book);
                chapters = refreshed.chapters;
                for (final c in chapters) {
                  c.bookId = book.id;
                }
                try {
                  await _bookRepository.saveBook(book);
                  await _bookRepository.deleteChaptersForBook(book.id);
                  await _bookRepository.saveChapters(chapters);
                } catch (e) {
                  // 容错与缓存隔离：数据库存储失败，不阻塞内存数据加载
                  print(
                    'Database Error during catalog persistence: $e. Falling back to memory-only catalog.',
                  );
                }
              }
            } catch (e) {
              print('Error fetching catalog from source: $e');
            }
          }
        }
      }

      if (chapters.isNotEmpty &&
          (book.totalChapters <= 0 || chapters.length >= book.totalChapters) &&
          book.totalChapters != chapters.length) {
        book.totalChapters = chapters.length;
        await _bookRepository.saveBook(book);
      }

      // Load current chapter + 2 next chapters, and 1 previous chapter for smooth scrolling
      int currentIdx = book.currentChapter;
      int startIndex = (currentIdx - 1).clamp(0, chapters.length);
      int endIndex = (currentIdx + 3).clamp(0, chapters.length);
      final initialLoaded = chapters.sublist(startIndex, endIndex);

      final initialItems = await _flattenChapters(
        initialLoaded,
        startIndex,
        book,
      );

      state = state.copyWith(
        book: book,
        chapters: chapters,
        loadedChapters: initialLoaded,
        items: initialItems,
        currentChapterIndex: currentIdx,
        charOffset: charOffset,
        readingProgress: book.readingProgress,
        bookmarks: bookmarks,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '加载书籍失败: $e');
    }
  }

  Future<void> _loadReaderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final customWallpaperPath = prefs.getString('reader.customWallpaperPath');
    final zoneNames = prefs.getStringList('reader.tapZoneActions');
    final savedBackgroundIndex = prefs.containsKey('reader.background.v2')
        ? prefs.getInt('reader.background.v2')
        : ((prefs.getInt('reader.background') ?? -1) + 1);
    final backgroundIndex =
        (savedBackgroundIndex == null || savedBackgroundIndex < 0)
        ? state.background.index
        : savedBackgroundIndex;
    final zones = zoneNames
        ?.map(
          (name) => ReaderTapAction.values.firstWhere(
            (action) => action.name == name,
            orElse: () => ReaderTapAction.menu,
          ),
        )
        .toList();
    if (!mounted) return;
    state = state.copyWith(
      fontSize: prefs.getDouble('reader.fontSize') ?? state.fontSize,
      lineHeight: prefs.getDouble('reader.lineHeight') ?? state.lineHeight,
      letterSpacing:
          prefs.getDouble('reader.letterSpacing') ?? state.letterSpacing,
      titleSpacing:
          prefs.getDouble('reader.titleSpacing') ?? state.titleSpacing,
      paragraphSpacing:
          prefs.getDouble('reader.paragraphSpacing') ?? state.paragraphSpacing,
      topPadding: prefs.getDouble('reader.topPadding') ?? state.topPadding,
      bottomPadding:
          prefs.getDouble('reader.bottomPadding') ?? state.bottomPadding,
      paragraphIndent:
          prefs.getInt('reader.paragraphIndent') ?? state.paragraphIndent,
      footerHeight:
          prefs.getDouble('reader.footerHeight') ?? state.footerHeight,
      fontWeightIndex:
          prefs.getInt('reader.fontWeightIndex') ?? state.fontWeightIndex,
      pagePadding: prefs.getDouble('reader.pagePadding') ?? state.pagePadding,
      isJustify: prefs.getBool('reader.isJustify') ?? state.isJustify,
      keepScreenOn: prefs.getBool('reader.keepScreenOn') ?? state.keepScreenOn,
      volumeKeyTurn:
          prefs.getBool('reader.volumeKeyTurn') ?? state.volumeKeyTurn,
      background: ReaderBackground
          .values[backgroundIndex.clamp(0, ReaderBackground.values.length - 1)],
      customBackgroundColor: Color(
        prefs.getInt('reader.customBackgroundColor') ??
            state.customBackgroundColor.value,
      ),
      mode:
          ReaderMode.values[(prefs.getInt('reader.mode') ?? state.mode.index)
              .clamp(0, ReaderMode.values.length - 1)],
      tapZoneActions: zones != null && zones.length == 9
          ? List.unmodifiable(zones)
          : null,
      customWallpaperPath: customWallpaperPath,
    );
  }

  Future<void> _saveReaderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('reader.fontSize', state.fontSize);
    await prefs.setDouble('reader.lineHeight', state.lineHeight);
    await prefs.setDouble('reader.letterSpacing', state.letterSpacing);
    await prefs.setDouble('reader.titleSpacing', state.titleSpacing);
    await prefs.setDouble('reader.paragraphSpacing', state.paragraphSpacing);
    await prefs.setDouble('reader.topPadding', state.topPadding);
    await prefs.setDouble('reader.bottomPadding', state.bottomPadding);
    await prefs.setInt('reader.paragraphIndent', state.paragraphIndent);
    await prefs.setDouble('reader.footerHeight', state.footerHeight);
    await prefs.setInt('reader.fontWeightIndex', state.fontWeightIndex);
    await prefs.setDouble('reader.pagePadding', state.pagePadding);
    await prefs.setBool('reader.isJustify', state.isJustify);
    await prefs.setBool('reader.keepScreenOn', state.keepScreenOn);
    await prefs.setBool('reader.volumeKeyTurn', state.volumeKeyTurn);
    await prefs.setInt('reader.background', state.background.index);
    await prefs.setInt('reader.background.v2', state.background.index);
    await prefs.setInt(
      'reader.customBackgroundColor',
      state.customBackgroundColor.value,
    );
    await prefs.setInt('reader.mode', state.mode.index);
    await prefs.setStringList(
      'reader.tapZoneActions',
      state.tapZoneActions.map((action) => action.name).toList(),
    );
    if (state.customWallpaperPath != null) {
      await prefs.setString(
        'reader.customWallpaperPath',
        state.customWallpaperPath!,
      );
    } else {
      await prefs.remove('reader.customWallpaperPath');
    }
  }

  /// 加载下一章
  Future<void> loadNextChapter() async {
    if (state.isLoadingMore) return;
    if (state.currentChapterIndex >= state.chapters.length - 1) return;

    state = state.copyWith(isLoadingMore: true);

    try {
      final nextIndex = state.loadedChapters.isEmpty
          ? state.currentChapterIndex
          : state.loadedChapters.last.index + 1;
      if (nextIndex < state.chapters.length) {
        final nextChapter = state.chapters[nextIndex];
        final newChapters = List<Chapter>.from(state.loadedChapters)
          ..add(nextChapter);

        final newItems = List<ReaderItem>.from(state.items)
          ..addAll(
            await _flattenChapters([nextChapter], nextIndex, state.book!),
          );

        state = state.copyWith(
          loadedChapters: newChapters,
          items: newItems,
          isLoadingMore: false,
        );
      } else {
        state = state.copyWith(isLoadingMore: false);
      }
    } catch (e) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  /// 内部加载当前章附近内容。目录跳转时会带上上一章，便于继续往上读。
  Future<void> _loadCurrentChapter({bool includePrevious = false}) async {
    final book = state.book;
    if (book == null) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final currentIdx = state.currentChapterIndex;
      final startIndex = includePrevious
          ? (currentIdx - 1).clamp(0, state.chapters.length)
          : currentIdx;
      final endIndex = (currentIdx + 3).clamp(0, state.chapters.length);
      final loaded = state.chapters.sublist(startIndex, endIndex);
      final items = await _flattenChapters(loaded, startIndex, book);

      state = state.copyWith(
        loadedChapters: loaded,
        items: items,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '加载章节失败: $e');
    }
  }

  /// 跳转到指定章节
  Future<void> jumpToChapter(int index) async {
    if (index < 0 || index >= state.chapters.length) return;
    state = state.copyWith(currentChapterIndex: index, scrollPosition: 0);

    // 目录跳转必须从目标章节标题开始，避免加载上一章造成视觉错位。
    await _loadCurrentChapter(includePrevious: true);
  }

  /// 跳转到指定书签
  Future<void> jumpToBookmark(Bookmark bookmark) async {
    if (bookmark.chapterIndex < 0 ||
        bookmark.chapterIndex >= state.chapters.length) {
      return;
    }
    state = state.copyWith(currentChapterIndex: bookmark.chapterIndex);
    await _loadCurrentChapter(includePrevious: true);
  }

  /// 更新阅读进度
  void updateProgress(double progress) {
    state = state.copyWith(readingProgress: progress.clamp(0.0, 1.0));
  }

  void updateVisibleChapter(int chapterIndex) {
    if (chapterIndex < 0 || chapterIndex >= state.chapters.length) return;
    state = state.copyWith(
      currentChapterIndex: chapterIndex,
      readingProgress: ((chapterIndex + 1) / state.chapters.length).clamp(
        0.0,
        1.0,
      ),
    );
  }

  Future<void> saveReadingPosition({
    required int chapterIndex,
    required int charOffset,
    required double scrollPosition,
  }) async {
    final book = state.book;
    if (book == null || state.chapters.isEmpty) return;

    final progress = ((chapterIndex + 1) / state.chapters.length).clamp(
      0.0,
      1.0,
    );
    await _bookRepository.updateReadingProgress(
      book.id,
      chapterIndex,
      charOffset,
      scrollPosition: scrollPosition,
      percentage: progress,
    );

    book.currentChapter = chapterIndex;
    book.currentPosition = scrollPosition;
    book.readingProgress = progress;
    book.lastReadTime = DateTime.now();

    if (mounted) {
      state = state.copyWith(
        book: book,
        currentChapterIndex: chapterIndex,
        charOffset: charOffset,
        scrollPosition: scrollPosition,
        readingProgress: progress,
      );
    }
  }

  /// 设置字号
  void setFontSize(double size) {
    state = state.copyWith(fontSize: size.clamp(12.0, 32.0));
    _saveReaderSettings();
  }

  /// 设置行距
  void setLineHeight(double height) {
    state = state.copyWith(lineHeight: height.clamp(1.2, 2.5));
    _saveReaderSettings();
  }

  void setLetterSpacing(double spacing) {
    state = state.copyWith(letterSpacing: spacing.clamp(0.0, 3.0));
    _saveReaderSettings();
  }

  void setTitleSpacing(double spacing) {
    state = state.copyWith(titleSpacing: spacing.clamp(0.0, 80.0));
    _saveReaderSettings();
  }

  void setParagraphSpacing(double spacing) {
    state = state.copyWith(paragraphSpacing: spacing.clamp(0.0, 60.0));
    _saveReaderSettings();
  }

  void setVerticalPadding({double? top, double? bottom}) {
    state = state.copyWith(
      topPadding: (top ?? state.topPadding).clamp(0.0, 80.0),
      bottomPadding: (bottom ?? state.bottomPadding).clamp(0.0, 100.0),
    );
    _saveReaderSettings();
  }

  void setParagraphIndent(int indent) {
    state = state.copyWith(paragraphIndent: indent.clamp(0, 4));
    _saveReaderSettings();
  }

  void setFooterHeight(double height) {
    state = state.copyWith(footerHeight: height.clamp(0.0, 140.0));
    _saveReaderSettings();
  }

  /// 设置背景色
  void setBackground(ReaderBackground bg) {
    state = state.copyWith(background: bg);
    _saveReaderSettings();
  }

  void setCustomBackground(Color color) {
    state = state.copyWith(
      background: ReaderBackground.custom,
      customBackgroundColor: color,
    );
    _saveReaderSettings();
  }

  /// 设置字体
  void setFontFamily(String font) {
    state = state.copyWith(fontFamily: font);
  }

  /// 设置字体粗细
  void setFontWeight(int index) {
    state = state.copyWith(fontWeightIndex: index.clamp(-1, 2));
    _saveReaderSettings();
  }

  /// 设置排版对齐
  void setJustify(bool justify) {
    state = state.copyWith(isJustify: justify);
    _saveReaderSettings();
  }

  /// 设置页边距
  void setPagePadding(double padding) {
    state = state.copyWith(pagePadding: padding.clamp(10.0, 40.0));
    _saveReaderSettings();
  }

  /// 切换屏幕常亮
  void toggleKeepScreenOn() {
    state = state.copyWith(keepScreenOn: !state.keepScreenOn);
    _saveReaderSettings();
  }

  /// 切换音量键翻页
  void toggleVolumeKeyTurn() {
    state = state.copyWith(volumeKeyTurn: !state.volumeKeyTurn);
    _saveReaderSettings();
  }

  /// 设置阅读模式
  void setMode(ReaderMode mode) {
    state = state.copyWith(mode: mode);
    _saveReaderSettings();
  }

  void setTapZoneAction(int index, ReaderTapAction action) {
    if (index < 0 || index >= 9) return;
    final actions = List<ReaderTapAction>.from(state.tapZoneActions);
    actions[index] = action;
    if (!actions.contains(ReaderTapAction.menu)) {
      actions[4] = ReaderTapAction.menu;
    }
    state = state.copyWith(tapZoneActions: List.unmodifiable(actions));
    _saveReaderSettings();
  }

  Future<List<BookSource>> getEnabledSwitchSources() async {
    final currentSourceId = int.tryParse(state.book?.sourceUrl ?? '');
    final sources = await _bookRepository.getAllBookSources();
    return sources
        .where((source) => source.enabled && source.id != currentSourceId)
        .toList();
  }

  Future<void> switchBookSource(BookSource source, Book candidate) async {
    final currentBook = state.book;
    if (currentBook == null) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final fetched = await _fetchOnlineCatalog(source, candidate);
      final replacement = fetched.book;

      final updatedBook = currentBook.copyWith(
        title: replacement.title.isEmpty
            ? currentBook.title
            : replacement.title,
        author: replacement.author.isEmpty
            ? currentBook.author
            : replacement.author,
        coverPath: replacement.coverPath?.isEmpty ?? true
            ? currentBook.coverPath
            : replacement.coverPath,
        filePath: replacement.filePath,
        fileType: 'online',
        sourceUrl: source.id.toString(),
      )..isFromSource = true;

      final oldChapterTitle =
          state.currentChapterIndex >= 0 &&
              state.currentChapterIndex < state.chapters.length
          ? state.chapters[state.currentChapterIndex].title
          : '';
      final chapters = fetched.book.filePath == updatedBook.filePath
          ? fetched.chapters
          : await LegadoParser.getChapterList(source, updatedBook);
      if (chapters.isEmpty) {
        throw Exception('新书源没有解析到目录');
      }
      for (final chapter in chapters) {
        chapter.bookId = updatedBook.id;
      }

      final currentIndex = _matchChapterIndex(
        chapters,
        oldChapterTitle,
      ).clamp(0, chapters.length - 1);
      updatedBook
        ..totalChapters = chapters.length
        ..currentChapter = currentIndex
        ..currentPosition = 0
        ..readingProgress = ((currentIndex + 1) / chapters.length).clamp(
          0.0,
          1.0,
        )
        ..lastReadTime = DateTime.now();

      try {
        await _bookRepository.saveBook(updatedBook);
      } catch (e) {
        print(
          'Database Error saving book in switchBookSource: $e. Continuing.',
        );
      }
      try {
        await _bookRepository.deleteChaptersForBook(updatedBook.id);
      } catch (e) {
        print(
          'Database Error deleting chapters in switchBookSource: $e. Continuing.',
        );
      }
      try {
        await _bookRepository.saveChapters(chapters);
      } catch (e) {
        print(
          'Database Error saving chapters in switchBookSource: $e. Continuing.',
        );
      }

      state = state.copyWith(
        book: updatedBook,
        chapters: chapters,
        loadedChapters: const [],
        items: const [],
        currentChapterIndex: currentIndex,
        scrollPosition: 0,
        readingProgress: updatedBook.readingProgress,
        isLoading: false,
      );
      await _loadCurrentChapter(includePrevious: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: '换源失败: $e');
      rethrow;
    }
  }

  Future<int> refreshCatalog() async {
    final book = state.book;
    if (book == null || !book.isFromSource || book.sourceUrl == null) {
      throw Exception('本地书籍不支持刷新在线目录');
    }
    final sourceId = int.tryParse(book.sourceUrl!);
    final isar = _bookRepository.isar;
    if (sourceId == null || isar == null) {
      throw Exception('无法定位当前书源');
    }

    final source = await isar.bookSources.get(sourceId);
    if (source == null) {
      throw Exception('当前书源不存在或已被删除');
    }

    state = state.copyWith(isLoading: true, error: null);
    try {
      final refreshed = await _fetchOnlineCatalog(source, book);
      final refreshedBook = refreshed.book;
      final chapters = refreshed.chapters;
      if (chapters.isEmpty) {
        throw Exception('没有解析到目录，请单源测试 ruleToc');
      }
      for (final chapter in chapters) {
        chapter.bookId = refreshedBook.id;
      }

      final currentIndex = state.currentChapterIndex
          .clamp(0, chapters.length - 1)
          .toInt();
      refreshedBook
        ..totalChapters = chapters.length
        ..currentChapter = currentIndex
        ..readingProgress = ((currentIndex + 1) / chapters.length).clamp(
          0.0,
          1.0,
        )
        ..lastReadTime = DateTime.now();

      try {
        await _bookRepository.saveBook(refreshedBook);
        await _bookRepository.deleteChaptersForBook(refreshedBook.id);
        await _bookRepository.saveChapters(chapters);
      } catch (e) {
        print('Database Error refreshing catalog: $e. Keeping memory state.');
      }

      state = state.copyWith(
        book: refreshedBook,
        chapters: chapters,
        loadedChapters: const [],
        items: const [],
        currentChapterIndex: currentIndex,
        scrollPosition: 0,
        readingProgress: refreshedBook.readingProgress,
        isLoading: false,
      );
      await _loadCurrentChapter(includePrevious: true);
      return chapters.length;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: null);
      rethrow;
    }
  }

  bool _shouldRefreshOnlineCatalog(Book book, List<Chapter> chapters) {
    if (!book.isFromSource) return false;
    if (chapters.isEmpty) return true;
    final expected = book.totalChapters;
    if (expected <= 0) return false;
    return expected > chapters.length && expected - chapters.length >= 3;
  }

  Future<({Book book, List<Chapter> chapters})> _fetchOnlineCatalog(
    BookSource source,
    Book book,
  ) async {
    var detailBook = book;
    try {
      detailBook = await LegadoParser.parseBookInfo(source, book);
    } catch (_) {
      detailBook = book;
    }
    final chapters = await LegadoParser.getChapterList(source, detailBook);
    return (book: detailBook, chapters: chapters);
  }

  void _copyBookRuntimeFields(Book target, Book source) {
    target
      ..title = source.title.isEmpty || source.title == '未知'
          ? target.title
          : source.title
      ..author = source.author.isEmpty ? target.author : source.author
      ..coverPath = source.coverPath?.isEmpty ?? true
          ? target.coverPath
          : source.coverPath
      ..filePath = source.filePath.isEmpty ? target.filePath : source.filePath
      ..fileType = source.fileType.isEmpty ? target.fileType : source.fileType
      ..totalChapters = source.totalChapters > 0
          ? source.totalChapters
          : target.totalChapters
      ..fileSize = source.fileSize > 0 ? source.fileSize : target.fileSize
      ..isFromSource = true
      ..sourceUrl = source.sourceUrl ?? target.sourceUrl;
  }

  int _matchChapterIndex(List<Chapter> chapters, String title) {
    if (title.trim().isEmpty) return state.currentChapterIndex;
    final target = _normalizeTitleText(title);
    final exact = chapters.indexWhere(
      (chapter) => _normalizeTitleText(chapter.title) == target,
    );
    if (exact >= 0) return exact;
    final fuzzy = chapters.indexWhere((chapter) {
      final value = _normalizeTitleText(chapter.title);
      return value.contains(target) || target.contains(value);
    });
    return fuzzy >= 0 ? fuzzy : state.currentChapterIndex;
  }

  /// 切换自动翻页
  void toggleAutoScroll() {
    state = state.copyWith(autoScroll: !state.autoScroll);
  }

  /// 设置自动翻页速度
  void setAutoScrollSpeed(double speed) {
    state = state.copyWith(autoScrollSpeed: speed.clamp(0.5, 5.0));
  }

  // --- TTS 逻辑 ---

  /// 切换 TTS 播放状态
  void toggleTts() {
    toggleTtsFromItem(null);
  }

  void toggleTtsFromItem(ReaderItem? startItem) {
    if (state.isPlayingTts) {
      _ttsService.stop();
      state = state.copyWith(isPlayingTts: false, ttsPlayingItemIndex: -1);
    } else {
      // 从当前屏幕顶部最近的 Item 开始读（为了简便，如果还没指定，从第一个开始）
      var startIndex = startItem == null ? -1 : _indexOfReaderItem(startItem);
      if (startIndex < 0 && state.ttsPlayingItemIndex >= 0) {
        startIndex = state.ttsPlayingItemIndex;
      }
      if (startIndex < 0) startIndex = 0;
      _playTtsItem(startIndex);
    }
  }

  int _indexOfReaderItem(ReaderItem target) {
    return state.items.indexWhere(
      (item) =>
          identical(item, target) ||
          (item.chapterIndex == target.chapterIndex &&
              item.paragraphIndex == target.paragraphIndex &&
              item.charOffset == target.charOffset &&
              item.isTitle == target.isTitle &&
              item.isDivider == target.isDivider),
    );
  }

  void _playTtsItem(int index) {
    if (index >= state.items.length) {
      // 尝试加载下一章并继续播放
      loadNextChapter().then((_) {
        if (index < state.items.length) {
          _playTtsItem(index);
        } else {
          _ttsService.stop();
          state = state.copyWith(isPlayingTts: false, ttsPlayingItemIndex: -1);
        }
      });
      return;
    }

    final item = state.items[index];
    state = state.copyWith(isPlayingTts: true, ttsPlayingItemIndex: index);

    if (item.isDivider || item.text.trim().isEmpty) {
      // 跳过空段落和分割线
      _playNextTtsItem();
    } else {
      _ttsService.speak(item.text);
    }
  }

  void _playNextTtsItem() {
    if (!state.isPlayingTts) return;
    final nextIdx = state.ttsPlayingItemIndex + 1;
    _playTtsItem(nextIdx);
  }

  // --- 书签逻辑 ---

  /// 添加书签
  Future<void> addBookmark(Bookmark bookmark) async {
    await _bookRepository.saveBookmark(bookmark);
    final bookId = state.book?.id;
    if (bookId != null) {
      final bookmarks = await _bookRepository.getBookmarks(bookId);
      state = state.copyWith(bookmarks: bookmarks);
    }
  }

  /// 删除书签
  Future<void> removeBookmark(int bookmarkId) async {
    await _bookRepository.deleteBookmark(bookmarkId);
    final bookId = state.book?.id;
    if (bookId != null) {
      final bookmarks = await _bookRepository.getBookmarks(bookId);
      state = state.copyWith(bookmarks: bookmarks);
    }
  }

  /// Helper to flatten chapters into paragraphs
  Future<List<ReaderItem>> _flattenChapters(
    List<Chapter> chapters,
    int startIndex,
    Book book,
  ) async {
    List<ReaderItem> flattened = [];
    int globalChapIdx = startIndex;
    for (var chapter in chapters) {
      flattened.add(
        ReaderItem(
          chapterIndex: globalChapIdx,
          chapter: chapter,
          paragraphIndex: -1,
          text: chapter.title,
          isTitle: true,
        ),
      );

      String? textContent = chapter.content;

      // 如果是在线书籍且正文存的是 URL，则加载正文
      if (book.isFromSource &&
          textContent != null &&
          textContent.startsWith('http')) {
        final sourceId = int.tryParse(book.sourceUrl ?? '');
        final isar = _bookRepository.isar;
        if (sourceId != null && isar != null) {
          final source = await isar.bookSources.get(sourceId);
          if (source != null) {
            textContent = await LegadoParser.getChapterContent(
              source,
              textContent,
            );
            // 存回本地以免重复请求
            chapter.content = textContent;
            try {
              await isar.writeTxn(() async {
                await isar.chapters.put(chapter);
              });
            } catch (e) {
              print(
                'Database Error caching chapter content: $e. Retaining in memory.',
              );
            }
          }
        }
      }

      if (textContent != null && textContent.isNotEmpty) {
        // 应用净化规则
        String filteredContent = textContent;
        for (var rule in _purifyRules) {
          try {
            filteredContent = filteredContent.replaceAll(RegExp(rule), '');
          } catch (e) {
            filteredContent = filteredContent.replaceAll(rule, '');
          }
        }

        filteredContent = _normalizeChapterContent(
          filteredContent,
          chapter.title,
        );

        final paragraphs = filteredContent.split(RegExp(r'\n+'));
        var charOffset = 0;
        for (int i = 0; i < paragraphs.length; i++) {
          final rawText = paragraphs[i];
          final text = rawText.trim();
          if (text.isNotEmpty) {
            flattened.add(
              ReaderItem(
                chapterIndex: globalChapIdx,
                chapter: chapter,
                paragraphIndex: i,
                charOffset: charOffset,
                text: text,
              ),
            );
          }
          charOffset += rawText.length + 1;
        }
      }

      // Add divider
      flattened.add(
        ReaderItem(
          chapterIndex: globalChapIdx,
          chapter: chapter,
          paragraphIndex: 99999,
          text: '',
          isDivider: true,
        ),
      );

      globalChapIdx++;
    }
    return flattened;
  }

  String _normalizeChapterContent(String content, String title) {
    final lines = content
        .replaceAll(
          RegExp(r'<[^>]*>', multiLine: true, caseSensitive: false),
          '',
        )
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\uFEFF', '')
        .split('\n')
        .map((line) => line.trim())
        .toList();

    while (lines.isNotEmpty && lines.first.isEmpty) {
      lines.removeAt(0);
    }

    while (lines.isNotEmpty && _sameChapterTitle(lines.first, title)) {
      lines.removeAt(0);
      while (lines.isNotEmpty && lines.first.isEmpty) {
        lines.removeAt(0);
      }
    }

    final normalized = <String>[];
    var sawBlank = false;
    for (final line in lines) {
      if (line.isEmpty) {
        sawBlank = normalized.isNotEmpty;
        continue;
      }
      if (sawBlank && normalized.isNotEmpty) {
        normalized.add('');
      }
      normalized.add(line);
      sawBlank = false;
    }
    while (normalized.isNotEmpty && normalized.last.isEmpty) {
      normalized.removeLast();
    }
    return normalized.join('\n');
  }

  // ignore: unused_element
  List<({String text, int offset})> _splitLongReaderParagraph(String text) {
    const maxChunkLength = 180;
    final value = text.trim();
    if (value.length <= maxChunkLength) {
      return [(text: value, offset: 0)];
    }

    final chunks = <({String text, int offset})>[];
    var start = 0;
    while (start < value.length) {
      var end = start + maxChunkLength;
      if (end >= value.length) {
        chunks.add((text: value.substring(start).trim(), offset: start));
        break;
      }

      final minBreak = start + (maxChunkLength * 0.58).round();
      var breakAt = -1;
      for (var i = end; i >= minBreak; i--) {
        final unit = value.codeUnitAt(i - 1);
        if (_isGoodParagraphBreak(unit)) {
          breakAt = i;
          break;
        }
      }
      if (breakAt <= start) breakAt = end;

      final chunk = value.substring(start, breakAt).trim();
      if (chunk.isNotEmpty) {
        chunks.add((text: chunk, offset: start));
      }
      start = breakAt;
      while (start < value.length &&
          (value.codeUnitAt(start) == 0x20 ||
              value.codeUnitAt(start) == 0x3000)) {
        start++;
      }
    }
    return chunks;
  }

  bool _isGoodParagraphBreak(int unit) {
    return unit == 0x3002 || // 。
        unit == 0xff01 || // ！
        unit == 0xff1f || // ？
        unit == 0xff1b || // ；
        unit == 0x003b || // ;
        unit == 0x002e || // .
        unit == 0x0021 || // !
        unit == 0x003f || // ?
        unit == 0x3000 || // full-width space
        unit == 0x0020; // space
  }

  bool _sameChapterTitle(String line, String title) {
    final normalizedLine = _normalizeTitleText(line);
    final normalizedTitle = _normalizeTitleText(title);
    if (normalizedLine.isEmpty || normalizedTitle.isEmpty) return false;
    if (normalizedLine == normalizedTitle) return true;
    return normalizedLine.startsWith(normalizedTitle) &&
        normalizedLine.length <= normalizedTitle.length + 8;
  }

  String _normalizeTitleText(String value) {
    return value.toLowerCase().replaceAll(
      RegExp(r'[\s　:：，,。.！!？?、\-—_【】\[\]（）()]+'),
      '',
    );
  }

  Future<void> setCustomWallpaperPath(String path) async {
    state = state.copyWith(
      background: ReaderBackground.customImage,
      customWallpaperPath: path,
    );
    await _saveReaderSettings();
  }

  Future<void> startDownloadChapters({int? limit}) async {
    final book = state.book;
    if (book == null || !book.isFromSource || book.sourceUrl == null) return;
    final sourceId = int.tryParse(book.sourceUrl!);
    final isar = _bookRepository.isar;
    if (sourceId == null || isar == null) return;

    final source = await isar.bookSources.get(sourceId);
    if (source == null) return;

    final startIdx = state.currentChapterIndex;
    final allChapters = state.chapters;

    final toDownload = allChapters
        .skip(startIdx)
        .where(
          (c) =>
              !c.isDownloaded &&
              c.content != null &&
              c.content!.startsWith('http'),
        )
        .toList();

    final limitList = limit != null
        ? toDownload.take(limit).toList()
        : toDownload;
    if (limitList.isEmpty) return;

    final int maxConcurrent = 3;
    var index = 0;

    Future<void> worker() async {
      while (index < limitList.length) {
        final currentJobIndex = index++;
        if (currentJobIndex >= limitList.length) break;
        final chapter = limitList[currentJobIndex];
        try {
          final contentUrl = chapter.content!;
          final content = await LegadoParser.getChapterContent(
            source,
            contentUrl,
          );

          chapter.content = content;
          chapter.isDownloaded = true;
          chapter.wordCount = content.length;

          await isar.writeTxn(() async {
            await isar.chapters.put(chapter);
          });

          if (mounted) {
            final updatedChapters = List<Chapter>.from(state.chapters);
            final idx = updatedChapters.indexWhere((c) => c.id == chapter.id);
            if (idx >= 0) {
              updatedChapters[idx] = chapter;
              state = state.copyWith(chapters: updatedChapters);
            }
          }
        } catch (e) {
          print('Failed to download chapter ${chapter.title}: $e');
        }
      }
    }

    final workers = List.generate(maxConcurrent, (_) => worker());
    await Future.wait(workers);
  }
}

/// 对应的 Provider，使用 family 接收 bookId 参数
final readerViewModelProvider =
    StateNotifierProvider.family<ReaderViewModel, ReaderState, String>((
      ref,
      bookId,
    ) {
      final repo = ref.watch(bookRepositoryProvider);
      final rules = ref.watch(purifyRulesProvider);
      return ReaderViewModel(repo, rules)..loadBook(bookId);
    });
