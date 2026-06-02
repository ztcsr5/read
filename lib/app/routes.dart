import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/home/views/home_page.dart';
import '../features/bookshelf/views/bookshelf_page.dart';
import '../features/bookshelf/views/library_page.dart';
import '../features/bookshelf/viewmodels/bookshelf_viewmodel.dart';
import '../features/explore/views/explore_page.dart';
import '../features/settings/views/settings_page.dart';
import '../features/settings/views/about_page.dart';
import '../features/settings/views/reading_history_page.dart';
import '../features/settings/views/source_management_page.dart';
import '../features/settings/views/source_catalog_browser_page.dart';
import '../features/settings/views/source_test_page.dart';
import '../features/settings/views/source_verification_page.dart';
import '../features/settings/views/webview_import_page.dart';
import '../features/explore/views/rss_source_articles_page.dart';
import '../features/explore/views/rss_article_reader_page.dart';
import '../features/explore/views/book_source_browser_page.dart';
import '../data/models/rss_source.dart';
import '../data/models/rss_article.dart';
import '../data/models/book_source.dart';
import '../data/models/source_catalog.dart';
import '../features/reader/views/reader_page.dart';
import '../features/settings/views/purify_rules_page.dart';
import '../features/explore/views/web_source_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/bookshelf',
    redirect: (context, state) {
      if (state.uri.scheme == 'file') {
        try {
          ref.read(pendingImportFilePathProvider.notifier).state = state.uri
              .toFilePath();
        } catch (_) {
          ref.read(pendingImportFilePathProvider.notifier).state = state.uri
              .toString()
              .replaceFirst(RegExp(r'^file://'), '');
        }
        return '/bookshelf';
      }
      return null;
    },
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return HomePage(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/bookshelf',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: BookshelfPage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/explore',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: ExplorePage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: SettingsPage()),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/reader/:bookId',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final bookId = state.pathParameters['bookId']!;
          return CupertinoPage(child: ReaderPage(bookId: bookId));
        },
      ),
      GoRoute(
        path: '/sources',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            const CupertinoPage(child: SourceManagementPage()),
      ),
      GoRoute(
        path: '/source_test',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final source = state.extra as BookSource;
          return CupertinoPage(child: SourceTestPage(source: source));
        },
      ),
      GoRoute(
        path: '/source_verify',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final extra = state.extra;
          if (extra is Map<String, dynamic>) {
            return CupertinoPage(
              child: SourceVerificationPage(
                source: extra['source'] as BookSource,
                initialUrl: extra['url'] as String?,
              ),
            );
          }
          return CupertinoPage(
            child: SourceVerificationPage(source: extra as BookSource),
          );
        },
      ),
      GoRoute(
        path: '/source_catalog',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final catalog = state.extra as SourceCatalog;
          return CupertinoPage(
            child: SourceCatalogBrowserPage(catalog: catalog),
          );
        },
      ),
      GoRoute(
        path: '/book_source',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final source = state.extra as BookSource;
          return CupertinoPage(child: BookSourceBrowserPage(source: source));
        },
      ),
      GoRoute(
        path: '/web_source',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            const CupertinoPage(child: WebSourcePage()),
      ),
      GoRoute(
        path: '/webview_import',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final url = state.extra is String ? state.extra as String : null;
          return CupertinoPage(child: WebViewImportPage(initialUrl: url));
        },
      ),
      GoRoute(
        path: '/library',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            const CupertinoPage(child: LibraryPage()),
      ),
      GoRoute(
        path: '/about',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            const CupertinoPage(child: AboutPage()),
      ),
      GoRoute(
        path: '/reading_history',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            const CupertinoPage(child: ReadingHistoryPage()),
      ),
      GoRoute(
        path: '/purify',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            const CupertinoPage(child: PurifyRulesPage()),
      ),
      GoRoute(
        path: '/rss_articles',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final source = state.extra as RssSource;
          return CupertinoPage(child: RssSourceArticlesPage(source: source));
        },
      ),
      GoRoute(
        path: '/rss_reader',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return CupertinoPage(
            child: RssArticleReaderPage(
              source: extra['source'] as RssSource,
              article: extra['article'] as RssArticle,
            ),
          );
        },
      ),
    ],
  );
});
