import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../../widgets/ios_navigation_bar.dart';
import '../../../app/theme/app_theme.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  String _cacheSizeStr = '0.00 MB';

  @override
  void initState() {
    super.initState();
    _calculateCacheSize();
  }

  Future<void> _calculateCacheSize() async {
    try {
      final tempDir = await getTemporaryDirectory();
      int totalSize = 0;
      if (tempDir.existsSync()) {
        tempDir.listSync(recursive: true, followLinks: false).forEach((
          FileSystemEntity entity,
        ) {
          if (entity is File) {
            totalSize += entity.lengthSync();
          }
        });
      }
      final sizeMb = totalSize / (1024 * 1024);
      if (mounted) {
        setState(() {
          _cacheSizeStr = '${sizeMb.toStringAsFixed(2)} MB';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cacheSizeStr = '未知';
        });
      }
    }
  }

  Future<void> _clearCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        tempDir.listSync(recursive: true, followLinks: false).forEach((
          FileSystemEntity entity,
        ) {
          if (entity is File) {
            entity.deleteSync();
          } else if (entity is Directory) {
            entity.deleteSync(recursive: true);
          }
        });
      }
      await _calculateCacheSize();

      if (!mounted) return;
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('清理成功'),
          content: const Text('已清空所有临时缓存文件'),
          actions: [
            CupertinoDialogAction(
              child: const Text('确定'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('清理缓存失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoTheme.of(context).scaffoldBackgroundColor,
      child: CustomScrollView(
        slivers: [
          const IosNavigationBar(title: '设置'),
          SliverList(
            delegate: SliverChildListDelegate([
              CupertinoListSection.insetGrouped(
                header: const Text('外观'),
                children: [
                  CupertinoListTile(
                    title: const Text('跟随系统'),
                    trailing: ref.watch(themeProvider) == ThemeType.system
                        ? const Icon(CupertinoIcons.check_mark)
                        : null,
                    onTap: () {
                      ref.read(themeProvider.notifier).state = ThemeType.system;
                    },
                  ),
                  CupertinoListTile(
                    title: const Text('浅色模式'),
                    trailing: ref.watch(themeProvider) == ThemeType.light
                        ? const Icon(CupertinoIcons.check_mark)
                        : null,
                    onTap: () {
                      ref.read(themeProvider.notifier).state = ThemeType.light;
                    },
                  ),
                  CupertinoListTile(
                    title: const Text('深色模式'),
                    trailing: ref.watch(themeProvider) == ThemeType.dark
                        ? const Icon(CupertinoIcons.check_mark)
                        : null,
                    onTap: () {
                      ref.read(themeProvider.notifier).state = ThemeType.dark;
                    },
                  ),
                  CupertinoListTile(
                    title: const Text('护眼模式'),
                    trailing: ref.watch(themeProvider) == ThemeType.eyeCare
                        ? const Icon(CupertinoIcons.check_mark)
                        : null,
                    onTap: () {
                      ref.read(themeProvider.notifier).state =
                          ThemeType.eyeCare;
                    },
                  ),
                ],
              ),
              CupertinoListSection.insetGrouped(
                header: const Text('内容设置'),
                children: [
                  CupertinoListTile(
                    title: const Text('书源管理'),
                    leading: const Icon(CupertinoIcons.square_stack_3d_up),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () => context.push('/sources'),
                  ),
                  CupertinoListTile(
                    title: const Text('规则净化'),
                    leading: const Icon(CupertinoIcons.shield),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () => context.push('/purify'),
                  ),
                ],
              ),
              CupertinoListSection.insetGrouped(
                header: const Text('通用'),
                children: [
                  CupertinoListTile(
                    title: const Text('清理缓存'),
                    leading: const Icon(CupertinoIcons.trash),
                    additionalInfo: Text(_cacheSizeStr),
                    onTap: _clearCache,
                  ),
                  CupertinoListTile(
                    title: const Text('关于阅读'),
                    leading: const Icon(CupertinoIcons.info_circle),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () => context.push('/about'),
                  ),
                ],
              ),
              const SizedBox(height: 40),
            ]),
          ),
        ],
      ),
    );
  }
}
