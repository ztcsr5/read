import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import '../../../data/models/book.dart';
import '../../../data/models/book_source.dart';
import '../../../data/repositories/book_repository.dart';
import '../../../data/parsers/legado_parser.dart';

import '../../../data/models/rss_source.dart';
import '../../../data/repositories/source_repository.dart';

final exploreViewModelProvider =
    StateNotifierProvider<ExploreViewModel, ExploreState>((ref) {
      final repo = ref.watch(bookRepositoryProvider);
      final sourceRepo = ref.watch(sourceRepositoryProvider);
      return ExploreViewModel(repo, sourceRepo);
    });

class ExploreState {
  final bool isSearching;
  final List<Book> searchResults;
  final String error;
  final List<RssSource> rssSources;
  final int selectedTab; // 0 for books, 1 for RSS

  ExploreState({
    this.isSearching = false,
    this.searchResults = const [],
    this.error = '',
    this.rssSources = const [],
    this.selectedTab = 0,
  });

  ExploreState copyWith({
    bool? isSearching,
    List<Book>? searchResults,
    String? error,
    List<RssSource>? rssSources,
    int? selectedTab,
  }) {
    return ExploreState(
      isSearching: isSearching ?? this.isSearching,
      searchResults: searchResults ?? this.searchResults,
      error: error ?? this.error,
      rssSources: rssSources ?? this.rssSources,
      selectedTab: selectedTab ?? this.selectedTab,
    );
  }
}

class ExploreViewModel extends StateNotifier<ExploreState> {
  final BookRepository _repository;
  final SourceRepository _sourceRepository;

  ExploreViewModel(this._repository, this._sourceRepository)
    : super(ExploreState()) {
    loadRssSources();
  }

  void setTab(int index) {
    state = state.copyWith(selectedTab: index);
    if (index == 1) {
      loadRssSources();
    }
  }

  Future<void> loadRssSources() async {
    final sources = await _sourceRepository.getEnabledRssSources();
    state = state.copyWith(rssSources: sources);
  }

  Future<void> search(String keyword) async {
    if (keyword.isEmpty) return;

    state = state.copyWith(isSearching: true, error: '', searchResults: []);

    try {
      List<BookSource> sources = await _repository.getAllBookSources();

      if (sources.isEmpty) {
        state = state.copyWith(isSearching: false, error: '没有可用的书源，请先在设置中导入书源');
        return;
      }

      List<Book> allResults = [];

      final searchTasks = sources.take(10).map((source) {
        return LegadoParser.searchBooks(source, keyword).catchError((e) {
          print('Search Error from ${source.bookSourceName}: $e');
          return <Book>[]; // 返回空列表而不是报错中断
        });
      });

      final resultsLists = await Future.wait(searchTasks.toList());
      for (var list in resultsLists) {
        allResults.addAll(list);
      }

      state = state.copyWith(
        isSearching: false,
        searchResults: allResults,
        error: allResults.isEmpty ? '未搜到相关书籍' : '',
      );
    } catch (e) {
      state = state.copyWith(isSearching: false, error: '搜索失败: $e');
    }
  }

  Future<int> addToBookshelf(Book book) async {
    return _repository.saveBook(book);
  }
}
