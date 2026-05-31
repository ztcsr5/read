import 'package:isar/isar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/reading_stats.dart';
import '../../app/database/database_provider.dart';

final statsRepositoryProvider = Provider((ref) => StatsRepository());

class StatsRepository {
  Isar? get _isar => DatabaseHelper.isar;

  /// 记录一次阅读时长
  Future<void> recordReadingSession(int durationInSeconds) async {
    if (_isar == null) return;
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    await _isar!.writeTxn(() async {
      var stats = await _isar!.readingStats.where().dateEqualTo(today).findFirst();
      if (stats == null) {
        stats = ReadingStats(date: today);
        stats.readingDurationSeconds = durationInSeconds;
        stats.sessionCount = 1;
      } else {
        stats.readingDurationSeconds += durationInSeconds;
        stats.sessionCount += 1;
      }
      await _isar!.readingStats.put(stats);
    });
  }

  /// 获取当天的阅读统计
  Future<ReadingStats> getTodayStats() async {
    if (_isar == null) return ReadingStats(date: DateTime.now());
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    final stats = await _isar!.readingStats.where().dateEqualTo(today).findFirst();
    return stats ?? ReadingStats(date: today);
  }

  /// 获取总的阅读时长（秒）
  Future<int> getTotalReadingDuration() async {
    if (_isar == null) return 0;
    
    final allStats = await _isar!.readingStats.where().findAll();
    return allStats.fold<int>(0, (prev, stats) => prev + stats.readingDurationSeconds);
  }

  /// 获取连续阅读天数
  Future<int> getConsecutiveReadingDays() async {
    if (_isar == null) return 0;
    
    final allStats = await _isar!.readingStats.where().sortByDateDesc().findAll();
    if (allStats.isEmpty) return 0;

    int consecutiveDays = 0;
    DateTime? expectedDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    
    for (var stat in allStats) {
      if (stat.readingDurationSeconds > 0) {
        if (expectedDate == null) {
          consecutiveDays++;
          expectedDate = stat.date.subtract(const Duration(days: 1));
        } else if (stat.date.isAtSameMomentAs(expectedDate)) {
          consecutiveDays++;
          expectedDate = stat.date.subtract(const Duration(days: 1));
        } else if (stat.date.isAfter(expectedDate)) {
          // ignore future dates somehow
          continue;
        } else {
          break; // break the streak
        }
      }
    }
    
    // If today is 0 duration but yesterday had reading, the streak isn't broken yet visually
    if (consecutiveDays == 0 && allStats.isNotEmpty) {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final yesterdayStat = allStats.firstWhere((s) => s.date.year == yesterday.year && s.date.month == yesterday.month && s.date.day == yesterday.day, orElse: () => ReadingStats(date: yesterday));
      if (yesterdayStat.readingDurationSeconds > 0) {
        expectedDate = yesterday.subtract(const Duration(days: 1));
        consecutiveDays = 1;
        for (var stat in allStats.skipWhile((s) => s.date.isAfter(yesterday))) {
            if (stat.readingDurationSeconds > 0 && expectedDate != null && stat.date.isAtSameMomentAs(expectedDate)) {
                consecutiveDays++;
                expectedDate = stat.date.subtract(const Duration(days: 1));
            } else {
                break;
            }
        }
      }
    }
    
    return consecutiveDays;
  }
}
