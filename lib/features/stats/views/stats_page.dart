import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../widgets/ios_navigation_bar.dart';
import '../../../app/theme/colors.dart';
import '../../../data/repositories/stats_repository.dart';

final todayStatsProvider = FutureProvider((ref) {
  return ref.read(statsRepositoryProvider).getTodayStats();
});

final totalDurationProvider = FutureProvider((ref) {
  return ref.read(statsRepositoryProvider).getTotalReadingDuration();
});

final consecutiveDaysProvider = FutureProvider((ref) {
  return ref.read(statsRepositoryProvider).getConsecutiveReadingDays();
});

class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayStats = ref.watch(todayStatsProvider);
    final totalDuration = ref.watch(totalDurationProvider);
    final consecutiveDays = ref.watch(consecutiveDaysProvider);

    return CupertinoPageScaffold(
      backgroundColor: CupertinoTheme.of(context).scaffoldBackgroundColor,
      child: CustomScrollView(
        slivers: [
          const IosNavigationBar(title: '阅读统计'),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 今日阅读时间卡片
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primaryBlue, Color(0xFF5856D6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '今日阅读',
                          style: TextStyle(
                            color: CupertinoColors.white.withOpacity(0.8),
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              todayStats.when(
                                data: (stats) => (stats.readingDurationSeconds ~/ 60).toString(),
                                loading: () => '...',
                                error: (_, __) => '0',
                              ),
                              style: const TextStyle(
                                color: CupertinoColors.white,
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                                height: 1.0,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                '分钟',
                                style: TextStyle(
                                  color: CupertinoColors.white.withOpacity(0.9),
                                  fontSize: 17,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // 总计数据
                  const Text(
                    '总计',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildStatBox(
                        context, 
                        '今日已读', 
                        todayStats.when(
                          data: (stats) => '${stats.wordsRead} 字',
                          loading: () => '...',
                          error: (_, __) => '-',
                        )
                      ),
                      const SizedBox(width: 16),
                      _buildStatBox(
                        context, 
                        '总时长', 
                        totalDuration.when(
                          data: (duration) => '${duration ~/ 3600} 小时',
                          loading: () => '...',
                          error: (_, __) => '-',
                        )
                      ),
                      const SizedBox(width: 16),
                      _buildStatBox(
                        context, 
                        '连续阅读', 
                        consecutiveDays.when(
                          data: (days) => '$days 天',
                          loading: () => '...',
                          error: (_, __) => '-',
                        )
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBox(BuildContext context, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: CupertinoTheme.of(context).barBackgroundColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
