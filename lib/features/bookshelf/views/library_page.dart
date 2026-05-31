import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../viewmodels/bookshelf_viewmodel.dart';
import '../../../data/models/book_group.dart';
import '../../../data/models/book.dart';
import '../../../widgets/book_cover.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  int? _selectedGroupId;
  bool _isManaging = false;
  final Set<int> _selectedBookIds = {};

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bookshelfViewModelProvider);
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    final bgColor = CupertinoTheme.of(context).scaffoldBackgroundColor;

    List<Book> displayBooks = _selectedGroupId == null
        ? state.allBooks
        : state.allBooks.where((b) => b.groupId == _selectedGroupId).toList();

    return CupertinoPageScaffold(
      backgroundColor: bgColor,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('所有书籍'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isManaging)
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: _selectedBookIds.isEmpty
                    ? null
                    : () => _confirmDeleteSelected(context),
                child: Icon(
                  CupertinoIcons.trash,
                  color: _selectedBookIds.isEmpty
                      ? CupertinoColors.systemGrey
                      : CupertinoColors.destructiveRed,
                ),
              ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(_isManaging ? '完成' : '管理'),
              onPressed: () {
                setState(() {
                  _isManaging = !_isManaging;
                  _selectedBookIds.clear();
                });
              },
            ),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: const Text('分组'),
              onPressed: () {
                _showGroupManager(context, state.groups);
              },
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              child: const Icon(CupertinoIcons.folder_badge_plus),
              onPressed: () {
                _showCreateGroupDialog(context);
              },
            ),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // 分组过滤栏
            Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildGroupChip('全部', null, _selectedGroupId == null, isDark),
                  ...state.groups.map((g) {
                    return _buildGroupChip(
                      g.name,
                      g.id,
                      _selectedGroupId == g.id,
                      isDark,
                      onLongPress: () => _showGroupOptions(context, g),
                    );
                  }),
                ],
              ),
            ),

            // 书籍网格
            Expanded(
              child: displayBooks.isEmpty
                  ? const Center(child: Text('当前分组没有书籍'))
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.65,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 16,
                          ),
                      itemCount: displayBooks.length,
                      itemBuilder: (context, index) {
                        return _buildBookItem(
                          context,
                          displayBooks[index],
                          state.groups,
                          isDark,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupChip(
    String label,
    int? id,
    bool isSelected,
    bool isDark, {
    VoidCallback? onLongPress,
  }) {
    final color = isSelected
        ? CupertinoColors.activeBlue
        : (isDark ? CupertinoColors.systemGrey6 : CupertinoColors.systemGrey5);
    final textColor = isSelected
        ? CupertinoColors.white
        : (isDark ? CupertinoColors.white : CupertinoColors.black);

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedGroupId = id;
        });
      },
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBookItem(
    BuildContext context,
    Book book,
    List<BookGroup> groups,
    bool isDark,
  ) {
    final selected = _selectedBookIds.contains(book.id);
    return GestureDetector(
      onTap: () {
        if (_isManaging) {
          setState(() {
            if (selected) {
              _selectedBookIds.remove(book.id);
            } else {
              _selectedBookIds.add(book.id);
            }
          });
        } else {
          context.push('/reader/${book.id}');
        }
      },
      onLongPress: () => _showBookOptions(context, book, groups),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  BookCover(book: book),
                  if (_isManaging)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Icon(
                        selected
                            ? CupertinoIcons.check_mark_circled_solid
                            : CupertinoIcons.circle,
                        color: CupertinoColors.white,
                        size: 22,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  void _showCreateGroupDialog(BuildContext context) {
    String groupName = '';
    showCupertinoDialog(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: const Text('新建分组'),
          content: Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: CupertinoTextField(
              placeholder: '分组名称',
              onChanged: (v) => groupName = v,
            ),
          ),
          actions: [
            CupertinoDialogAction(
              child: const Text('取消'),
              onPressed: () => Navigator.pop(context),
            ),
            CupertinoDialogAction(
              child: const Text('创建'),
              onPressed: () {
                if (groupName.isNotEmpty) {
                  ref
                      .read(bookshelfViewModelProvider.notifier)
                      .createGroup(groupName);
                }
                Navigator.pop(context);
              },
            ),
          ],
        );
      },
    );
  }

  void _showGroupOptions(BuildContext context, BookGroup group) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) {
        return CupertinoActionSheet(
          title: Text('操作分组: ${group.name}'),
          actions: [
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                ref
                    .read(bookshelfViewModelProvider.notifier)
                    .deleteGroup(group.id);
                if (_selectedGroupId == group.id) {
                  setState(() => _selectedGroupId = null);
                }
                Navigator.pop(context);
              },
              child: const Text('删除分组 (书籍移至全部)'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context),
          ),
        );
      },
    );
  }

  void _showGroupManager(BuildContext context, List<BookGroup> groups) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) {
        return CupertinoActionSheet(
          title: const Text('管理分组'),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                _showCreateGroupDialog(context);
              },
              child: const Text('新建分组'),
            ),
            ...groups.map((group) {
              return CupertinoActionSheetAction(
                isDestructiveAction: true,
                onPressed: () {
                  ref
                      .read(bookshelfViewModelProvider.notifier)
                      .deleteGroup(group.id);
                  if (_selectedGroupId == group.id) {
                    setState(() => _selectedGroupId = null);
                  }
                  Navigator.pop(context);
                },
                child: Text('删除 ${group.name}'),
              );
            }),
            if (groups.isEmpty)
              CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(context),
                child: const Text('暂无分组'),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context),
          ),
        );
      },
    );
  }

  void _confirmDeleteSelected(BuildContext context) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('删除书籍'),
        content: Text('确定删除选中的 ${_selectedBookIds.length} 本书吗？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              final ids = List<int>.from(_selectedBookIds);
              for (final id in ids) {
                await ref
                    .read(bookshelfViewModelProvider.notifier)
                    .deleteBook(id);
              }
              if (!mounted) return;
              setState(() {
                _selectedBookIds.clear();
                _isManaging = false;
              });
              Navigator.pop(context);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showBookOptions(
    BuildContext context,
    Book book,
    List<BookGroup> groups,
  ) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) {
        return CupertinoActionSheet(
          title: Text('移动《${book.title}》到...'),
          actions: [
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                ref
                    .read(bookshelfViewModelProvider.notifier)
                    .deleteBook(book.id);
                Navigator.pop(context);
              },
              child: const Text('删除书籍'),
            ),
            CupertinoActionSheetAction(
              onPressed: () {
                ref
                    .read(bookshelfViewModelProvider.notifier)
                    .moveBookToGroup(book, null);
                Navigator.pop(context);
              },
              child: const Text('移出分组'),
            ),
            ...groups.map((g) {
              return CupertinoActionSheetAction(
                onPressed: () {
                  ref
                      .read(bookshelfViewModelProvider.notifier)
                      .moveBookToGroup(book, g.id);
                  Navigator.pop(context);
                },
                child: Text(g.name),
              );
            }),
          ],
          cancelButton: CupertinoActionSheetAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context),
          ),
        );
      },
    );
  }
}
