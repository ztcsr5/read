import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/rss_source.dart';
import '../../../data/models/rss_article.dart';
import '../../../data/parsers/legado_parser.dart';

final rssArticlesViewModelProvider = StateNotifierProvider.family<RssArticlesViewModel, RssArticlesState, RssSource>((ref, source) {
  return RssArticlesViewModel(source);
});

class RssArticlesState {
  final bool isLoading;
  final List<RssArticle> articles;
  final String error;

  RssArticlesState({
    this.isLoading = true,
    this.articles = const [],
    this.error = '',
  });

  RssArticlesState copyWith({
    bool? isLoading,
    List<RssArticle>? articles,
    String? error,
  }) {
    return RssArticlesState(
      isLoading: isLoading ?? this.isLoading,
      articles: articles ?? this.articles,
      error: error ?? this.error,
    );
  }
}

class RssArticlesViewModel extends StateNotifier<RssArticlesState> {
  final RssSource source;
  
  RssArticlesViewModel(this.source) : super(RssArticlesState()) {
    loadArticles();
  }

  Future<void> loadArticles() async {
    state = state.copyWith(isLoading: true, error: '');
    try {
      final articles = await LegadoParser.parseRssArticles(source);
      state = state.copyWith(
        isLoading: false,
        articles: articles,
        error: articles.isEmpty ? '没有拉取到文章，可能是规则不兼容或网站拒绝访问' : '',
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: '拉取失败: $e',
      );
    }
  }
}
