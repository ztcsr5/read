import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/book.dart';
import '../../../data/models/book_source.dart';
import '../../../data/models/rss_source.dart';
import '../../../data/parsers/legado_parser.dart';
import '../../../data/parsers/legado/legado_request_builder.dart';
import '../../../data/repositories/book_repository.dart';
import '../../../data/repositories/source_repository.dart';

final exploreViewModelProvider =
    StateNotifierProvider.autoDispose<ExploreViewModel, ExploreState>((ref) {
      final repo = ref.watch(bookRepositoryProvider);
      final sourceRepo = ref.watch(sourceRepositoryProvider);
      return ExploreViewModel(repo, sourceRepo);
    });

enum SearchMatchMode { fuzzy, precise }

class ExploreState {
  final bool isSearching;
  final List<Book> searchResults;
  final String error;
  final List<RssSource> rssSources;
  final int selectedTab;
  final SearchMatchMode searchMatchMode;
  final BookSource? verificationSource;
  final String verificationUrl;
  final String lastQuery;

  ExploreState({
    this.isSearching = false,
    this.searchResults = const [],
    this.error = '',
    this.rssSources = const [],
    this.selectedTab = 0,
    this.searchMatchMode = SearchMatchMode.fuzzy,
    this.verificationSource,
    this.verificationUrl = '',
    this.lastQuery = '',
  });

  ExploreState copyWith({
    bool? isSearching,
    List<Book>? searchResults,
    String? error,
    List<RssSource>? rssSources,
    int? selectedTab,
    SearchMatchMode? searchMatchMode,
    BookSource? verificationSource,
    String? verificationUrl,
    String? lastQuery,
    bool clearVerificationSource = false,
  }) {
    return ExploreState(
      isSearching: isSearching ?? this.isSearching,
      searchResults: searchResults ?? this.searchResults,
      error: error ?? this.error,
      rssSources: rssSources ?? this.rssSources,
      selectedTab: selectedTab ?? this.selectedTab,
      searchMatchMode: searchMatchMode ?? this.searchMatchMode,
      verificationSource: clearVerificationSource
          ? null
          : verificationSource ?? this.verificationSource,
      verificationUrl: clearVerificationSource
          ? ''
          : verificationUrl ?? this.verificationUrl,
      lastQuery: lastQuery ?? this.lastQuery,
    );
  }
}

class ExploreViewModel extends StateNotifier<ExploreState> {
  final BookRepository _repository;
  final SourceRepository _sourceRepository;
  CancelToken? _searchCancelToken;

  ExploreViewModel(this._repository, this._sourceRepository)
    : super(ExploreState()) {
    loadRssSources();
  }

  @override
  void dispose() {
    _searchCancelToken?.cancel('User interrupted source switching');
    super.dispose();
  }

  void cancelSearch() {
    _searchCancelToken?.cancel('User interrupted source switching');
    _searchCancelToken = null;
    state = state.copyWith(isSearching: false);
  }

  void setTab(int index) {
    state = state.copyWith(selectedTab: index);
    if (index == 1) {
      loadRssSources();
    }
  }

  void setSearchMatchMode(SearchMatchMode mode) {
    state = state.copyWith(searchMatchMode: mode);
  }

  Future<void> loadRssSources() async {
    final sources = await _sourceRepository.getEnabledRssSources();
    state = state.copyWith(rssSources: sources);
  }

  Future<void> search(String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty) return;

    _searchCancelToken?.cancel('User interrupted source switching');
    _searchCancelToken = CancelToken();
    final currentCancelToken = _searchCancelToken!;

    state = state.copyWith(
      isSearching: true,
      error: '',
      searchResults: [],
      lastQuery: query,
      clearVerificationSource: true,
    );

    try {
      final sources = _searchableSources(await _repository.getAllBookSources());
      if (sources.isEmpty) {
        state = state.copyWith(
          isSearching: false,
          error: '没有可用书源，请先在设置里导入并启用书源',
        );
        return;
      }

      final allResults = <Book>[];
      final seen = <String>{};
      BookSource? verificationSource;
      String verificationUrl = '';
      var tried = 0;
      final mode = state.searchMatchMode;
      final maxResults = mode == SearchMatchMode.precise ? 120 : 240;

      for (var start = 0; start < sources.length; start += 6) {
        if (currentCancelToken.isCancelled) return;
        final batch = sources.skip(start).take(6).toList();
        tried += batch.length;
        final resultsLists = await Future.wait(
          batch.map((source) async {
            try {
              if (currentCancelToken.isCancelled) return <Book>[];
              final books = await LegadoParser.searchBooks(
                source,
                query,
                cancelToken: currentCancelToken,
              ).timeout(const Duration(seconds: 9));
              if (currentCancelToken.isCancelled) return <Book>[];
              return books
                  .where((book) => _matchesSearchMode(book, query, mode))
                  .map((book) {
                    book
                      ..isFromSource = true
                      ..sourceUrl = source.id.toString();
                    return book;
                  })
                  .toList();
            } catch (e) {
              if (e is DioException && e.type == DioExceptionType.cancel) {
                return <Book>[];
              }
              if (verificationSource == null && _shouldOfferVerification(e)) {
                verificationSource = source;
                verificationUrl = e is LegadoVerificationRequiredException
                    ? e.url
                    : _sourceDefaultUrl(source);
              }
              print('Search Error from ${source.bookSourceName}: $e');
              return <Book>[];
            }
          }),
        );

        if (currentCancelToken.isCancelled) return;

        for (final list in resultsLists) {
          for (final book in list) {
            if (book.title.trim().isEmpty || book.title == '未知') continue;
            final key = [
              book.title.trim().toLowerCase(),
              book.author.trim().toLowerCase(),
              book.sourceUrl ?? '',
              book.filePath,
            ].join('|');
            if (seen.add(key)) allResults.add(book);
            if (allResults.length >= maxResults) break;
          }
          if (allResults.length >= maxResults) break;
        }
        if (allResults.length >= maxResults) break;
      }

      if (currentCancelToken.isCancelled) return;

      // 搜索双重优先排序算法
      allResults.sort((a, b) {
        // 第一维优先权重（精准匹配）
        final aExact = a.title.trim() == query;
        final bExact = b.title.trim() == query;
        if (aExact != bExact) {
          return aExact ? -1 : 1;
        }

        // 第二维优先权重（内容完整度）：章节数或字数降序
        // 优先比较章节数 totalChapters 降序
        if (a.totalChapters != b.totalChapters) {
          return b.totalChapters.compareTo(a.totalChapters);
        }

        // 其次比较字数 (用 fileSize 存储) 降序
        return b.fileSize.compareTo(a.fileSize);
      });

      state = state.copyWith(
        isSearching: false,
        searchResults: allResults,
        verificationSource: allResults.isEmpty ? verificationSource : null,
        verificationUrl: allResults.isEmpty ? verificationUrl : '',
        clearVerificationSource: allResults.isNotEmpty,
        error: allResults.isEmpty ? '已搜索 $tried 个启用书源，暂时没有搜到书籍' : '',
      );
    } catch (e) {
      state = state.copyWith(isSearching: false, error: '搜索失败: $e');
    }
  }

  Future<int> addToBookshelf(Book book) async {
    var target = book
      ..isFromSource = true
      ..isFavorite = true
      ..lastReadTime = DateTime.now();

    final source = await _sourceForBook(target);
    if (source != null) {
      try {
        target = await LegadoParser.parseBookInfo(source, target);
        target
          ..isFromSource = true
          ..sourceUrl = source.id.toString()
          ..lastReadTime = DateTime.now();
      } catch (_) {
        // 搜索结果本身也可以直接加入书架。
      }
    }

    final id = await _repository.saveBook(target);
    target.id = id;

    if (source != null) {
      try {
        final chapters = await LegadoParser.getChapterList(
          source,
          target,
        ).timeout(const Duration(seconds: 12));
        if (chapters.isNotEmpty) {
          for (final chapter in chapters) {
            chapter.bookId = id;
          }
          await _repository.deleteChaptersForBook(id);
          await _repository.saveChapters(chapters);
          target.totalChapters = chapters.length;
          await _repository.saveBook(target);
        }
      } catch (_) {
        // 目录失败不阻止收藏，阅读页会继续尝试解析。
      }
    }

    return id;
  }

  List<BookSource> _searchableSources(List<BookSource> sources) {
    return sources
        .where(
          (source) =>
              source.enabled &&
              (source.searchUrl?.trim().isNotEmpty ?? false) &&
              (source.ruleSearch?.trim().isNotEmpty ?? false),
        )
        .toList()
      ..sort((a, b) {
        final weight = b.weight.compareTo(a.weight);
        if (weight != 0) return weight;
        return a.bookSourceName.compareTo(b.bookSourceName);
      });
  }

  bool _shouldOfferVerification(Object error) =>
      error is LegadoVerificationRequiredException;

  String _sourceDefaultUrl(BookSource source) {
    final base = LegadoRequestBuilder.cleanBaseUrl(source.bookSourceUrl);
    if (base.startsWith('http')) return base;
    return 'https://$base';
  }

  Future<BookSource?> _sourceForBook(Book book) async {
    final id = int.tryParse(book.sourceUrl ?? '');
    final sources = await _repository.getAllBookSources();
    if (id != null) {
      for (final source in sources) {
        if (source.id == id) return source;
      }
    }
    if (book.filePath.isNotEmpty) {
      for (final source in sources) {
        final base = source.bookSourceUrl.split('##').first;
        if (book.filePath.startsWith(base)) return source;
      }
    }
    return null;
  }

  bool _matchesSearchMode(Book book, String query, SearchMatchMode mode) {
    if (mode == SearchMatchMode.fuzzy) return true;
    final q = _normalizeText(query);
    if (q.isEmpty) return true;
    final title = _normalizeText(book.title);
    final author = _normalizeText(book.author);
    return title == q || title.startsWith(q) || author == q;
  }

  String _normalizeText(String value) {
    return value.toLowerCase().replaceAll(
      RegExp(r'[\s\p{P}\p{S}]+', unicode: true),
      '',
    );
  }
}
