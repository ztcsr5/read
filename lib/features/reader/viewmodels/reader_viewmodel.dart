import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:ui' show Color;

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
  final int fontWeightIndex; // 0=normal, 1=medium, 2=bold
  final double pagePadding; // 页面左右边距
  final bool isJustify; // 是否两端对齐
  final ReaderBackground background;
  final Color customBackgroundColor;
  final ReaderMode mode;
  final bool keepScreenOn; // 屏幕常亮
  final bool volumeKeyTurn; // 音量键翻页
  final List<ReaderTapAction> tapZoneActions;

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
    this.bottomPadding = 32.0,
    this.paragraphIndent = 2,
    this.footerHeight = 80.0,
    this.fontFamily = 'system',
    this.fontWeightIndex = 0,
    this.pagePadding = 24.0,
    this.isJustify = true,
    this.keepScreenOn = true,
    this.volumeKeyTurn = false,
    this.tapZoneActions = ReaderTapAction.defaultZones,
    this.background = ReaderBackground.white,
    this.customBackgroundColor = const Color(0xFFF6F0E4),
    this.mode = ReaderMode.scroll,
    this.bookmarks = const [],
    this.autoScroll = false,
    this.autoScrollSpeed = 1.0,
    this.isPlayingTts = false,
    this.ttsPlayingItemIndex = -1,
  });

  ReaderState copyWith({
    Book? book,
    List<Chapter>? chapters,
    List<Chapter>? loadedChapters,
    List<ReaderItem>? items,
    int? currentChapterIndex,
    double? scrollPosition,
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
  }) {
    return ReaderState(
      book: book ?? this.book,
      chapters: chapters ?? this.chapters,
      loadedChapters: loadedChapters ?? this.loadedChapters,
      items: items ?? this.items,
      currentChapterIndex: currentChapterIndex ?? this.currentChapterIndex,
      scrollPosition: scrollPosition ?? this.scrollPosition,
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
    );
  }
}

/// 阅读器背景色
enum ReaderBackground {
  white(Color(0xFFF9F9F9), '纯白'),
  cream(Color(0xFFF6F0E4), '牛皮纸'),
  green(Color(0xFFE5F1E7), '护眼绿'),
  pink(Color(0xFFFCEFEF), '樱花粉'),
  gray(Color(0xFF333333), '深灰'),
  black(Color(0xFF111111), '极黑'),
  custom(Color(0xFFF6F0E4), '自定义');

  final Color color;
  final String label;
  const ReaderBackground(this.color, this.label);

  /// 获取文字颜色
  Color get textColor {
    switch (this) {
      case ReaderBackground.white:
      case ReaderBackground.cream:
      case ReaderBackground.green:
      case ReaderBackground.pink:
      case ReaderBackground.custom:
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
    if (background == ReaderBackground.custom) {
      return customBackgroundColor;
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

      List<Chapter> chapters = await _bookRepository.getChaptersForBook(id);
      List<Bookmark> bookmarks = await _bookRepository.getBookmarks(id);

      // 在线书籍如果还没拉取过目录，则去爬取
      if (chapters.isEmpty && book.isFromSource && book.sourceUrl != null) {
        final sourceId = int.tryParse(book.sourceUrl!);
        final isar = _bookRepository.isar;
        if (sourceId != null && isar != null) {
          final source = await isar.bookSources.get(sourceId);
          if (source != null) {
            chapters = await LegadoParser.getChapterList(source, book);
            if (chapters.isNotEmpty) {
              await isar.writeTxn(() async {
                await isar.chapters.putAll(chapters);
              });
            }
          }
        }
      }

      // Load current chapter + 2 next chapters for smooth scrolling
      int currentIdx = book.currentChapter;
      int endIndex = (currentIdx + 3).clamp(0, chapters.length);
      final initialLoaded = chapters.sublist(currentIdx, endIndex);

      final initialItems = await _flattenChapters(
        initialLoaded,
        currentIdx,
        book,
      );

      state = state.copyWith(
        book: book,
        chapters: chapters,
        loadedChapters: initialLoaded,
        items: initialItems,
        currentChapterIndex: currentIdx,
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
    final zoneNames = prefs.getStringList('reader.tapZoneActions');
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
      background:
          ReaderBackground.values[(prefs.getInt('reader.background') ??
                  state.background.index)
              .clamp(0, ReaderBackground.values.length - 1)],
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
    await prefs.setInt(
      'reader.customBackgroundColor',
      state.customBackgroundColor.value,
    );
    await prefs.setInt('reader.mode', state.mode.index);
    await prefs.setStringList(
      'reader.tapZoneActions',
      state.tapZoneActions.map((action) => action.name).toList(),
    );
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
    await _loadCurrentChapter(includePrevious: false);
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
    state = state.copyWith(fontWeightIndex: index);
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
    if (state.isPlayingTts) {
      _ttsService.stop();
      state = state.copyWith(isPlayingTts: false, ttsPlayingItemIndex: -1);
    } else {
      // 从当前屏幕顶部最近的 Item 开始读（为了简便，如果还没指定，从第一个开始）
      int startIndex = state.ttsPlayingItemIndex >= 0
          ? state.ttsPlayingItemIndex
          : 0;
      _playTtsItem(startIndex);
    }
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
            await isar.writeTxn(() async {
              await isar.chapters.put(chapter);
            });
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
