import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../data/models/rss_source.dart';
import '../viewmodels/rss_source_articles_viewmodel.dart';
import '../../../widgets/ios_navigation_bar.dart';

class RssSourceArticlesPage extends ConsumerWidget {
  final RssSource source;

  const RssSourceArticlesPage({super.key, required this.source});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(rssArticlesViewModelProvider(source));

    return CupertinoPageScaffold(
      child: CustomScrollView(
        slivers: [
          IosNavigationBar(
            title: source.sourceName,
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () {
                ref.read(rssArticlesViewModelProvider(source).notifier).loadArticles();
              },
              child: const Icon(CupertinoIcons.refresh),
            ),
          ),
          
          if (state.isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(40.0),
                child: CupertinoActivityIndicator(radius: 14),
              ),
            )
          else if (state.error.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(40.0),
                child: Center(
                  child: Text(
                    state.error,
                    style: const TextStyle(color: CupertinoColors.destructiveRed),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final article = state.articles[index];
                  return GestureDetector(
                    onTap: () {
                      context.push('/rss_reader', extra: {
                        'source': source,
                        'article': article,
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemBackground.resolveFrom(context),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: CupertinoColors.systemGrey.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  article.title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                if (article.description != null && article.description!.isNotEmpty) ...[
                                  Text(
                                    article.description!,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: CupertinoColors.secondaryLabel.resolveFrom(context),
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 8),
                                ],
                                Text(
                                  article.pubDate ?? '未知时间',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (article.coverUrl != null && article.coverUrl!.isNotEmpty) ...[
                            const SizedBox(width: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: CachedNetworkImage(
                                imageUrl: article.coverUrl!,
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                                errorWidget: (context, url, error) => Container(
                                  width: 80,
                                  height: 80,
                                  color: CupertinoColors.systemGrey5,
                                  child: const Icon(CupertinoIcons.news, color: CupertinoColors.systemGrey),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
                childCount: state.articles.length,
              ),
            ),
            
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}
