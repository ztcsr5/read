import 'dart:ui' show FontVariation, ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/bookmark.dart';
import '../../../data/models/book.dart';
import '../../../data/models/book_source.dart';
import '../../../data/parsers/legado_parser.dart';
import '../../../app/theme/colors.dart';
import '../../../app/theme/dimensions.dart';
import '../models/reader_navigation_target.dart';
import '../widgets/reader_settings_panel.dart';
import '../views/reader_book_details_page.dart';
import '../views/reader_toc_page.dart';
import '../viewmodels/reader_viewmodel.dart';

/// 阅读器页面 — 核心阅读体验
///
/// 特性：
/// - 全局丝滑无限滑动，自动加载章节
/// - 120Hz ProMotion 流畅刷新
/// - 点击显示/隐藏工具栏
/// - 底部进度条和工具栏
class ReaderPage extends ConsumerStatefulWidget {
  final String bookId;

  const ReaderPage({super.key, required this.bookId});

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // 滚动控制器 — 无限滑动的核心
  final ScrollController _scrollController = ScrollController();
  final PageController _pageController = PageController();
  final Map<int, GlobalKey> _itemKeys = {};

  // UI 状态
  bool _showOverlay = false;
  bool _showSettings = false;
  bool _didRestoreScrollPosition = false;
  int _lastVisibleItemIndex = 0;
  int _lastPagedPageIndex = 0;
  DateTime _lastProgressSaveAt = DateTime.fromMillisecondsSinceEpoch(0);

  // 动画控制器
  late AnimationController _overlayAnimController;
  late Animation<double> _overlayAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 工具栏动画
    _overlayAnimController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _overlayAnimation = CurvedAnimation(
      parent: _overlayAnimController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    // 滚动监听 — 80% 位置触发预加载
    _scrollController.addListener(_onScroll);

    // 初始加载由 Provider 创建时自动调用，无需手动

    // 全屏沉浸模式
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // 先保存当前位置，再销毁滚动控制器，否则返回书架时会丢失最后一屏位置。
    _saveReadingProgress();

    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _pageController.dispose();
    _overlayAnimController.dispose();

    // 恢复系统 UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _saveReadingProgress();
    }
  }

  /// 滚动监听 — 实现无限滑动
  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    final maxExtent = position.maxScrollExtent;
    final currentScroll = position.pixels;

    final vm = ref.read(readerViewModelProvider(widget.bookId).notifier);
    final state = ref.read(readerViewModelProvider(widget.bookId));

    // 向下滑动 — 80% 位置预加载下一章
    if (currentScroll >= maxExtent * 0.8 && !state.isLoadingMore) {
      vm.loadNextChapter();
    }

    _updateCurrentChapter();

    final now = DateTime.now();
    if (now.difference(_lastProgressSaveAt).inMilliseconds > 900) {
      _lastProgressSaveAt = now;
      _saveReadingProgress();
    }
  }

  /// 更新当前章节位置
  void _updateCurrentChapter() {
    final visibleItem = _findTopVisibleItem();
    if (visibleItem == null) return;

    final state = ref.read(readerViewModelProvider(widget.bookId));
    if (visibleItem.chapterIndex != state.currentChapterIndex) {
      ref
          .read(readerViewModelProvider(widget.bookId).notifier)
          .updateVisibleChapter(visibleItem.chapterIndex);
    }
  }

  /// 保存阅读进度
  void _saveReadingProgress() {
    final state = ref.read(readerViewModelProvider(widget.bookId));
    if (state.mode != ReaderMode.scroll) {
      final item = _currentReaderItem();
      ref
          .read(readerViewModelProvider(widget.bookId).notifier)
          .saveReadingPosition(
            chapterIndex: item?.chapterIndex ?? state.currentChapterIndex,
            charOffset: item?.charOffset ?? 0,
            scrollPosition: 0,
          );
      return;
    }
    if (!_scrollController.hasClients) return;
    final visibleItem = _findTopVisibleItem();
    final item =
        visibleItem ??
        (state.items.isNotEmpty
            ? state.items[_lastVisibleItemIndex.clamp(
                0,
                state.items.length - 1,
              )]
            : null);
    if (item == null || state.book == null) return;

    ref
        .read(readerViewModelProvider(widget.bookId).notifier)
        .saveReadingPosition(
          chapterIndex: item.chapterIndex,
          charOffset: item.charOffset,
          scrollPosition: _scrollController.offset,
        );
  }

  /// 切换工具栏显示
  void _toggleOverlay() {
    setState(() {
      _showOverlay = !_showOverlay;
      if (_showOverlay) {
        _overlayAnimController.forward();
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      } else {
        _overlayAnimController.reverse();
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        _showSettings = false;
      }
    });
  }

  void _handleReaderTap(TapUpDetails details) {
    final size = MediaQuery.of(context).size;
    final position = details.localPosition;
    final col = (position.dx / (size.width / 3)).clamp(0, 2).floor();
    final row = (position.dy / (size.height / 3)).clamp(0, 2).floor();
    final zone = row * 3 + col;
    final state = ref.read(readerViewModelProvider(widget.bookId));
    final action = state.tapZoneActions.length == 9
        ? state.tapZoneActions[zone]
        : ReaderTapAction.defaultZones[zone];
    _runTapAction(action);
  }

  void _runTapAction(ReaderTapAction action) {
    switch (action) {
      case ReaderTapAction.previousPage:
        _turnPage(-1);
        break;
      case ReaderTapAction.nextPage:
        _turnPage(1);
        break;
      case ReaderTapAction.previousChapter:
        _turnChapter(-1);
        break;
      case ReaderTapAction.nextChapter:
        _turnChapter(1);
        break;
      case ReaderTapAction.menu:
        _toggleOverlay();
        break;
      case ReaderTapAction.disabled:
        break;
    }
  }

  Future<void> _turnPage(int direction) async {
    final state = ref.read(readerViewModelProvider(widget.bookId));
    if (state.mode == ReaderMode.scroll) {
      if (!_scrollController.hasClients) return;
      final viewport = _scrollController.position.viewportDimension;
      var max = _scrollController.position.maxScrollExtent;
      if (direction > 0 && (max - _scrollController.offset) < viewport * 0.25) {
        await ref
            .read(readerViewModelProvider(widget.bookId).notifier)
            .loadNextChapter();
      }
      if (!mounted || !_scrollController.hasClients) return;
      max = _scrollController.position.maxScrollExtent;
      final target = (_scrollController.offset + viewport * 0.82 * direction)
          .clamp(0.0, max);
      await _scrollController.animateTo(
        target.toDouble(),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      _saveReadingProgress();
      return;
    }

    final pages = _buildReaderPages(state, MediaQuery.of(context).size);
    if (!_pageController.hasClients || pages.isEmpty) return;
    final page = (_pageController.page ?? _lastPagedPageIndex).round();
    final targetPage = (page + direction).clamp(0, pages.length - 1).toInt();
    if (targetPage == page) return;
    await _pageController.animateToPage(
      targetPage,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _turnChapter(int direction) async {
    final state = ref.read(readerViewModelProvider(widget.bookId));
    if (state.chapters.isEmpty) return;
    final target = (state.currentChapterIndex + direction).clamp(
      0,
      state.chapters.length - 1,
    );
    if (target == state.currentChapterIndex) return;
    await _navigateToTarget(ReaderNavigationTarget(chapterIndex: target));
  }

  /// 切换设置面板
  void _toggleSettings() {
    setState(() {
      _showSettings = !_showSettings;
    });
  }

  /// 切换自动翻页
  void _toggleAutoScroll() {
    ref
        .read(readerViewModelProvider(widget.bookId).notifier)
        .toggleAutoScroll();
    final autoScroll = ref
        .read(readerViewModelProvider(widget.bookId))
        .autoScroll;
    if (autoScroll) {
      _startAutoScroll();
    }
  }

  Future<void> _showTocPanel(BuildContext context) async {
    setState(() {
      _showOverlay = false;
      _showSettings = false;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    });
    final target = await Navigator.of(context).push<ReaderNavigationTarget>(
      CupertinoPageRoute(
        builder: (context) => ReaderTocPage(bookId: widget.bookId),
        fullscreenDialog: true,
      ),
    );
    if (target != null) {
      await _navigateToTarget(target);
    }
  }

  Future<void> _navigateToTarget(ReaderNavigationTarget target) async {
    final vm = ref.read(readerViewModelProvider(widget.bookId).notifier);
    _itemKeys.clear();
    await vm.jumpToChapter(target.chapterIndex);
    if (!mounted) return;

    void jumpAfterLayout() {
      final state = ref.read(readerViewModelProvider(widget.bookId));
      if (state.mode != ReaderMode.scroll) {
        if (_pageController.hasClients) {
          final pages = _buildReaderPages(state, MediaQuery.of(context).size);
          final pageIndex = _pageIndexForTarget(pages, target);
          _lastPagedPageIndex = pageIndex;
          _pageController.jumpToPage(pageIndex);
        }
      } else {
        _scrollToTarget(target);
      }
      _saveReadingProgress();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      jumpAfterLayout();
      Future<void>.delayed(const Duration(milliseconds: 80), () {
        if (mounted) jumpAfterLayout();
      });
    });
  }

  /// 自动滚动
  void _startAutoScroll() {
    final state = ref.read(readerViewModelProvider(widget.bookId));
    if (!state.autoScroll || !_scrollController.hasClients) return;

    _scrollController
        .animateTo(
          _scrollController.offset + state.autoScrollSpeed,
          duration: const Duration(milliseconds: 16), // ~60fps
          curve: Curves.linear,
        )
        .then((_) {
          if (mounted &&
              ref.read(readerViewModelProvider(widget.bookId)).autoScroll) {
            _startAutoScroll();
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ReaderState>(readerViewModelProvider(widget.bookId), (
      previous,
      next,
    ) {
      if (!_didRestoreScrollPosition &&
          previous != null &&
          previous.items.isEmpty &&
          next.items.isNotEmpty &&
          next.book != null &&
          next.book!.currentPosition > 0) {
        _didRestoreScrollPosition = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scrollController.hasClients) return;
          final max = _scrollController.position.maxScrollExtent;
          _scrollController.jumpTo(
            next.book!.currentPosition.clamp(0, max).toDouble(),
          );
        });
      }
      if (previous != null &&
          previous.items.isEmpty &&
          next.items.isNotEmpty &&
          next.mode != ReaderMode.scroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageController.hasClients) {
            final pages = _buildReaderPages(next, MediaQuery.of(context).size);
            _pageController.jumpToPage(
              _pageIndexForChapter(pages, next.currentChapterIndex),
            );
          }
        });
      }
    });

    final readerState = ref.watch(readerViewModelProvider(widget.bookId));
    final brightness = MediaQuery.platformBrightnessOf(context);
    final bgColor = readerState.resolveBackgroundColor(brightness);
    final textColor = readerState.resolveTextColor(brightness);

    return CupertinoPageScaffold(
      backgroundColor: bgColor,
      child: Stack(
        children: [
          // 主阅读区域 — 无限滑动
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: _handleReaderTap,
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity != null &&
                  details.primaryVelocity! > 650) {
                _goBack();
              }
            },
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(boldText: false),
              child: _buildReadingContent(bgColor, textColor),
            ),
          ),

          // 顶部工具栏
          if (_showOverlay)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _overlayAnimation,
                child: _buildTopBar(context),
              ),
            ),

          // 底部工具栏
          if (_showOverlay)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _overlayAnimation,
                child: _buildBottomBar(context),
              ),
            ),

          // 设置面板
          if (_showSettings)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: ReaderSettingsPanel(bookId: widget.bookId)
                  .animate()
                  .slideY(
                    begin: 1.0,
                    end: 0,
                    duration: 300.ms,
                    curve: Curves.easeOutCubic,
                  ),
            ),

          // 加载中指示器
          if (readerState.isLoadingMore)
            const Positioned(
              bottom: 80,
              left: 0,
              right: 0,
              child: Center(child: CupertinoActivityIndicator()),
            ),
        ],
      ),
    );
  }

  /// 构建阅读内容 — 核心无限滑动
  Widget _buildReadingContent(Color bgColor, Color textColor) {
    final readerState = ref.watch(readerViewModelProvider(widget.bookId));

    if (readerState.isLoading && readerState.items.isEmpty) {
      return const Center(child: CupertinoActivityIndicator());
    }

    if (readerState.mode != ReaderMode.scroll) {
      return _buildPagedReadingContent(readerState, bgColor, textColor);
    }

    return CustomScrollView(
      controller: _scrollController,
      physics: const _AppleBouncingScrollPhysics(),
      slivers: [
        // 顶部留白
        SliverPadding(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + readerState.topPadding,
          ),
        ),

        // 章节内容列表（基于段落级）
        SliverList.builder(
          itemCount: readerState.items.length,
          itemBuilder: (context, index) {
            final item = readerState.items[index];
            return RepaintBoundary(
              key: _itemKeys.putIfAbsent(index, () => GlobalKey()),
              child: _buildReaderItemView(
                index,
                item,
                readerState,
                textColor,
                bgColor,
              ),
            );
          },
        ),

        // 底部留白
        SliverPadding(
          padding: EdgeInsets.only(
            bottom: readerState.footerHeight + readerState.bottomPadding,
          ),
        ),
      ],
    );
  }

  Widget _buildPagedReadingContent(
    ReaderState readerState,
    Color bgColor,
    Color textColor,
  ) {
    final pages = _buildReaderPages(readerState, MediaQuery.of(context).size);
    if (pages.isEmpty) {
      return const Center(child: CupertinoActivityIndicator());
    }
    var currentPage = _lastPagedPageIndex.clamp(0, pages.length - 1).toInt();
    final currentPageHasChapter = pages[currentPage].entries.any(
      (entry) => entry.item.chapterIndex == readerState.currentChapterIndex,
    );
    if (!currentPageHasChapter) {
      currentPage = _pageIndexForChapter(
        pages,
        readerState.currentChapterIndex,
      );
    }

    if (_pageController.hasClients &&
        (_pageController.page?.round() ?? _lastPagedPageIndex) != currentPage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          _pageController.jumpToPage(currentPage);
        }
      });
    }

    return PageView.builder(
      controller: _pageController,
      physics: const PageScrollPhysics(parent: BouncingScrollPhysics()),
      itemCount: pages.length,
      onPageChanged: (index) {
        _lastPagedPageIndex = index;
        final first = pages[index].firstReadableItem;
        if (first != null) {
          _lastVisibleItemIndex = first.itemIndex;
          ref
              .read(readerViewModelProvider(widget.bookId).notifier)
              .updateVisibleChapter(first.item.chapterIndex);
        }
        if (index >= pages.length - 2 && !readerState.isLoadingMore) {
          ref
              .read(readerViewModelProvider(widget.bookId).notifier)
              .loadNextChapter();
        }
        _saveReadingProgress();
      },
      itemBuilder: (context, pageIndex) {
        final page = pages[pageIndex];
        return Padding(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + readerState.topPadding,
            bottom: readerState.footerHeight + readerState.bottomPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: page.entries.map((entry) {
              return RepaintBoundary(
                key: _itemKeys.putIfAbsent(entry.itemIndex, () => GlobalKey()),
                child: _buildReaderItemView(
                  entry.itemIndex,
                  entry.item,
                  readerState,
                  textColor,
                  bgColor,
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  List<_ReaderPageData> _buildReaderPages(ReaderState state, Size size) {
    if (state.items.isEmpty) return const [];
    final width = (size.width - state.pagePadding * 2).clamp(80.0, size.width);
    final height =
        size.height -
        MediaQuery.of(context).padding.top -
        MediaQuery.of(context).padding.bottom -
        state.topPadding -
        state.bottomPadding -
        state.footerHeight;
    final maxHeight = height.clamp(220.0, size.height);
    final pages = <_ReaderPageData>[];
    var current = <_ReaderPageEntry>[];
    var usedHeight = 0.0;

    for (var i = 0; i < state.items.length; i++) {
      final item = state.items[i];
      final itemHeight = _estimateItemHeight(item, state, width);
      if (current.isNotEmpty && usedHeight + itemHeight > maxHeight) {
        pages.add(_ReaderPageData(List.unmodifiable(current)));
        current = <_ReaderPageEntry>[];
        usedHeight = 0;
      }
      current.add(_ReaderPageEntry(i, item));
      usedHeight += itemHeight;
    }
    if (current.isNotEmpty) {
      pages.add(_ReaderPageData(List.unmodifiable(current)));
    }
    return pages;
  }

  double _estimateItemHeight(ReaderItem item, ReaderState state, double width) {
    if (item.isDivider) return 82;
    if (item.isTitle) {
      final titleSize = (state.fontSize + 7).clamp(24.0, 38.0);
      final metaSize = (state.fontSize - 6).clamp(11.0, 14.0);
      final titlePainter = TextPainter(
        text: TextSpan(
          text: item.text,
          style: _readerTextStyle(
            state,
            state.resolvedTextColor,
            fontSize: titleSize,
            fontWeightIndex: 2,
            height: 1.22,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width);
      return state.topPadding +
          AppDimensions.paddingLarge +
          6 +
          metaSize * 1.2 +
          16 +
          titlePainter.height +
          state.titleSpacing +
          18;
    }

    final displayText = state.paragraphIndent > 0
        ? '${List.filled(state.paragraphIndent, '\u3000').join()}${item.text}'
        : item.text;
    final painter = TextPainter(
      text: TextSpan(
        text: displayText,
        style: _readerTextStyle(
          state,
          state.resolvedTextColor,
          fontWeightIndex: state.fontWeightIndex,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: state.isJustify ? TextAlign.justify : TextAlign.left,
    )..layout(maxWidth: width);
    final isFirstParagraph = item.paragraphIndex == 0;
    final isShortLine = item.text.length <= 22;
    final paragraphTop = isFirstParagraph
        ? 2.0
        : (isShortLine ? state.paragraphSpacing * 0.75 : 0.0);
    return painter.height + paragraphTop + state.paragraphSpacing;
  }

  int _pageIndexForChapter(List<_ReaderPageData> pages, int chapterIndex) {
    if (pages.isEmpty) return 0;
    final index = pages.indexWhere(
      (page) =>
          page.entries.any((entry) => entry.item.chapterIndex == chapterIndex),
    );
    return index < 0
        ? _lastPagedPageIndex.clamp(0, pages.length - 1).toInt()
        : index;
  }

  int _pageIndexForTarget(
    List<_ReaderPageData> pages,
    ReaderNavigationTarget target,
  ) {
    if (pages.isEmpty) return 0;
    final index = pages.indexWhere(
      (page) => page.entries.any(
        (entry) =>
            entry.item.chapterIndex == target.chapterIndex &&
            entry.item.charOffset >= target.charOffset &&
            !entry.item.isDivider,
      ),
    );
    if (index >= 0) return index;
    return _pageIndexForChapter(pages, target.chapterIndex);
  }

  ReaderItem? _findTopVisibleItem() {
    if (!_scrollController.hasClients) return null;
    final state = ref.read(readerViewModelProvider(widget.bookId));
    if (state.items.isEmpty) return null;

    final topInset = MediaQuery.of(context).padding.top + 8;
    var bestIndex = _lastVisibleItemIndex.clamp(0, state.items.length - 1);
    var bestDistance = double.infinity;

    for (final entry in _itemKeys.entries) {
      if (entry.key >= state.items.length) continue;
      final keyContext = entry.value.currentContext;
      if (keyContext == null) continue;
      final box = keyContext.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      if (bottom < topInset) continue;
      final distance = (top - topInset).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = entry.key;
      }
    }

    _lastVisibleItemIndex = bestIndex;
    return state.items[bestIndex];
  }

  ReaderItem? _currentReaderItem() {
    final state = ref.read(readerViewModelProvider(widget.bookId));
    if (state.items.isEmpty) return null;
    if (state.mode == ReaderMode.scroll) {
      return _findTopVisibleItem() ??
          state.items[_lastVisibleItemIndex.clamp(0, state.items.length - 1)];
    }
    final pages = _buildReaderPages(state, MediaQuery.of(context).size);
    if (pages.isNotEmpty) {
      final page =
          pages[_lastPagedPageIndex.clamp(0, pages.length - 1).toInt()];
      final entry = page.firstReadableItem;
      if (entry != null) return entry.item;
    }
    return state.items.firstWhere(
      (item) => !item.isDivider,
      orElse: () => state.items.first,
    );
  }

  Bookmark? _currentBookmark() {
    final state = ref.watch(readerViewModelProvider(widget.bookId));
    final item = _currentReaderItem();
    if (item == null) return null;
    for (final bookmark in state.bookmarks) {
      if (bookmark.chapterIndex == item.chapterIndex &&
          (bookmark.position - item.charOffset).abs() <= 80) {
        return bookmark;
      }
    }
    return null;
  }

  Future<void> _toggleCurrentBookmark() async {
    final state = ref.read(readerViewModelProvider(widget.bookId));
    if (state.book == null || state.chapters.isEmpty) return;
    final vm = ref.read(readerViewModelProvider(widget.bookId).notifier);
    final item = _currentReaderItem();
    if (item == null) return;
    Bookmark? existing;
    for (final bookmark in state.bookmarks) {
      if (bookmark.chapterIndex == item.chapterIndex &&
          (bookmark.position - item.charOffset).abs() <= 80) {
        existing = bookmark;
        break;
      }
    }

    if (existing != null) {
      await vm.removeBookmark(existing.id);
      return;
    }

    final chapterIndex = item.chapterIndex.clamp(0, state.chapters.length - 1);
    await vm.addBookmark(
      Bookmark(
        bookId: state.book!.id,
        chapterIndex: chapterIndex,
        position: item.charOffset,
        selectedText: item.isTitle ? null : item.text,
        chapterTitle: state.chapters[chapterIndex].title,
        createdAt: DateTime.now(),
      ),
    );
  }

  void _scrollToTarget(ReaderNavigationTarget target) {
    final state = ref.read(readerViewModelProvider(widget.bookId));
    if (!_scrollController.hasClients || state.items.isEmpty) return;

    var targetIndex = state.items.indexWhere(
      (item) =>
          item.chapterIndex == target.chapterIndex &&
          item.charOffset >= target.charOffset &&
          !item.isDivider,
    );
    if (targetIndex < 0) {
      targetIndex = state.items.indexWhere(
        (item) => item.chapterIndex == target.chapterIndex,
      );
    }
    if (targetIndex < 0) return;

    final keyContext = _itemKeys[targetIndex]?.currentContext;
    if (target.charOffset == 0 &&
        state.items[targetIndex].isTitle &&
        _scrollController.hasClients) {
      _scrollController.jumpTo(0);
    } else if (keyContext != null) {
      Scrollable.ensureVisible(
        keyContext,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0,
      );
    }
    _lastVisibleItemIndex = targetIndex;
  }

  /// 构建单个段落或标题
  Widget _buildReaderItemView(
    int index,
    ReaderItem item,
    ReaderState state,
    Color textColor,
    Color bgColor,
  ) {
    // 映射字体粗细
    FontWeight getFontWeight(int index) {
      return _fontWeight(index);
    }

    double getFontWeightValue(int index) {
      return _fontWeightValue(index);
    }

    // 分割线
    if (item.isDivider) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Container(
            width: 60,
            height: 1,
            color: textColor.withOpacity(0.1),
          ),
        ),
      );
    }

    // 标题
    if (item.isTitle) {
      final titleSize = (state.fontSize + 7).clamp(24.0, 38.0);
      final metaSize = (state.fontSize - 6).clamp(11.0, 14.0);
      return Padding(
        padding: EdgeInsets.only(
          left: state.pagePadding,
          right: state.pagePadding,
          top: state.topPadding + AppDimensions.paddingLarge + 6,
          bottom: state.titleSpacing + 18,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '第 ${item.chapterIndex + 1} 章',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: metaSize,
                fontWeight: FontWeight.w600,
                fontVariations: const [FontVariation('wght', 600)],
                color: textColor.withOpacity(0.7),
                height: 1.2,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              item.text,
              style: TextStyle(
                fontSize: titleSize,
                fontWeight: FontWeight.w700,
                fontVariations: const [FontVariation('wght', 700)],
                fontFamilyFallback: const [
                  'PingFang SC',
                  'Heiti SC',
                  'Noto Sans CJK SC',
                  'Microsoft YaHei',
                ],
                color: textColor,
                height: 1.22,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      );
    }

    // TTS 高亮色
    final isPlayingThis =
        state.isPlayingTts && state.ttsPlayingItemIndex == index;
    final isFirstParagraph = item.paragraphIndex == 0;
    final isShortLine = item.text.length <= 22;
    final paragraphTop = isFirstParagraph
        ? 2.0
        : (isShortLine ? state.paragraphSpacing * 0.75 : 0.0);

    final finalTextColor = isPlayingThis
        ? AppColors.primaryBlue
        : textColor.withOpacity(0.92);
    final fontWeight = isPlayingThis
        ? FontWeight.w600
        : getFontWeight(state.fontWeightIndex);

    final displayText = state.paragraphIndent > 0
        ? '${List.filled(state.paragraphIndent, '\u3000').join()}${item.text}'
        : item.text;

    // 普通正文段落
    return Padding(
      padding: EdgeInsets.only(
        left: state.pagePadding,
        right: state.pagePadding,
        top: paragraphTop,
        bottom: state.paragraphSpacing,
      ),
      child: Text(
        displayText,
        textAlign: state.isJustify ? TextAlign.justify : TextAlign.left,
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: false,
          applyHeightToLastDescent: true,
        ),
        style: TextStyle(
          fontSize: state.fontSize,
          fontFamily: state.fontFamily == 'system' ? null : state.fontFamily,
          fontFamilyFallback: const [
            'PingFang SC',
            'Heiti SC',
            'Noto Sans CJK SC',
            'Microsoft YaHei',
          ],
          fontWeight: fontWeight,
          fontVariations: [
            FontVariation('wght', getFontWeightValue(state.fontWeightIndex)),
          ],
          color: finalTextColor,
          height: state.lineHeight,
          letterSpacing: state.letterSpacing,
          leadingDistribution: TextLeadingDistribution.even,
        ),
      ),
    );
  }

  TextStyle _readerTextStyle(
    ReaderState state,
    Color textColor, {
    double? fontSize,
    int? fontWeightIndex,
    double? height,
  }) {
    final index = fontWeightIndex ?? state.fontWeightIndex;
    return TextStyle(
      fontSize: fontSize ?? state.fontSize,
      fontFamily: state.fontFamily == 'system' ? null : state.fontFamily,
      fontFamilyFallback: const [
        'PingFang SC',
        'Heiti SC',
        'Noto Sans CJK SC',
        'Microsoft YaHei',
      ],
      fontWeight: _fontWeight(index),
      fontVariations: [FontVariation('wght', _fontWeightValue(index))],
      color: textColor,
      height: height ?? state.lineHeight,
      letterSpacing: state.letterSpacing,
      leadingDistribution: TextLeadingDistribution.even,
    );
  }

  FontWeight _fontWeight(int index) {
    if (index == 1) return FontWeight.w600;
    if (index == 2) return FontWeight.w900;
    return FontWeight.w300;
  }

  double _fontWeightValue(int index) {
    if (index == 1) return 600;
    if (index == 2) return 900;
    return 300;
  }

  /// 顶部工具栏
  Widget _buildTopBar(BuildContext context) {
    final pageContext = context;
    final readerState = ref.watch(readerViewModelProvider(widget.bookId));
    final background = readerState.resolveBackgroundColor(
      MediaQuery.platformBrightnessOf(context),
    );
    final isDark = background.computeLuminance() < 0.45;
    final panelColor = isDark
        ? const Color(0xDD1C1C1E)
        : const Color(0xEEF8F8F8);
    final foreground = isDark ? CupertinoColors.white : CupertinoColors.black;
    final secondary = foreground.withOpacity(0.62);
    final currentChapter =
        readerState.currentChapterIndex >= 0 &&
            readerState.currentChapterIndex < readerState.chapters.length
        ? readerState.chapters[readerState.currentChapterIndex].title
        : '';
    final currentBookmark = _currentBookmark();

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: panelColor,
            border: Border(
              bottom: BorderSide(
                color: foreground.withOpacity(0.08),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.paddingMedium,
                vertical: AppDimensions.paddingSmall,
              ),
              child: Row(
                children: [
                  // 返回按钮
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _goBack,
                    child: Icon(
                      CupertinoIcons.back,
                      color: foreground,
                      size: 28,
                    ),
                  ),
                  // 书名
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          readerState.book?.title ?? '加载中...',
                          style: TextStyle(
                            color: foreground,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (currentChapter.isNotEmpty)
                          Text(
                            '第 ${readerState.currentChapterIndex + 1} 章 · $currentChapter',
                            style: TextStyle(
                              color: secondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minSize: 36,
                    onPressed: _toggleCurrentBookmark,
                    child: Icon(
                      currentBookmark == null
                          ? CupertinoIcons.bookmark
                          : CupertinoIcons.bookmark_fill,
                      color: currentBookmark == null
                          ? foreground
                          : AppColors.primaryPurple,
                      size: 22,
                    ),
                  ),
                  // 更多选项
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      showCupertinoModalPopup(
                        context: context,
                        builder: (context) => CupertinoActionSheet(
                          title: Text(
                            ref
                                    .read(
                                      readerViewModelProvider(widget.bookId),
                                    )
                                    .book
                                    ?.title ??
                                '选项',
                          ),
                          actions: [
                            CupertinoActionSheetAction(
                              onPressed: () {
                                Navigator.pop(context);
                                _toggleSettings();
                              },
                              child: const Text('阅读设置'),
                            ),
                            CupertinoActionSheetAction(
                              onPressed: () {
                                Navigator.pop(context);
                                _showContentFormatSettings(pageContext);
                              },
                              child: const Text('文本内容格式'),
                            ),
                            CupertinoActionSheetAction(
                              onPressed: () {
                                Navigator.pop(context);
                                _showSourceSwitcher(pageContext);
                              },
                              child: const Text('换源'),
                            ),
                            CupertinoActionSheetAction(
                              onPressed: () {
                                Navigator.pop(context);
                                _showBookDetails(pageContext);
                              },
                              child: const Text('书籍详情'),
                            ),
                          ],
                          cancelButton: CupertinoActionSheetAction(
                            isDefaultAction: true,
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            child: const Text('取消'),
                          ),
                        ),
                      );
                    },
                    child: Icon(
                      CupertinoIcons.ellipsis,
                      color: foreground,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/bookshelf');
    }
  }

  void _showBookDetails(BuildContext pageContext) {
    final state = ref.read(readerViewModelProvider(widget.bookId));
    final book = state.book;
    if (book == null) return;
    Navigator.of(pageContext).push(
      CupertinoPageRoute(
        builder: (context) => ReaderBookDetailsPage(bookId: widget.bookId),
      ),
    );
  }

  void _showContentFormatSettings(BuildContext pageContext) {
    final state = ref.read(readerViewModelProvider(widget.bookId));
    showCupertinoModalPopup(
      context: pageContext,
      builder: (context) => CupertinoActionSheet(
        title: const Text('文本内容格式'),
        message: const Text(
          '这里处理阅读正文的显示格式。净化规则用于删除广告、站点尾巴、乱码片段；排版项会立即影响当前阅读页。',
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _toggleSettings();
            },
            child: const Text('打开排版设置'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              context.push('/purify');
            },
            child: const Text('净化规则'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              ref
                  .read(readerViewModelProvider(widget.bookId).notifier)
                  .setJustify(!state.isJustify);
            },
            child: Text(state.isJustify ? '关闭两端对齐' : '开启两端对齐'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  Future<void> _showSourceSwitcher(BuildContext pageContext) async {
    final state = ref.read(readerViewModelProvider(widget.bookId));
    final book = state.book;
    if (book == null || !book.isFromSource) {
      _showReaderMessage(pageContext, '本地书籍暂不需要换源');
      return;
    }

    final vm = ref.read(readerViewModelProvider(widget.bookId).notifier);
    showCupertinoDialog<void>(
      context: pageContext,
      barrierDismissible: false,
      builder: (context) => const CupertinoAlertDialog(
        title: Text('正在搜索可换书源'),
        content: Padding(
          padding: EdgeInsets.only(top: 14),
          child: CupertinoActivityIndicator(),
        ),
      ),
    );

    final candidates = <_SourceSwitchCandidate>[];
    try {
      final sources = await vm.getEnabledSwitchSources();
      for (final source in sources.take(40)) {
        try {
          final books = await LegadoParser.searchBooks(
            source,
            book.title,
          ).timeout(const Duration(seconds: 5));
          final matched = _pickBestSourceBook(book, books);
          if (matched != null) {
            candidates.add(_SourceSwitchCandidate(source, matched));
            if (candidates.length >= 12) break;
          }
        } catch (_) {
          continue;
        }
      }
    } finally {
      if (mounted && Navigator.of(pageContext, rootNavigator: true).canPop()) {
        Navigator.of(pageContext, rootNavigator: true).pop();
      }
    }

    if (!mounted) return;
    if (candidates.isEmpty) {
      _showReaderMessage(pageContext, '没有搜索到可用换源结果');
      return;
    }

    showCupertinoModalPopup<void>(
      context: pageContext,
      builder: (context) => CupertinoActionSheet(
        title: const Text('换源'),
        message: const Text('选择后会替换当前书籍来源，并尽量定位到同名章节。'),
        actions: candidates.map((candidate) {
          return CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await vm.switchBookSource(candidate.source, candidate.book);
                if (!mounted) return;
                _itemKeys.clear();
                _lastVisibleItemIndex = 0;
                _lastPagedPageIndex = 0;
                _showReaderMessage(pageContext, '换源成功');
              } catch (e) {
                if (!mounted) return;
                _showReaderMessage(pageContext, e.toString());
              }
            },
            child: Text(
              '${candidate.source.bookSourceName}\n${candidate.book.title} · ${candidate.book.author}',
            ),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  Book? _pickBestSourceBook(Book current, List<Book> books) {
    if (books.isEmpty) return null;
    final title = _normalizeSwitchText(current.title);
    final author = _normalizeSwitchText(current.author);
    for (final book in books) {
      if (_normalizeSwitchText(book.title) == title &&
          (author.isEmpty || _normalizeSwitchText(book.author) == author)) {
        return book;
      }
    }
    for (final book in books) {
      final value = _normalizeSwitchText(book.title);
      if (value == title || value.contains(title) || title.contains(value)) {
        return book;
      }
    }
    return books.first;
  }

  String _normalizeSwitchText(String value) {
    return value.toLowerCase().replaceAll(
      RegExp(r'[\s\p{P}\p{S}]+', unicode: true),
      '',
    );
  }

  void _showReaderMessage(BuildContext pageContext, String message) {
    showCupertinoDialog<void>(
      context: pageContext,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('提示'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 底部工具栏
  Widget _buildBottomBar(BuildContext context) {
    final readerState = ref.watch(readerViewModelProvider(widget.bookId));
    final progress = readerState.chapters.isNotEmpty
        ? (readerState.currentChapterIndex + 1) / readerState.chapters.length
        : 0.0;
    final background = readerState.resolveBackgroundColor(
      MediaQuery.platformBrightnessOf(context),
    );
    final isDark = background.computeLuminance() < 0.45;
    final panelColor = isDark
        ? const Color(0xDD1C1C1E)
        : const Color(0xEEF8F8F8);
    final foreground = isDark ? CupertinoColors.white : CupertinoColors.black;
    final secondary = foreground.withOpacity(0.62);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: panelColor,
            border: Border(
              top: BorderSide(color: foreground.withOpacity(0.08), width: 0.5),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 进度条
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.paddingLarge,
                  ),
                  child: Row(
                    children: [
                      Text(
                        '第 ${readerState.currentChapterIndex + 1} 章',
                        style: TextStyle(color: secondary, fontSize: 12),
                      ),
                      Expanded(
                        child: CupertinoSlider(
                          value: progress.clamp(0.0, 1.0),
                          onChanged: (value) {
                            final state = ref.read(
                              readerViewModelProvider(widget.bookId),
                            );
                            if (state.chapters.isEmpty) return;
                            final chapterIndex =
                                (value * (state.chapters.length - 1)).round();
                            _navigateToTarget(
                              ReaderNavigationTarget(
                                chapterIndex: chapterIndex,
                              ),
                            );
                          },
                          activeColor: AppColors.primaryBlue,
                        ),
                      ),
                      Text(
                        '${(progress * 100).toInt()}%',
                        style: TextStyle(color: secondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // 工具栏按钮
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.paddingLarge,
                    vertical: AppDimensions.paddingSmall,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildToolButton(
                        icon: CupertinoIcons.list_bullet,
                        label: '目录',
                        color: foreground,
                        onTap: () {
                          _showTocPanel(context);
                        },
                      ),
                      _buildToolButton(
                        icon: CupertinoIcons.backward_end,
                        label: '上一章',
                        color: foreground,
                        onTap: () {
                          _turnChapter(-1);
                        },
                      ),
                      _buildToolButton(
                        icon: CupertinoIcons.textformat_size,
                        label: '字体',
                        color: foreground,
                        onTap: _toggleSettings,
                      ),
                      _buildToolButton(
                        icon: CupertinoIcons.forward_end,
                        label: '下一章',
                        color: foreground,
                        onTap: () {
                          _turnChapter(1);
                        },
                      ),
                      _buildToolButton(
                        icon: readerState.isPlayingTts
                            ? CupertinoIcons.stop
                            : CupertinoIcons.speaker_2,
                        label: readerState.isPlayingTts ? '停止' : '朗读',
                        color: foreground,
                        onTap: () {
                          ref
                              .read(
                                readerViewModelProvider(widget.bookId).notifier,
                              )
                              .toggleTts();
                        },
                      ),
                      _buildToolButton(
                        icon: readerState.autoScroll
                            ? CupertinoIcons.pause
                            : CupertinoIcons.play,
                        label: readerState.autoScroll ? '暂停' : '自动',
                        color: foreground,
                        onTap: _toggleAutoScroll,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 工具栏按钮
  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onPressed: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: color, fontSize: 11)),
        ],
      ),
    );
  }

  // (Removed legacy settings panel code)
}

/// Apple 风格弹性滑动物理 — 120Hz 优化
class _ReaderPageEntry {
  final int itemIndex;
  final ReaderItem item;

  const _ReaderPageEntry(this.itemIndex, this.item);
}

class _ReaderPageData {
  final List<_ReaderPageEntry> entries;

  const _ReaderPageData(this.entries);

  _ReaderPageEntry? get firstReadableItem {
    for (final entry in entries) {
      if (!entry.item.isDivider) return entry;
    }
    return entries.isEmpty ? null : entries.first;
  }
}

class _SourceSwitchCandidate {
  final BookSource source;
  final Book book;

  const _SourceSwitchCandidate(this.source, this.book);
}

class _AppleBouncingScrollPhysics extends BouncingScrollPhysics {
  const _AppleBouncingScrollPhysics({super.parent});

  @override
  _AppleBouncingScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _AppleBouncingScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  SpringDescription get spring =>
      const SpringDescription(mass: 0.5, stiffness: 100.0, damping: 15.0);

  @override
  double get dragStartDistanceMotionThreshold => 3.5;
}
