import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/book_source.dart';
import '../../../data/models/rss_source.dart';
import '../../../data/models/source_catalog.dart';
import '../../../widgets/ios_navigation_bar.dart';
import '../viewmodels/book_source_viewmodel.dart';
import '../../../data/repositories/book_repository.dart';
import '../../source_diagnostic/services/source_generator_service.dart';

class SourceManagementPage extends ConsumerStatefulWidget {
  const SourceManagementPage({super.key});

  @override
  ConsumerState<SourceManagementPage> createState() =>
      _SourceManagementPageState();
}

class _SourceManagementPageState extends ConsumerState<SourceManagementPage> {
  int _selectedTab = 0; // 0: 书源, 1: 仓库, 2: RSS
  bool _isManaging = false;
  final _searchController = TextEditingController();
  final Set<int> _selectedBookSourceIds = {};
  final Set<int> _selectedCatalogIds = {};
  final Set<int> _selectedRssSourceIds = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bookSourceViewModelProvider);
    final bgColor = CupertinoTheme.of(context).scaffoldBackgroundColor;
    final keyword = _searchController.text.trim().toLowerCase();
    final visibleBookSources = _filterBookSources(state.sources, keyword);
    final visibleCatalogs = _filterCatalogs(state.catalogs, keyword);
    final visibleRssSources = _filterRssSources(state.rssSources, keyword);
    final hasItems = _currentIds(
      visibleBookSources,
      visibleCatalogs,
      visibleRssSources,
    ).isNotEmpty;
    final totalCount = switch (_selectedTab) {
      0 => state.sources.length,
      1 => state.catalogs.length,
      _ => state.rssSources.length,
    };

    ref.listen<BookSourceState>(bookSourceViewModelProvider, (previous, next) {
      if (next.error != null &&
          next.error != previous?.error &&
          context.mounted) {
        _showAlert(context, '提示', next.error!);
      }
      if (next.message != null &&
          next.message != previous?.message &&
          context.mounted) {
        _showAlert(context, '完成', next.message!);
      }
    });

    return CupertinoPageScaffold(
      backgroundColor: bgColor,
      child: CustomScrollView(
        slivers: [
          IosNavigationBar(
            title: '源管理',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (totalCount > 0)
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: Text(_isManaging ? '完成' : '管理'),
                    onPressed: () {
                      setState(() {
                        _isManaging = !_isManaging;
                        if (!_isManaging) _clearSelection();
                      });
                    },
                  ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  child: const Icon(CupertinoIcons.add),
                  onPressed: () => _showImportDialog(context, ref),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: CupertinoSlidingSegmentedControl<int>(
                groupValue: _selectedTab,
                children: const {
                  0: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Text('书源'),
                  ),
                  1: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Text('仓库'),
                  ),
                  2: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Text('RSS'),
                  ),
                },
                onValueChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedTab = value;
                    _searchController.clear();
                    _clearSelection();
                  });
                },
              ),
            ),
          ),
          if (totalCount > 0)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: CupertinoSearchTextField(
                  controller: _searchController,
                  placeholder: '搜索名称、地址、分组',
                  onChanged: (_) {
                    setState(_clearSelection);
                  },
                ),
              ),
            ),
          if (_isManaging && hasItems)
            _buildManageBar(
              visibleBookSources,
              visibleCatalogs,
              visibleRssSources,
            ),
          if (state.isLoading)
            const SliverFillRemaining(
              child: Center(child: CupertinoActivityIndicator()),
            )
          else if (!hasItems)
            SliverFillRemaining(child: _buildEmptyState(totalCount, keyword))
          else if (_selectedTab == 0)
            _buildBookSourceList(visibleBookSources)
          else if (_selectedTab == 1)
            _buildCatalogList(visibleCatalogs)
          else
            _buildRssList(visibleRssSources),
        ],
      ),
    );
  }

  Widget _buildEmptyState(int totalCount, String keyword) {
    final text = totalCount > 0 && keyword.isNotEmpty
        ? '没有匹配的结果'
        : switch (_selectedTab) {
            0 => '暂无书源\n请点击右上角导入书源 JSON',
            1 => '暂无书源仓库\n可导入 Yiove 等仓库订阅 JSON',
            _ => '暂无 RSS\n普通文章订阅会放在这里',
          };
    return Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: CupertinoColors.systemGrey),
      ),
    );
  }

  SliverList _buildBookSourceList(List<BookSource> sources) {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final source = sources[index];
        final selected = _selectedBookSourceIds.contains(source.id);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: () {
            setState(() {
              _isManaging = true;
              _selectedBookSourceIds.add(source.id);
            });
          },
          child: CupertinoListTile(
            onTap: () {
              if (_isManaging) {
                _toggleSelection(_selectedBookSourceIds, source.id);
              } else {
                context.push('/source_explore', extra: source);
              }
            },
            title: Text(source.bookSourceName),
            subtitle: Text(
              _joinNonEmpty([source.bookSourceUrl, source.bookSourceGroup]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            additionalInfo: Text(source.enabled ? '启用' : '停用'),
            trailing: _isManaging
                ? _SelectionMark(selected: selected)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CupertinoButton(
                        minSize: 32,
                        padding: EdgeInsets.zero,
                        child: const Icon(CupertinoIcons.doc_text),
                        onPressed: () =>
                            context.push('/source_json_editor', extra: source),
                      ),
                      CupertinoButton(
                        minSize: 32,
                        padding: EdgeInsets.zero,
                        child: const Icon(
                          CupertinoIcons.waveform_path_ecg,
                          color: Color(0xFF10B981),
                        ),
                        onPressed: () =>
                            context.push('/source_diagnostic', extra: source),
                      ),
                      CupertinoButton(
                        minSize: 32,
                        padding: EdgeInsets.zero,
                        child: const Icon(CupertinoIcons.checkmark_seal),
                        onPressed: () =>
                            context.push('/source_test', extra: source),
                      ),
                      CupertinoButton(
                        minSize: 32,
                        padding: EdgeInsets.zero,
                        child: const Icon(
                          CupertinoIcons.trash,
                          color: CupertinoColors.destructiveRed,
                        ),
                        onPressed: () => ref
                            .read(bookSourceViewModelProvider.notifier)
                            .deleteSource(source.id),
                      ),
                    ],
                  ),
          ),
        );
      }, childCount: sources.length),
    );
  }

  SliverList _buildCatalogList(List<SourceCatalog> catalogs) {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final catalog = catalogs[index];
        final selected = _selectedCatalogIds.contains(catalog.id);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: () {
            setState(() {
              _isManaging = true;
              _selectedCatalogIds.add(catalog.id);
            });
          },
          child: CupertinoListTile(
            onTap: () {
              if (_isManaging) {
                _toggleSelection(_selectedCatalogIds, catalog.id);
              } else {
                context.push('/source_catalog', extra: catalog);
              }
            },
            title: Text(catalog.name),
            subtitle: Text(
              catalog.comment?.isNotEmpty == true
                  ? catalog.comment!
                  : catalog.url,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            additionalInfo: Text(catalog.enabled ? '启用' : '停用'),
            trailing: _isManaging
                ? _SelectionMark(selected: selected)
                : CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Icon(CupertinoIcons.square_list),
                    onPressed: () =>
                        context.push('/source_catalog', extra: catalog),
                  ),
          ),
        );
      }, childCount: catalogs.length),
    );
  }

  SliverList _buildRssList(List<RssSource> rssSources) {
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final source = rssSources[index];
        final selected = _selectedRssSourceIds.contains(source.id);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: () {
            setState(() {
              _isManaging = true;
              _selectedRssSourceIds.add(source.id);
            });
          },
          child: CupertinoListTile(
            onTap: () {
              if (_isManaging) {
                _toggleSelection(_selectedRssSourceIds, source.id);
              } else {
                context.push('/rss_articles', extra: source);
              }
            },
            title: Text(source.sourceName),
            subtitle: Text(
              _joinNonEmpty([source.sourceUrl, source.sourceGroup]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            additionalInfo: Text(source.enabled ? '启用' : '停用'),
            trailing: _isManaging
                ? _SelectionMark(selected: selected)
                : CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Icon(
                      CupertinoIcons.trash,
                      color: CupertinoColors.destructiveRed,
                    ),
                    onPressed: () => ref
                        .read(bookSourceViewModelProvider.notifier)
                        .deleteRssSource(source.id),
                  ),
          ),
        );
      }, childCount: rssSources.length),
    );
  }

  SliverToBoxAdapter _buildManageBar(
    List<BookSource> visibleBookSources,
    List<SourceCatalog> visibleCatalogs,
    List<RssSource> visibleRssSources,
  ) {
    final selectedCount = _currentSelectedIds().length;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                '已选 $selectedCount',
                style: const TextStyle(
                  color: CupertinoColors.systemGrey,
                  fontSize: 14,
                ),
              ),
            ),
            _smallAction('全选', () {
              setState(
                () => _selectAll(
                  visibleBookSources,
                  visibleCatalogs,
                  visibleRssSources,
                ),
              );
            }),
            _smallAction('反选', () {
              setState(
                () => _invertSelection(
                  visibleBookSources,
                  visibleCatalogs,
                  visibleRssSources,
                ),
              );
            }),
            if (_selectedTab == 0)
              _smallAction('测源', () {
                final idsToTest = selectedCount == 0
                    ? visibleBookSources.map((s) => s.id).toSet()
                    : _selectedBookSourceIds;
                final sourcesToTest = visibleBookSources
                    .where((s) => idsToTest.contains(s.id))
                    .toList();
                if (sourcesToTest.isNotEmpty) {
                  context.push('/source_batch_check', extra: sourcesToTest);
                }
              }),
            _smallAction(
              '启用',
              selectedCount == 0 || _selectedTab == 2
                  ? null
                  : () => _setSelectedEnabled(true),
            ),
            _smallAction(
              '停用',
              selectedCount == 0 || _selectedTab == 2
                  ? null
                  : () => _setSelectedEnabled(false),
            ),
            _smallAction(
              '删除',
              selectedCount == 0 ? null : _confirmDeleteSelected,
              destructive: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallAction(
    String label,
    VoidCallback? onPressed, {
    bool destructive = false,
  }) {
    return CupertinoButton(
      minSize: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      color: destructive
          ? CupertinoColors.destructiveRed.withOpacity(0.12)
          : CupertinoColors.systemGrey5,
      disabledColor: CupertinoColors.systemGrey5.withOpacity(0.5),
      borderRadius: BorderRadius.circular(8),
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          color: destructive
              ? CupertinoColors.destructiveRed
              : CupertinoColors.activeBlue,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Future<void> _setSelectedEnabled(bool enabled) async {
    final notifier = ref.read(bookSourceViewModelProvider.notifier);
    if (_selectedTab == 0) {
      await notifier.setSourcesEnabled(_selectedBookSourceIds, enabled);
    } else if (_selectedTab == 1) {
      await notifier.setCatalogsEnabled(_selectedCatalogIds, enabled);
    }
    if (!mounted) return;
    setState(() {
      _isManaging = false;
      _clearSelection();
    });
  }

  Set<int> _currentSelectedIds() {
    return switch (_selectedTab) {
      0 => _selectedBookSourceIds,
      1 => _selectedCatalogIds,
      _ => _selectedRssSourceIds,
    };
  }

  Set<int> _currentIds(
    List<BookSource> bookSources,
    List<SourceCatalog> catalogs,
    List<RssSource> rssSources,
  ) {
    return switch (_selectedTab) {
      0 => bookSources.map((source) => source.id).toSet(),
      1 => catalogs.map((catalog) => catalog.id).toSet(),
      _ => rssSources.map((source) => source.id).toSet(),
    };
  }

  void _toggleSelection(Set<int> target, int id) {
    setState(() {
      if (!target.add(id)) target.remove(id);
    });
  }

  void _selectAll(
    List<BookSource> bookSources,
    List<SourceCatalog> catalogs,
    List<RssSource> rssSources,
  ) {
    final selected = _currentSelectedIds();
    selected
      ..clear()
      ..addAll(_currentIds(bookSources, catalogs, rssSources));
  }

  void _invertSelection(
    List<BookSource> bookSources,
    List<SourceCatalog> catalogs,
    List<RssSource> rssSources,
  ) {
    final selected = _currentSelectedIds();
    final visible = _currentIds(bookSources, catalogs, rssSources);
    final next = visible.difference(selected);
    selected
      ..removeAll(visible)
      ..addAll(next);
  }

  void _clearSelection() {
    _selectedBookSourceIds.clear();
    _selectedCatalogIds.clear();
    _selectedRssSourceIds.clear();
  }

  Future<void> _confirmDeleteSelected() async {
    final selectedCount = _currentSelectedIds().length;
    await showCupertinoDialog(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('删除确认'),
        content: Text('确定删除选中的 $selectedCount 个源吗？'),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(dialogContext),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('删除'),
            onPressed: () async {
              Navigator.pop(dialogContext);
              final notifier = ref.read(bookSourceViewModelProvider.notifier);
              if (_selectedTab == 0) {
                await notifier.deleteSources(_selectedBookSourceIds);
              } else if (_selectedTab == 1) {
                await notifier.deleteCatalogs(_selectedCatalogIds);
              } else {
                await notifier.deleteRssSources(_selectedRssSourceIds);
              }
              if (!mounted) return;
              setState(() {
                _isManaging = false;
                _clearSelection();
              });
            },
          ),
        ],
      ),
    );
  }

  void _showImportDialog(BuildContext context, WidgetRef ref) {
    final rootContext = context;
    String inputText = '';
    showCupertinoModalPopup(
      context: context,
      builder: (context) {
        return Material(
          type: MaterialType.transparency,
          child: Container(
            height: MediaQuery.of(context).size.height * 0.72,
            color: CupertinoTheme.of(context).scaffoldBackgroundColor,
            child: SafeArea(
              child: Column(
                children: [
                  CupertinoNavigationBar(
                    middle: const Text('导入源'),
                    leading: CupertinoButton(
                      padding: EdgeInsets.zero,
                      child: const Text('取消'),
                      onPressed: () => Navigator.pop(context),
                    ),
                    trailing: CupertinoButton(
                      padding: EdgeInsets.zero,
                      child: const Text('导入'),
                      onPressed: () {
                        _importInput(inputText, ref);
                        Navigator.pop(context);
                      },
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            '支持书源 JSON、书源仓库订阅 JSON、RSS/Atom、阅读导入链接和网页分享入口。大文件建议选择本地 JSON。',
                            style: TextStyle(
                              fontSize: 13,
                              color: CupertinoColors.systemGrey,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: CupertinoTextField(
                              placeholder: '粘贴 JSON、HTTP 地址、分享页或 yuedu:// 链接',
                              maxLines: null,
                              expands: true,
                              textAlignVertical: TextAlignVertical.top,
                              onChanged: (val) => inputText = val,
                            ),
                          ),
                          const SizedBox(height: 16),
                          CupertinoButton(
                            child: const Text('选择本地 JSON 文件'),
                            onPressed: () {
                              Navigator.pop(context);
                              _pickAndImportJsonFile(ref);
                            },
                          ),
                          const SizedBox(height: 8),
                          CupertinoButton(
                            child: const Text('打开内置浏览器导入'),
                            onPressed: () {
                              final url = inputText.trim().isEmpty
                                  ? null
                                  : inputText.trim();
                              Navigator.pop(context);
                              rootContext.push('/webview_import', extra: url);
                            },
                          ),
                          const SizedBox(height: 8),
                          CupertinoButton(
                            child: const Text('一键自动生成书源'),
                            onPressed: () {
                              final url = inputText.trim();
                              Navigator.pop(context);
                              _generateBookSourceFromUrl(url, ref);
                            },
                          ),
                          const SizedBox(height: 8),
                          CupertinoButton.filled(
                            child: const Text('自动识别并导入'),
                            onPressed: () {
                              _importInput(inputText, ref);
                              if (context.mounted) Navigator.pop(context);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _generateBookSourceFromUrl(String url, WidgetRef ref) async {
    final rootContext = context;
    if (url.trim().isEmpty || !url.trim().startsWith('http')) {
      _showAlert(context, '输入错误', '请输入以 http:// 或 https:// 开头的网站主页地址。');
      return;
    }

    showCupertinoDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const CupertinoAlertDialog(
        title: Text('分析与生成中'),
        content: Padding(
          padding: EdgeInsets.only(top: 12.0),
          child: CupertinoActivityIndicator(),
        ),
      ),
    );

    try {
      final generated = await SourceGeneratorService.generate(url);
      final repo = ref.read(bookRepositoryProvider);
      await repo.saveBookSource(generated);
      await ref.read(bookSourceViewModelProvider.notifier).loadSources();

      if (rootContext.mounted) {
        Navigator.pop(rootContext);
        _showAlert(
          rootContext,
          '生成成功',
          '已自动识别网页结构并生成书源：${generated.bookSourceName}',
        );
      }
    } catch (e) {
      if (rootContext.mounted) {
        Navigator.pop(rootContext);
        _showAlert(rootContext, '生成失败', '自动识别或分析网站失败: $e');
      }
    }
  }

  Future<void> _pickAndImportJsonFile(WidgetRef ref) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json', 'txt'],
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      final notifier = ref.read(bookSourceViewModelProvider.notifier);
      if (file.path != null) {
        await notifier.importFromFilePath(file.path!);
        return;
      }

      final bytesResult = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json', 'txt'],
        withData: true,
      );
      final bytes = bytesResult?.files.single.bytes;
      if (bytes == null) {
        notifier.reportImportError('没有读取到文件内容，请换一个 JSON 文件重试。');
        return;
      }
      await notifier.importFromBytes(bytes, originalUrl: file.name);
    } catch (e) {
      final notifier = ref.read(bookSourceViewModelProvider.notifier);
      notifier.reportImportError('选择文件失败: $e');
    }
  }

  void _importInput(String inputText, WidgetRef ref) {
    final value = inputText.trim();
    if (value.isEmpty) return;
    ref.read(bookSourceViewModelProvider.notifier).importSmartInput(value);
  }

  void _showAlert(BuildContext context, String title, String content) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          CupertinoDialogAction(
            child: const Text('确定'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  List<BookSource> _filterBookSources(
    List<BookSource> sources,
    String keyword,
  ) {
    if (keyword.isEmpty) return sources;
    return sources.where((source) {
      return _containsKeyword(keyword, [
        source.bookSourceName,
        source.bookSourceUrl,
        source.bookSourceGroup,
        source.customConfig,
      ]);
    }).toList();
  }

  List<SourceCatalog> _filterCatalogs(
    List<SourceCatalog> catalogs,
    String keyword,
  ) {
    if (keyword.isEmpty) return catalogs;
    return catalogs.where((catalog) {
      return _containsKeyword(keyword, [
        catalog.name,
        catalog.url,
        catalog.group,
        catalog.comment,
      ]);
    }).toList();
  }

  List<RssSource> _filterRssSources(List<RssSource> sources, String keyword) {
    if (keyword.isEmpty) return sources;
    return sources.where((source) {
      return _containsKeyword(keyword, [
        source.sourceName,
        source.sourceUrl,
        source.sourceGroup,
        source.sourceComment,
      ]);
    }).toList();
  }

  bool _containsKeyword(String keyword, List<String?> values) {
    return values.whereType<String>().any(
      (value) => value.toLowerCase().contains(keyword),
    );
  }

  String _joinNonEmpty(List<String?> values) {
    final result = values
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(' · ');
    return result.isEmpty ? '-' : result;
  }
}

class _SelectionMark extends StatelessWidget {
  final bool selected;

  const _SelectionMark({required this.selected});

  @override
  Widget build(BuildContext context) {
    return Icon(
      selected
          ? CupertinoIcons.check_mark_circled_solid
          : CupertinoIcons.circle,
      color: selected
          ? CupertinoColors.activeBlue
          : CupertinoColors.systemGrey3,
    );
  }
}
