import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'database_file_cleanup.dart';
import '../../data/models/book.dart';
import '../../data/models/bookmark.dart';
import '../../data/models/book_source.dart';
import '../../data/models/book_group.dart';
import '../../data/models/rss_source.dart';
import '../../data/models/source_catalog.dart';
import '../../data/models/chapter.dart';
import '../../data/models/reading_progress.dart';
import '../../data/models/reading_stats.dart';

/// Provider for the Isar database instance.
/// It must be overridden in the ProviderScope at the app root after initialization.
final isarProvider = Provider<Isar?>((ref) {
  return null;
});

/// Helper class to initialize and manage the Isar database.
class DatabaseHelper {
  static Isar? _isar;

  /// Get the initialized Isar instance.
  static Isar? get isar => _isar;

  /// Initialize the Isar database with all schemas.
  /// Handles both Web and native platforms appropriately.
  static Future<Isar?> init() async {
    if (kIsWeb) {
      return null; // Isar 3.x is not supported on web
    }
    if (Isar.instanceNames.isNotEmpty) {
      _isar = Isar.getInstance()!;
      return _isar;
    }

    final schemas = [
      BookSchema,
      BookmarkSchema,
      BookSourceSchema,
      ChapterSchema,
      ReadingProgressSchema,
      ReadingStatsSchema,
      BookGroupSchema,
      RssSourceSchema,
      SourceCatalogSchema,
    ];

    final dir = await getApplicationDocumentsDirectory();
    try {
      _isar = await Isar.open(schemas, directory: dir.path);
    } on IsarError catch (_) {
      await deleteDefaultIsarFiles(dir.path);
      _isar = await Isar.open(schemas, directory: dir.path);
    }

    return _isar;
  }
}
