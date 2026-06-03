import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/ios_navigation_bar.dart';
import '../providers/purify_rules_provider.dart';

class PurifyRulesPage extends ConsumerStatefulWidget {
  const PurifyRulesPage({super.key});

  @override
  ConsumerState<PurifyRulesPage> createState() => _PurifyRulesPageState();
}

class _PurifyRulesPageState extends ConsumerState<PurifyRulesPage> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _subscriptionController = TextEditingController();
  bool _busy = false;
  List<String> _subscriptions = const [];

  @override
  void initState() {
    super.initState();
    _loadSubscriptions();
  }

  @override
  void dispose() {
    _controller.dispose();
    _subscriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadSubscriptions() async {
    final subscriptions = await ref
        .read(purifyRulesProvider.notifier)
        .getSubscriptions();
    if (mounted) setState(() => _subscriptions = subscriptions);
  }

  Future<void> _addRule() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    await ref.read(purifyRulesProvider.notifier).addRule(text);
    _controller.clear();
  }

  Future<void> _addSubscription() async {
    final url = _subscriptionController.text.trim();
    if (url.isEmpty) return;
    await _runBusy(() async {
      final count = await ref
          .read(purifyRulesProvider.notifier)
          .addSubscription(url);
      _subscriptionController.clear();
      await _loadSubscriptions();
      _showTip('导入完成', '已导入 $count 条净化规则');
    });
  }

  Future<void> _refreshSubscriptions() async {
    await _runBusy(() async {
      final count = await ref
          .read(purifyRulesProvider.notifier)
          .refreshSubscriptions();
      _showTip('刷新完成', '已导入 $count 条新规则');
    });
  }

  Future<void> _pickJsonFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json', 'txt'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    await _runBusy(() async {
      final text = await File(path).readAsString();
      final count = await ref
          .read(purifyRulesProvider.notifier)
          .importFromJsonText(text);
      _showTip('导入完成', '已导入 $count 条净化规则');
    });
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      _showTip('导入失败', e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showTip(String title, String message) {
    if (!mounted) return;
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('确定'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rules = ref.watch(purifyRulesProvider);
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoTheme.of(context).scaffoldBackgroundColor,
      child: CustomScrollView(
        slivers: [
          IosNavigationBar(
            title: '净化规则',
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _busy ? null : _pickJsonFile,
              child: const Icon(CupertinoIcons.doc_text),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CupertinoTextField(
                    controller: _controller,
                    placeholder: '手动添加要过滤的文字或正则',
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    onSubmitted: (_) => _addRule(),
                  ),
                  const SizedBox(height: 10),
                  CupertinoButton.filled(
                    onPressed: _busy ? null : _addRule,
                    child: const Text('添加规则'),
                  ),
                  const SizedBox(height: 22),
                  CupertinoTextField(
                    controller: _subscriptionController,
                    placeholder: '净化规则订阅 URL',
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: CupertinoButton.filled(
                          onPressed: _busy ? null : _addSubscription,
                          child: const Text('导入订阅'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: CupertinoButton(
                          onPressed: _busy || _subscriptions.isEmpty
                              ? null
                              : _refreshSubscriptions,
                          child: const Text('刷新订阅'),
                        ),
                      ),
                    ],
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 16),
                    const Center(child: CupertinoActivityIndicator()),
                  ],
                  if (_subscriptions.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const Text(
                      '订阅',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._subscriptions.map(
                      (url) => CupertinoListTile(
                        title: Text(
                          url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: CupertinoButton(
                          padding: EdgeInsets.zero,
                          child: const Icon(
                            CupertinoIcons.minus_circle_fill,
                            color: CupertinoColors.destructiveRed,
                          ),
                          onPressed: () async {
                            await ref
                                .read(purifyRulesProvider.notifier)
                                .removeSubscription(url);
                            await _loadSubscriptions();
                          },
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    '规则 ${rules.length} 条',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final rule = rules[index];
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Dismissible(
                  key: Key(rule),
                  direction: DismissDirection.endToStart,
                  onDismissed: (direction) {
                    ref.read(purifyRulesProvider.notifier).removeRule(rule);
                  },
                  background: Container(
                    decoration: BoxDecoration(
                      color: CupertinoColors.destructiveRed,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(CupertinoIcons.delete, color: CupertinoColors.white),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF2C2C2E)
                          : CupertinoColors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: CupertinoListTile(
                      title: Text(
                        rule,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: CupertinoButton(
                        padding: EdgeInsets.zero,
                        child: const Icon(
                          CupertinoIcons.minus_circle_fill,
                          color: CupertinoColors.destructiveRed,
                        ),
                        onPressed: () {
                          ref.read(purifyRulesProvider.notifier).removeRule(rule);
                        },
                      ),
                    ),
                  ),
                ),
              );
            }, childCount: rules.length),
          ),
        ],
      ),
    );
  }
}
