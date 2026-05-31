import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';

import '../../app/database/database_provider.dart';
import '../models/book_source.dart';
import '../models/rss_source.dart';

/// Provider for SourceRepository
final sourceRepositoryProvider = Provider<SourceRepository>((ref) {
  final isar = ref.watch(isarProvider);
  return SourceRepository(isar!);
});

/// Repository for handling BookSource (Legado sources) database operations
class SourceRepository {
  final Isar isar;

  SourceRepository(this.isar);

  /// Get all book sources.
  Future<List<BookSource>> getAllSources() async {
    return await isar.collection<BookSource>().where().findAll();
  }
  
  /// Get only enabled book sources.
  Future<List<BookSource>> getEnabledSources() async {
    return await isar.collection<BookSource>().filter().enabledEqualTo(true).findAll();
  }

  /// Save or update a single book source.
  Future<int> saveSource(BookSource source) async {
    return await isar.writeTxn(() async {
      return await isar.collection<BookSource>().put(source);
    });
  }

  /// Import Legado JSON formatted book sources from string content.
  Future<int> importSourcesFromJson(String jsonContent) async {
    try {
      final List<dynamic> data = jsonDecode(jsonContent);
      final List<BookSource> sources = [];
      
      for (final item in data) {
        sources.add(BookSource.fromJson(item as Map<String, dynamic>));
      }

      await isar.writeTxn(() async {
        await isar.collection<BookSource>().putAll(sources);
      });

      return sources.length;
    } catch (e) {
      // In case of any error during parsing, return 0 indicating failure
      return 0;
    }
  }

  /// Enable or disable a book source.
  Future<void> enableSource(int id, bool enabled) async {
    final source = await isar.collection<BookSource>().get(id);
    if (source != null) {
      source.enabled = enabled;
      await isar.writeTxn(() async {
        await isar.collection<BookSource>().put(source);
      });
    }
  }

  /// Delete a book source by ID.
  Future<void> deleteSource(int id) async {
    await isar.writeTxn(() async {
      await isar.collection<BookSource>().delete(id);
    });
  }

  // --- RssSource Operations ---

  Future<List<RssSource>> getAllRssSources() async {
    return await isar.collection<RssSource>().where().findAll();
  }

  Future<List<RssSource>> getEnabledRssSources() async {
    return await isar.collection<RssSource>().filter().enabledEqualTo(true).findAll();
  }

  Future<int> importRssSourcesFromJson(String jsonContent) async {
    try {
      final List<dynamic> data = jsonDecode(jsonContent);
      final List<RssSource> sources = [];
      
      for (final item in data) {
        sources.add(RssSource.fromJson(item as Map<String, dynamic>));
      }

      await isar.writeTxn(() async {
        await isar.collection<RssSource>().putAll(sources);
      });

      return sources.length;
    } catch (e) {
      return 0;
    }
  }

  Future<void> enableRssSource(int id, bool enabled) async {
    final source = await isar.collection<RssSource>().get(id);
    if (source != null) {
      source.enabled = enabled;
      await isar.writeTxn(() async {
        await isar.collection<RssSource>().put(source);
      });
    }
  }

  Future<void> deleteRssSource(int id) async {
    await isar.writeTxn(() async {
      await isar.collection<RssSource>().delete(id);
    });
  }
}
