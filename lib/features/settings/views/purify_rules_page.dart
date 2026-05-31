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

  void _addRule() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      ref.read(purifyRulesProvider.notifier).addRule(text);
      _controller.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rules = ref.watch(purifyRulesProvider);
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoTheme.of(context).scaffoldBackgroundColor,
      child: CustomScrollView(
        slivers: [
          const IosNavigationBar(title: '规则净化'),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '在此输入需要全局过滤的字符串或正则表达式，例如一些常见的网站广告词：“请记住本站域名”。',
                    style: TextStyle(fontSize: 14, color: CupertinoColors.systemGrey),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: CupertinoTextField(
                          controller: _controller,
                          placeholder: '输入需要过滤的文字',
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          onSubmitted: (_) => _addRule(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      CupertinoButton.filled(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        onPressed: _addRule,
                        child: const Text('添加'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final rule = rules[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.white,
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
                        child: const Icon(CupertinoIcons.minus_circle_fill, color: CupertinoColors.destructiveRed),
                        onPressed: () {
                          ref.read(purifyRulesProvider.notifier).removeRule(rule);
                        },
                      ),
                    ),
                  ),
                );
              },
              childCount: rules.length,
            ),
          ),
        ],
      ),
    );
  }
}
