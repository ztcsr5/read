import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/colors.dart';
import '../viewmodels/reader_viewmodel.dart';

class ReaderSettingsPanel extends ConsumerStatefulWidget {
  final String bookId;
  const ReaderSettingsPanel({super.key, required this.bookId});

  @override
  ConsumerState<ReaderSettingsPanel> createState() =>
      _ReaderSettingsPanelState();
}

class _ReaderSettingsPanelState extends ConsumerState<ReaderSettingsPanel> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(readerViewModelProvider(widget.bookId));
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;

    return Container(
      height: 420,
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1C1C1E)
            : CupertinoColors.systemBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // 拖拽把手
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 10),
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark
                      ? CupertinoColors.systemGrey3
                      : CupertinoColors.systemGrey4,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),

            // 选项卡
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoSlidingSegmentedControl<int>(
                  groupValue: _tabIndex,
                  children: const {
                    0: SizedBox(width: 72, child: Center(child: Text('外观'))),
                    1: SizedBox(width: 72, child: Center(child: Text('排版'))),
                    2: SizedBox(width: 72, child: Center(child: Text('高级'))),
                  },
                  onValueChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _tabIndex = val;
                      });
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 内容区
            Expanded(
              child: _buildCurrentTab(
                context,
                ref,
                state,
                isDark,
                widget.bookId,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTab(
    BuildContext context,
    WidgetRef ref,
    ReaderState state,
    bool isDark,
    String bookId,
  ) {
    switch (_tabIndex) {
      case 0:
        return _buildThemeTab(context, ref, state, isDark, bookId);
      case 1:
        return _buildLayoutTab(context, ref, state, isDark, bookId);
      case 2:
      default:
        return _buildAdvancedTab(context, ref, state, isDark, bookId);
    }
  }

  Widget _buildThemeTab(
    BuildContext context,
    WidgetRef ref,
    ReaderState state,
    bool isDark,
    String bookId,
  ) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // 字号控制
        _buildSectionTitle('字号大小', isDark),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Text(
                'A',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? CupertinoColors.white : CupertinoColors.black,
                ),
              ),
              Expanded(
                child: CupertinoSlider(
                  value: state.fontSize,
                  min: 12.0,
                  max: 32.0,
                  divisions: 20,
                  activeColor: AppColors.primaryPurple,
                  onChanged: (val) {
                    ref
                        .read(readerViewModelProvider(bookId).notifier)
                        .setFontSize(val);
                  },
                ),
              ),
              Text(
                'A',
                style: TextStyle(
                  fontSize: 24,
                  color: isDark ? CupertinoColors.white : CupertinoColors.black,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // 背景主题
        _buildSectionTitle('背景颜色', isDark),
        Wrap(
          spacing: 10,
          runSpacing: 12,
          children: ReaderBackground.values
              .where((bg) => bg != ReaderBackground.custom)
              .map((bg) {
                final isSelected = state.background == bg;
                final color = bg == ReaderBackground.custom
                    ? state.customBackgroundColor
                    : bg.color;
                return GestureDetector(
                  onTap: () {
                    if (bg == ReaderBackground.custom) {
                      _showCustomBackgroundPicker(context, ref, bookId);
                    } else {
                      ref
                          .read(readerViewModelProvider(bookId).notifier)
                          .setBackground(bg);
                    }
                  },
                  child: SizedBox(
                    width: 54,
                    child: Column(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primaryPurple
                                  : (isDark
                                        ? const Color(0xFF38383A)
                                        : CupertinoColors.systemGrey5),
                              width: isSelected ? 2.5 : 1.0,
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          bg.label,
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark
                                ? CupertinoColors.systemGrey2
                                : CupertinoColors.systemGrey,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              })
              .toList(),
        ),
      ],
    );
  }

  void _showCustomBackgroundPicker(
    BuildContext context,
    WidgetRef ref,
    String bookId,
  ) {
    final colors = <Color>[
      const Color(0xFFF8F1DC),
      const Color(0xFFEAF4EA),
      const Color(0xFFEAF0FA),
      const Color(0xFFFFEEF3),
      const Color(0xFFECE7DD),
      const Color(0xFF222222),
    ];

    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('自定义背景'),
        message: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            runSpacing: 14,
            children: colors.map((color) {
              return GestureDetector(
                onTap: () {
                  ref
                      .read(readerViewModelProvider(bookId).notifier)
                      .setCustomBackground(color);
                  Navigator.pop(context);
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: CupertinoColors.systemGrey3),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  Widget _buildLayoutTab(
    BuildContext context,
    WidgetRef ref,
    ReaderState state,
    bool isDark,
    String bookId,
  ) {
    final vm = ref.read(readerViewModelProvider(bookId).notifier);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _buildSectionTitle('排版', isDark),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _stepRow(
                      '字体大小',
                      state.fontSize.toStringAsFixed(0),
                      () => vm.setFontSize(state.fontSize - 1),
                      () => vm.setFontSize(state.fontSize + 1),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _stepRow(
                      '字体间距',
                      state.letterSpacing.toStringAsFixed(1),
                      () => vm.setLetterSpacing(state.letterSpacing - 0.1),
                      () => vm.setLetterSpacing(state.letterSpacing + 0.1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _stepRow(
                      '标题间距',
                      state.titleSpacing.toStringAsFixed(0),
                      () => vm.setTitleSpacing(state.titleSpacing - 2),
                      () => vm.setTitleSpacing(state.titleSpacing + 2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _stepRow(
                      '左右间距',
                      state.pagePadding.toStringAsFixed(0),
                      () => vm.setPagePadding(state.pagePadding - 2),
                      () => vm.setPagePadding(state.pagePadding + 2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _stepRow(
                      '上边距',
                      state.topPadding.toStringAsFixed(0),
                      () => vm.setVerticalPadding(top: state.topPadding - 2),
                      () => vm.setVerticalPadding(top: state.topPadding + 2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _stepRow(
                      '下边距',
                      state.bottomPadding.toStringAsFixed(0),
                      () => vm.setVerticalPadding(
                        bottom: state.bottomPadding - 2,
                      ),
                      () => vm.setVerticalPadding(
                        bottom: state.bottomPadding + 2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _stepRow(
                      '行高',
                      state.lineHeight.toStringAsFixed(1),
                      () => vm.setLineHeight(state.lineHeight - 0.1),
                      () => vm.setLineHeight(state.lineHeight + 0.1),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _stepRow(
                      '段距',
                      state.paragraphSpacing.toStringAsFixed(0),
                      () => vm.setParagraphSpacing(state.paragraphSpacing - 2),
                      () => vm.setParagraphSpacing(state.paragraphSpacing + 2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _stepRow(
                      '缩进',
                      '${state.paragraphIndent}',
                      () => vm.setParagraphIndent(state.paragraphIndent - 1),
                      () => vm.setParagraphIndent(state.paragraphIndent + 1),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _stepRow(
                      '页脚高度',
                      state.footerHeight.toStringAsFixed(0),
                      () => vm.setFooterHeight(state.footerHeight - 5),
                      () => vm.setFooterHeight(state.footerHeight + 5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _buildSectionTitle('字体粗细', isDark),
        CupertinoSlidingSegmentedControl<int>(
          groupValue: state.fontWeightIndex,
          children: const {
            -1: SizedBox(width: 58, child: Center(child: Text('系统'))),
            0: SizedBox(width: 58, child: Center(child: Text('常规'))),
            1: SizedBox(width: 58, child: Center(child: Text('中等'))),
            2: SizedBox(width: 58, child: Center(child: Text('加粗'))),
          },
          onValueChanged: (val) {
            if (val != null) vm.setFontWeight(val);
          },
        ),
      ],
    );
  }

  Widget _stepRow(
    String label,
    String value,
    VoidCallback onDecrease,
    VoidCallback onIncrease,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 58,
          child: Text(
            label,
            style: const TextStyle(
              color: CupertinoColors.secondaryLabel,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        CupertinoButton(
          minSize: 28,
          padding: EdgeInsets.zero,
          onPressed: onDecrease,
          child: const Icon(CupertinoIcons.minus, size: 18),
        ),
        Expanded(
          child: Center(
            child: Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        CupertinoButton(
          minSize: 28,
          padding: EdgeInsets.zero,
          onPressed: onIncrease,
          child: const Icon(CupertinoIcons.plus, size: 18),
        ),
      ],
    );
  }

  Widget _buildAdvancedTab(
    BuildContext context,
    WidgetRef ref,
    ReaderState state,
    bool isDark,
    String bookId,
  ) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // 翻页模式
        _buildSectionTitle('翻页模式', isDark),
        CupertinoSlidingSegmentedControl<ReaderMode>(
          groupValue: state.mode,
          children: const {
            ReaderMode.scroll: SizedBox(
              width: 70,
              child: Center(child: Text('滑动')),
            ),
            ReaderMode.pageTurn: SizedBox(
              width: 70,
              child: Center(child: Text('平移')),
            ),
            ReaderMode.cover: SizedBox(
              width: 70,
              child: Center(child: Text('覆盖')),
            ),
          },
          onValueChanged: (val) {
            if (val != null) {
              ref.read(readerViewModelProvider(bookId).notifier).setMode(val);
            }
          },
        ),

        const SizedBox(height: 24),

        _buildSectionTitle('点击区域', isDark),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: List.generate(3, (row) {
              return Row(
                children: List.generate(3, (col) {
                  final index = row * 3 + col;
                  final action = state.tapZoneActions.length == 9
                      ? state.tapZoneActions[index]
                      : ReaderTapAction.defaultZones[index];
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: CupertinoButton(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        color: _tapActionColor(action, isDark),
                        borderRadius: BorderRadius.circular(8),
                        onPressed: () {
                          _showTapActionPicker(context, ref, bookId, index);
                        },
                        child: Text(
                          action.label,
                          style: const TextStyle(
                            fontSize: 12,
                            color: CupertinoColors.white,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              );
            }),
          ),
        ),

        const SizedBox(height: 8),
        Text(
          '至少保留一个“菜单”区域；如果全部关掉，系统会自动把中间格恢复为菜单。',
          style: TextStyle(
            fontSize: 12,
            height: 1.35,
            color: isDark
                ? CupertinoColors.systemGrey2
                : CupertinoColors.systemGrey,
          ),
        ),

        const SizedBox(height: 24),

        // 更多开关
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _buildSwitchRow('屏幕常亮', state.keepScreenOn, (val) {
                ref
                    .read(readerViewModelProvider(bookId).notifier)
                    .toggleKeepScreenOn();
              }, isDark),
              Container(
                height: 1,
                color: isDark
                    ? const Color(0xFF38383A)
                    : CupertinoColors.systemGrey5,
                margin: const EdgeInsets.only(left: 16),
              ),
              _buildSwitchRow('音量键翻页', state.volumeKeyTurn, (val) {
                ref
                    .read(readerViewModelProvider(bookId).notifier)
                    .toggleVolumeKeyTurn();
              }, isDark),
              Container(
                height: 1,
                color: isDark
                    ? const Color(0xFF38383A)
                    : CupertinoColors.systemGrey5,
                margin: const EdgeInsets.only(left: 16),
              ),
              _buildSwitchRow('两端对齐排版', state.isJustify, (val) {
                ref
                    .read(readerViewModelProvider(bookId).notifier)
                    .setJustify(val);
              }, isDark),
            ],
          ),
        ),
      ],
    );
  }

  Color _tapActionColor(ReaderTapAction action, bool isDark) {
    switch (action) {
      case ReaderTapAction.previousPage:
        return const Color(0xFF4F5D9D);
      case ReaderTapAction.nextPage:
        return const Color(0xFF4D873F);
      case ReaderTapAction.previousChapter:
        return const Color(0xFF5967AA);
      case ReaderTapAction.nextChapter:
        return const Color(0xFF5B9A49);
      case ReaderTapAction.menu:
        return const Color(0xFFB67A3E);
      case ReaderTapAction.disabled:
        return isDark ? const Color(0xFF3A3A3C) : CupertinoColors.systemGrey3;
    }
  }

  void _showTapActionPicker(
    BuildContext context,
    WidgetRef ref,
    String bookId,
    int index,
  ) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text('设置第 ${index + 1} 格'),
        actions: ReaderTapAction.values.map((action) {
          return CupertinoActionSheetAction(
            onPressed: () {
              ref
                  .read(readerViewModelProvider(bookId).notifier)
                  .setTapZoneAction(index, action);
              Navigator.pop(context);
            },
            child: Text(action.label),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isDark
              ? CupertinoColors.systemGrey2
              : CupertinoColors.systemGrey,
        ),
      ),
    );
  }

  Widget _buildSwitchRow(
    String title,
    bool value,
    ValueChanged<bool> onChanged,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              color: isDark ? CupertinoColors.white : CupertinoColors.black,
            ),
          ),
          CupertinoSwitch(
            value: value,
            activeColor: AppColors.primaryPurple,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
