import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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

enum SearchResultFilterScope { all, title, author, source }

@visibleForTesting
List<Book> filterExploreSearchResults(
  List<Book> books,
  String filter,
  SearchResultFilterScope scope,
) {
  final q = _normalizeExploreText(filter);
  if (q.isEmpty) return books;
  return books.where((book) {
    final values = _exploreFilterValues(book, scope).map(_normalizeExploreText);
    return values.any((value) => value.contains(q));
  }).toList();
}

List<String> _exploreFilterValues(Book book, SearchResultFilterScope scope) {
  return switch (scope) {
    SearchResultFilterScope.title => [book.title],
    SearchResultFilterScope.author => [book.author],
    SearchResultFilterScope.source => [
      book.filePath,
      ...book.tags.where(
        (tag) => tag.startsWith('source:') || tag.startsWith('group:'),
      ),
    ],
    SearchResultFilterScope.all => [
      book.title,
      book.author,
      book.filePath,
      ...book.tags,
    ],
  };
}

String _normalizeExploreText(String value) {
  return value.toLowerCase().replaceAll(
    RegExp(r'[\s\p{P}\p{S}]+', unicode: true),
    '',
  );
}

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
  final String resultFilter;
  final SearchResultFilterScope resultFilterScope;
  final int searchTotalSources;
  final int searchedSources;
  final int matchedSources;

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
    this.resultFilter = '',
    this.resultFilterScope = SearchResultFilterScope.all,
    this.searchTotalSources = 0,
    this.searchedSources = 0,
    this.matchedSources = 0,
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
    String? resultFilter,
    SearchResultFilterScope? resultFilterScope,
    int? searchTotalSources,
    int? searchedSources,
    int? matchedSources,
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
      resultFilter: resultFilter ?? this.resultFilter,
      resultFilterScope: resultFilterScope ?? this.resultFilterScope,
      searchTotalSources: searchTotalSources ?? this.searchTotalSources,
      searchedSources: searchedSources ?? this.searchedSources,
      matchedSources: matchedSources ?? this.matchedSources,
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
    if (state.lastQuery.isNotEmpty && !state.isSearching) {
      unawaited(search(state.lastQuery));
    }
  }

  void setResultFilter(String value) {
    state = state.copyWith(resultFilter: value.trim());
  }

  void setResultFilterScope(SearchResultFilterScope scope) {
    state = state.copyWith(resultFilterScope: scope);
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
      searchTotalSources: 0,
      searchedSources: 0,
      matchedSources: 0,
      clearVerificationSource: true,
    );

    try {
      final sources = _searchableSources(await _repository.getAllBookSources());
      if (sources.isEmpty) {
        state = state.copyWith(
          isSearching: false,
          searchTotalSources: 0,
          searchedSources: 0,
          matchedSources: 0,
          error: '娌℃湁鍙敤涔︽簮锛岃鍏堝湪璁剧疆閲屽鍏ュ苟鍚敤涔︽簮',
        );
        return;
      }
      state = state.copyWith(searchTotalSources: sources.length);

      final allResults = <Book>[];
      final seen = <String>{};
      BookSource? verificationSource;
      String verificationUrl = '';
      var tried = 0;
      var sourcesWithParsedResults = 0;
      final failureSamples = <String>[];
      final mode = state.searchMatchMode;
      final maxResults = mode == SearchMatchMode.precise ? 240 : 500;

      for (var start = 0; start < sources.length; start += 8) {
        if (currentCancelToken.isCancelled) return;
        final batch = sources.skip(start).take(8).toList();
        tried += batch.length;
        final resultsLists = await Future.wait(
          batch.map((source) async {
            try {
              if (currentCancelToken.isCancelled) return <Book>[];
              final books = await LegadoParser.searchBooks(
                source,
                query,
                cancelToken: currentCancelToken,
              ).timeout(const Duration(seconds: 16));
              if (currentCancelToken.isCancelled) return <Book>[];
              if (books.isNotEmpty) sourcesWithParsedResults++;
              final filtered = books
                  .where((book) => _matchScore(book, query, mode) > 0)
                  .map((book) {
                    final tags = <String>{...book.tags};
                    if (source.bookSourceName.trim().isNotEmpty) {
                      tags.add('source:${source.bookSourceName.trim()}');
                    }
                    if (source.bookSourceGroup?.trim().isNotEmpty == true) {
                      tags.add('group:${source.bookSourceGroup!.trim()}');
                    }
                    book
                      ..isFromSource = true
                      ..sourceUrl = source.id.toString()
                      ..tags = tags.toList();
                    return book;
                  })
                  .toList();
              if (books.isNotEmpty && filtered.isEmpty) {
                _appendFailureSample(
                  failureSamples,
                  source,
                  '解析到 ${books.length} 条结果，但被当前匹配模式过滤；可切换模糊模式重试。',
                );
              }
              return filtered;
            } catch (e) {
              if (e is DioException && e.type == DioExceptionType.cancel) {
                return <Book>[];
              }
              if (verificationSource == null && _shouldOfferVerification(e)) {
                verificationSource = source;
                verificationUrl = e is LegadoVerificationRequiredException
                    ? e.url
                    : (e is LegadoLoginRequiredException
                          ? e.loginUrl
                          : _sourceDefaultUrl(source));
              }
              _appendFailureSample(failureSamples, source, _compactError(e));
              debugPrint('Search Error from ${source.bookSourceName}: $e');
              return <Book>[];
            }
          }),
        );

        if (currentCancelToken.isCancelled) return;

        for (final list in resultsLists) {
          for (final book in list) {
            if (book.title.trim().isEmpty || book.title == '鏈煡') continue;
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
        _sortSearchResults(allResults, query, mode);
        state = state.copyWith(
          searchResults: List.unmodifiable(allResults),
          searchTotalSources: sources.length,
          searchedSources: tried,
          matchedSources: sourcesWithParsedResults,
        );
        if (allResults.length >= maxResults) break;
      }

      if (currentCancelToken.isCancelled) return;

      _sortSearchResults(allResults, query, mode);

      state = state.copyWith(
        isSearching: false,
        searchResults: allResults,
        searchTotalSources: sources.length,
        searchedSources: tried,
        matchedSources: sourcesWithParsedResults,
        verificationSource: allResults.isEmpty ? verificationSource : null,
        verificationUrl: allResults.isEmpty ? verificationUrl : '',
        clearVerificationSource: allResults.isNotEmpty,
        error: allResults.isEmpty
            ? _emptySearchMessage(
                tried: tried,
                sourcesWithParsedResults: sourcesWithParsedResults,
                failures: failureSamples,
              )
            : '',
      );
    } catch (e) {
      state = state.copyWith(isSearching: false, error: '鎼滅储澶辫触: $e');
    }
  }

  Future<int> addToBookshelf(Book book) async {
    return _prepareOnlineBook(book, favorite: true);
  }

  Future<int> openPreview(Book book) async {
    final target = book
      ..isFromSource = true
      ..isFavorite = false
      ..lastReadTime = null;
    final source = await _sourceForBook(target);
    if (source != null) {
      target.sourceUrl = source.id.toString();
    }
    final id = await _repository.saveBook(target);
    target.id = id;
    return id;
  }

  Future<int> _prepareOnlineBook(Book book, {required bool favorite}) async {
    var target = book
      ..isFromSource = true
      ..isFavorite = favorite
      ..lastReadTime = favorite ? DateTime.now() : null;

    final source = await _sourceForBook(target);
    if (source != null) {
      try {
        target = await LegadoParser.parseBookInfo(source, target);
        target
          ..isFromSource = true
          ..sourceUrl = source.id.toString()
          ..isFavorite = favorite
          ..lastReadTime = favorite ? DateTime.now() : null;
      } catch (_) {
        // Search result can still be saved without parsed detail.
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
        // 鐩綍澶辫触涓嶉樆姝㈡敹钘忥紝闃呰椤典細缁х画灏濊瘯瑙ｆ瀽銆?
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
      error is LegadoVerificationRequiredException ||
      error is LegadoLoginRequiredException;

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

  int _matchScore(Book book, String query, SearchMatchMode mode) {
    final q = _normalizeText(query);
    if (q.isEmpty) return 1;
    final title = _normalizeText(book.title);
    final author = _normalizeText(book.author);
    if (title.isEmpty && author.isEmpty) return 0;
    if (title == q) return 1000;
    if (title.startsWith(q)) return 850;

    if (mode == SearchMatchMode.precise) {
      return author == q ? 500 : 0;
    }

    if (title.contains(q)) return 700;
    if (author == q) return 520;
    if (author.contains(q)) return 420;
    if (_isMeaningfulReverseTitleMatch(title, q)) return 260;
    return 0;
  }

  bool _isMeaningfulReverseTitleMatch(String title, String query) {
    if (title.length < 3 || query.length < 3) return false;
    final minTitleLength = query.length <= 5 ? 3 : (query.length * 0.6).ceil();
    return title.length >= minTitleLength && query.contains(title);
  }

  void _sortSearchResults(
    List<Book> books,
    String query,
    SearchMatchMode mode,
  ) {
    final q = _normalizeText(query);
    books.sort((a, b) {
      final score = _matchScore(
        b,
        query,
        mode,
      ).compareTo(_matchScore(a, query, mode));
      if (score != 0) return score;

      final lengthDistance = (a.title.length - q.length).abs().compareTo(
        (b.title.length - q.length).abs(),
      );
      if (lengthDistance != 0) return lengthDistance;

      if (a.totalChapters != b.totalChapters) {
        return b.totalChapters.compareTo(a.totalChapters);
      }
      return b.fileSize.compareTo(a.fileSize);
    });
  }

  List<Book> filterVisibleResults(
    List<Book> books,
    String filter,
    SearchResultFilterScope scope,
  ) {
    return filterExploreSearchResults(books, filter, scope);
  }

  String _normalizeText(String value) {
    return _normalizeExploreText(value);
  }

  void _appendFailureSample(
    List<String> samples,
    BookSource source,
    String message,
  ) {
    if (samples.length >= 8) return;
    final name = source.bookSourceName.trim().isEmpty
        ? source.bookSourceUrl
        : source.bookSourceName;
    samples.add('$name: $message');
  }

  String _compactError(Object error) {
    var text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    const dioPrefix = 'DioException [unknown]: ';
    if (text.startsWith(dioPrefix)) text = text.substring(dioPrefix.length);
    if (text.length > 180) text = '${text.substring(0, 180)}...';
    return text;
  }

  String _emptySearchMessage({
    required int tried,
    required int sourcesWithParsedResults,
    required List<String> failures,
  }) {
    final buffer = StringBuffer('已搜索 $tried 个启用书源，暂时没有搜到书籍');
    if (sourcesWithParsedResults > 0) {
      buffer.write('；其中 $sourcesWithParsedResults 个源解析到结果但被当前匹配模式过滤');
    }
    if (failures.isNotEmpty) {
      buffer
        ..write('\n失败样例：')
        ..write(failures.map((item) => '\n- $item').join());
    }
    return buffer.toString();
  }
}
