import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/rss_source.dart';
import '../../../data/models/rss_article.dart';
import '../../../data/parsers/legado_parser.dart';
import '../../../widgets/ios_navigation_bar.dart';

final rssArticleContentProvider = FutureProvider.family<String, Map<String, dynamic>>((ref, args) async {
  final source = args['source'] as RssSource;
  final article = args['article'] as RssArticle;
  return await LegadoParser.parseRssContent(source, article.link);
});

class RssArticleReaderPage extends ConsumerWidget {
  final RssSource source;
  final RssArticle article;

  const RssArticleReaderPage({
    super.key,
    required this.source,
    required this.article,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentAsync = ref.watch(rssArticleContentProvider({
      'source': source,
      'article': article,
    }));

    return CupertinoPageScaffold(
      child: CustomScrollView(
        slivers: [
          IosNavigationBar(
            title: article.title,
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () {
              },
              child: const Icon(CupertinoIcons.compass),
            ),
          ),
          contentAsync.when(
            data: (content) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      article.title,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      article.pubDate ?? '未知时间',
                      style: TextStyle(
                        fontSize: 14,
                        color: CupertinoColors.secondaryLabel.resolveFrom(context),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // TODO: Replace with flutter_widget_from_html for better rendering
                    Text(
                      content.replaceAll(RegExp(r'<[^>]*>', multiLine: true, caseSensitive: false), '').trim(),
                      style: const TextStyle(
                        fontSize: 18,
                        height: 1.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            loading: () => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(40.0),
                child: CupertinoActivityIndicator(radius: 14),
              ),
            ),
            error: (err, stack) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(40.0),
                child: Center(
                  child: Text(
                    '加载失败: $err',
                    style: const TextStyle(color: CupertinoColors.destructiveRed),
                  ),
                ),
              ),
            ),
          ),
          
          const SliverToBoxAdapter(child: SizedBox(height: 60)),
        ],
      ),
    );
  }
}
