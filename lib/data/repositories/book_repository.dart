import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';

import '../../app/database/database_provider.dart';
import '../models/book.dart';
import '../models/bookmark.dart';
import '../models/chapter.dart';
import '../models/reading_progress.dart';
import '../models/book_group.dart';
import '../models/book_source.dart';
import '../models/rss_source.dart';
import '../models/source_catalog.dart';

/// Provider for BookRepository
final bookRepositoryProvider = Provider<BookRepository>((ref) {
  final isar = ref.watch(isarProvider);
  return BookRepository(isar);
});

/// Repository for handling Book, Chapter, and ReadingProgress database operations
class BookRepository {
  final Isar? isar;

  // In-memory mocks for web fallback
  final List<Book> _mockBooks = [];
  final List<Chapter> _mockChapters = [];
  final List<ReadingProgress> _mockProgress = [];
  final List<Bookmark> _mockBookmarks = [];
  final List<BookGroup> _mockGroups = [];
  final List<BookSource> _mockBookSources = [];
  final List<RssSource> _mockRssSources = [];
  final List<SourceCatalog> _mockSourceCatalogs = [];
  int _mockBookIdCounter = 1;
  int _mockGroupIdCounter = 1;
  int _mockSourceIdCounter = 1;
  int _mockRssSourceIdCounter = 1;
  int _mockSourceCatalogIdCounter = 1;

  BookRepository(this.isar);

  /// Save or update a book. Returns the auto-incremented ID.
  Future<int> saveBook(Book book) async {
    if (isar == null) {
      if (book.id == Isar.autoIncrement) {
        book.id = _mockBookIdCounter++;
      }
      final index = _mockBooks.indexWhere((b) => b.id == book.id);
      if (index >= 0) {
        _mockBooks[index] = book;
      } else {
        _mockBooks.add(book);
      }
      return book.id;
    }
    return await isar!.writeTxn(() async {
      return await isar!.collection<Book>().put(book);
    });
  }

  /// Save or update a book group. Returns the auto-incremented ID.
  Future<int> saveBookGroup(BookGroup group) async {
    if (isar == null) {
      if (group.id == Isar.autoIncrement) {
        group.id = _mockGroupIdCounter++;
      }
      final index = _mockGroups.indexWhere((g) => g.id == group.id);
      if (index >= 0) {
        _mockGroups[index] = group;
      } else {
        _mockGroups.add(group);
      }
      return group.id;
    }
    return await isar!.writeTxn(() async {
      return await isar!.collection<BookGroup>().put(group);
    });
  }

  /// Delete a book group
  Future<void> deleteBookGroup(int groupId) async {
    if (isar == null) {
      _mockGroups.removeWhere((g) => g.id == groupId);
      return;
    }
    await isar!.writeTxn(() async {
      await isar!.collection<BookGroup>().delete(groupId);
    });
  }

  /// Get all book groups
  Future<List<BookGroup>> getAllBookGroups() async {
    if (isar == null) {
      return List.from(_mockGroups);
    }
    return await isar!.collection<BookGroup>().where().findAll();
  }

  /// Save a list of chapters for a book.
  Future<void> saveChapters(List<Chapter> chapters) async {
    if (isar == null) {
      _mockChapters.addAll(chapters);
      return;
    }
    await isar!.writeTxn(() async {
      await isar!.collection<Chapter>().putAll(chapters);
    });
  }

  /// Get all saved books.
  Future<List<Book>> getAllBooks() async {
    if (isar == null) return List.from(_mockBooks);
    return await isar!.collection<Book>().where().findAll();
  }

  /// Get a book by its ID.
  Future<Book?> getBookById(int bookId) async {
    if (isar == null) {
      try {
        return _mockBooks.firstWhere((b) => b.id == bookId);
      } catch (_) {
        return null;
      }
    }
    return await isar!.collection<Book>().get(bookId);
  }

  /// Delete a book and its associated chapters, reading progress, and bookmarks.
  Future<void> deleteBook(int bookId) async {
    if (isar == null) {
      _mockBooks.removeWhere((b) => b.id == bookId);
      _mockChapters.removeWhere((c) => c.bookId == bookId);
      _mockProgress.removeWhere((p) => p.bookId == bookId);
      _mockBookmarks.removeWhere((b) => b.bookId == bookId);
      return;
    }
    await isar!.writeTxn(() async {
      // Delete the book itself
      await isar!.collection<Book>().delete(bookId);

      // Delete associated chapters
      await isar!
          .collection<Chapter>()
          .filter()
          .bookIdEqualTo(bookId)
          .deleteAll();

      // Delete associated reading progress
      await isar!
          .collection<ReadingProgress>()
          .filter()
          .bookIdEqualTo(bookId)
          .deleteAll();

      // Delete associated bookmarks
      await isar!
          .collection<Bookmark>()
          .filter()
          .bookIdEqualTo(bookId)
          .deleteAll();
    });
  }

  /// Update the reading progress for a book.
  Future<void> updateReadingProgress(
    int bookId,
    int chapterIndex,
    int position, {
    double scrollPosition = 0,
    double percentage = 0,
  }) async {
    if (isar == null) {
      final idx = _mockProgress.indexWhere((p) => p.bookId == bookId);
      if (idx >= 0) {
        _mockProgress[idx].chapterIndex = chapterIndex;
        _mockProgress[idx].charOffset = position;
        _mockProgress[idx].scrollPosition = scrollPosition;
        _mockProgress[idx].percentage = percentage;
        _mockProgress[idx].lastReadAt = DateTime.now();
      } else {
        _mockProgress.add(
          ReadingProgress(
            bookId: bookId,
            chapterIndex: chapterIndex,
            charOffset: position,
            scrollPosition: scrollPosition,
            percentage: percentage,
            lastReadAt: DateTime.now(),
          ),
        );
      }
      final bookIndex = _mockBooks.indexWhere((b) => b.id == bookId);
      if (bookIndex >= 0) {
        _mockBooks[bookIndex].currentChapter = chapterIndex;
        _mockBooks[bookIndex].currentPosition = scrollPosition;
        _mockBooks[bookIndex].readingProgress = percentage;
        _mockBooks[bookIndex].lastReadTime = DateTime.now();
      }
      return;
    }
    await isar!.writeTxn(() async {
      var progress = await isar!
          .collection<ReadingProgress>()
          .filter()
          .bookIdEqualTo(bookId)
          .findFirst();

      if (progress == null) {
        progress = ReadingProgress(
          bookId: bookId,
          chapterIndex: chapterIndex,
          charOffset: position,
          scrollPosition: scrollPosition,
          percentage: percentage,
          lastReadAt: DateTime.now(),
        );
      } else {
        progress.chapterIndex = chapterIndex;
        progress.charOffset = position;
        progress.scrollPosition = scrollPosition;
        progress.percentage = percentage;
        progress.lastReadAt = DateTime.now();
      }

      await isar!.collection<ReadingProgress>().put(progress);

      final book = await isar!.collection<Book>().get(bookId);
      if (book != null) {
        book.currentChapter = chapterIndex;
        book.currentPosition = scrollPosition;
        book.readingProgress = percentage;
        book.lastReadTime = DateTime.now();
        await isar!.collection<Book>().put(book);
      }
    });
  }

  /// Get all chapters for a given book ID.
  Future<List<Chapter>> getChaptersForBook(int bookId) async {
    if (isar == null) {
      return _mockChapters.where((c) => c.bookId == bookId).toList()
        ..sort((a, b) => a.index.compareTo(b.index));
    }
    return await isar!
        .collection<Chapter>()
        .filter()
        .bookIdEqualTo(bookId)
        .sortByIndex()
        .findAll();
  }

  // --- RssSource Methods ---

  Future<int> saveRssSource(RssSource source) async {
    if (isar == null) {
      if (source.id == Isar.autoIncrement) {
        source.id = _mockRssSourceIdCounter++;
      }
      final index = _mockRssSources.indexWhere(
        (s) => s.id == source.id || s.sourceUrl == source.sourceUrl,
      );
      if (index >= 0) {
        source.id = _mockRssSources[index].id;
        _mockRssSources[index] = source;
      } else {
        _mockRssSources.add(source);
      }
      return source.id;
    }
    return await isar!.writeTxn(() async {
      final existing = await isar!
          .collection<RssSource>()
          .filter()
          .sourceUrlEqualTo(source.sourceUrl)
          .findFirst();
      if (existing != null) source.id = existing.id;
      return await isar!.collection<RssSource>().put(source);
    });
  }

  Future<void> deleteRssSource(int sourceId) async {
    if (isar == null) {
      _mockRssSources.removeWhere((s) => s.id == sourceId);
      return;
    }
    await isar!.writeTxn(() async {
      await isar!.collection<RssSource>().delete(sourceId);
    });
  }

  Future<List<RssSource>> getAllRssSources() async {
    if (isar == null) {
      return List.from(_mockRssSources);
    }
    return await isar!.collection<RssSource>().where().findAll();
  }

  // --- BookSource Methods ---

  Future<int> saveBookSource(BookSource source) async {
    if (isar == null) {
      if (source.id == Isar.autoIncrement) {
        source.id = _mockSourceIdCounter++;
      }
      final index = _mockBookSources.indexWhere(
        (s) => s.id == source.id || s.bookSourceUrl == source.bookSourceUrl,
      );
      if (index >= 0) {
        source.id = _mockBookSources[index].id;
        _mockBookSources[index] = source;
      } else {
        _mockBookSources.add(source);
      }
      return source.id;
    }
    return await isar!.writeTxn(() async {
      final existing = await isar!
          .collection<BookSource>()
          .filter()
          .bookSourceUrlEqualTo(source.bookSourceUrl)
          .findFirst();
      if (existing != null) source.id = existing.id;
      return await isar!.collection<BookSource>().put(source);
    });
  }

  Future<void> deleteBookSource(int sourceId) async {
    if (isar == null) {
      _mockBookSources.removeWhere((s) => s.id == sourceId);
      return;
    }
    await isar!.writeTxn(() async {
      await isar!.collection<BookSource>().delete(sourceId);
    });
  }

  Future<void> setBookSourceEnabled(int sourceId, bool enabled) async {
    if (isar == null) {
      final index = _mockBookSources.indexWhere((s) => s.id == sourceId);
      if (index >= 0) {
        _mockBookSources[index].enabled = enabled;
      }
      return;
    }
    await isar!.writeTxn(() async {
      final source = await isar!.collection<BookSource>().get(sourceId);
      if (source == null) return;
      source.enabled = enabled;
      await isar!.collection<BookSource>().put(source);
    });
  }

  Future<List<BookSource>> getAllBookSources() async {
    if (isar == null) {
      return List.from(_mockBookSources);
    }
    return await isar!.collection<BookSource>().where().findAll();
  }

  // --- SourceCatalog Methods ---

  Future<int> saveSourceCatalog(SourceCatalog catalog) async {
    if (isar == null) {
      if (catalog.id == Isar.autoIncrement) {
        catalog.id = _mockSourceCatalogIdCounter++;
      }
      final index = _mockSourceCatalogs.indexWhere((s) => s.url == catalog.url);
      if (index >= 0) {
        catalog.id = _mockSourceCatalogs[index].id;
        _mockSourceCatalogs[index] = catalog;
      } else {
        _mockSourceCatalogs.add(catalog);
      }
      return catalog.id;
    }
    return await isar!.writeTxn(() async {
      return await isar!.collection<SourceCatalog>().put(catalog);
    });
  }

  Future<void> deleteSourceCatalog(int catalogId) async {
    if (isar == null) {
      _mockSourceCatalogs.removeWhere((s) => s.id == catalogId);
      return;
    }
    await isar!.writeTxn(() async {
      await isar!.collection<SourceCatalog>().delete(catalogId);
    });
  }

  Future<void> setSourceCatalogEnabled(int catalogId, bool enabled) async {
    if (isar == null) {
      final index = _mockSourceCatalogs.indexWhere((s) => s.id == catalogId);
      if (index >= 0) {
        _mockSourceCatalogs[index].enabled = enabled;
      }
      return;
    }
    await isar!.writeTxn(() async {
      final catalog = await isar!.collection<SourceCatalog>().get(catalogId);
      if (catalog == null) return;
      catalog.enabled = enabled;
      await isar!.collection<SourceCatalog>().put(catalog);
    });
  }

  Future<List<SourceCatalog>> getAllSourceCatalogs() async {
    if (isar == null) {
      return List.from(_mockSourceCatalogs);
    }
    return await isar!.collection<SourceCatalog>().where().findAll();
  }

  /// Get bookmarks for a book
  Future<List<Bookmark>> getBookmarks(int bookId) async {
    if (isar == null) {
      return _mockBookmarks.where((b) => b.bookId == bookId).toList();
    }
    return await isar!
        .collection<Bookmark>()
        .filter()
        .bookIdEqualTo(bookId)
        .findAll();
  }

  /// Save a bookmark
  Future<void> saveBookmark(Bookmark bookmark) async {
    if (isar == null) {
      if (bookmark.id == Isar.autoIncrement) {
        bookmark.id = _mockGroupIdCounter++; // Reusing counter for mock
      }
      _mockBookmarks.add(bookmark);
      return;
    }
    await isar!.writeTxn(() async {
      await isar!.collection<Bookmark>().put(bookmark);
    });
  }

  /// Delete a bookmark
  Future<void> deleteBookmark(int bookmarkId) async {
    if (isar == null) {
      _mockBookmarks.removeWhere((b) => b.id == bookmarkId);
      return;
    }
    await isar!.writeTxn(() async {
      await isar!.collection<Bookmark>().delete(bookmarkId);
    });
  }
}
