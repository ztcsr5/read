import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/book_source.dart';
import '../../../data/repositories/book_repository.dart';

class WebSourcePage extends ConsumerStatefulWidget {
  const WebSourcePage({super.key});

  @override
  ConsumerState<WebSourcePage> createState() => _WebSourcePageState();
}

class _WebSourcePageState extends ConsumerState<WebSourcePage> {
  final _nameController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _searchUrlController = TextEditingController();
  final _bookListController = TextEditingController(text: '.book, .result li');
  final _nameRuleController = TextEditingController(text: 'a@text');
  final _authorRuleController = TextEditingController(text: '.author@text');
  final _coverRuleController = TextEditingController(text: 'img@src');
  final _bookUrlRuleController = TextEditingController(text: 'a@href');
  final _tocRuleController = TextEditingController(text: '.chapter-list a');
  final _contentRuleController = TextEditingController(text: '#content');

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _searchUrlController.dispose();
    _bookListController.dispose();
    _nameRuleController.dispose();
    _authorRuleController.dispose();
    _coverRuleController.dispose();
    _bookUrlRuleController.dispose();
    _tocRuleController.dispose();
    _contentRuleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Web 写源'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _save,
          child: const Text('保存'),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CupertinoButton.filled(
              onPressed: () {
                context.push('/source_json_editor', extra: _draftSource());
              },
              child: const Text('直接粘贴 / 编辑完整 JSON 书源'),
            ),
            const SizedBox(height: 10),
            Text(
              '适合从开源阅读、网页仓库或自己手写 Legado JSON。下面表单只适合简单 CSS 源。',
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 18),
            _field(_nameController, '书源名称', '例如：某某中文网'),
            _field(_baseUrlController, '网站地址', 'https://example.com'),
            _field(
              _searchUrlController,
              '搜索地址',
              'https://example.com/search?q={{key}}',
            ),
            const SizedBox(height: 12),
            const Text(
              '搜索规则',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            _field(_bookListController, '结果列表选择器', '.book, .result li'),
            _field(_nameRuleController, '书名规则', 'a@text'),
            _field(_authorRuleController, '作者规则', '.author@text'),
            _field(_coverRuleController, '封面规则', 'img@src'),
            _field(_bookUrlRuleController, '详情链接规则', 'a@href'),
            const SizedBox(height: 12),
            const Text(
              '章节与正文',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            _field(_tocRuleController, '目录链接规则', '.chapter-list a'),
            _field(_contentRuleController, '正文内容规则', '#content'),
            const SizedBox(height: 20),
            CupertinoButton(
              color: CupertinoColors.systemGrey5,
              onPressed: () {
                context.push('/source_json_editor', extra: _draftSource());
              },
              child: const Text(
                '转完整 JSON 编辑',
                style: TextStyle(color: CupertinoColors.activeBlue),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '提示：当前写源会生成标准 Legado 风格字段，先用于项目内的搜索、目录、正文解析。复杂登录、加密、JS 渲染源后续再加高级规则。',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String placeholder,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          CupertinoTextField(
            controller: controller,
            placeholder: placeholder,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    final searchUrl = _searchUrlController.text.trim();
    if (name.isEmpty || baseUrl.isEmpty || searchUrl.isEmpty) {
      _alert('请至少填写书源名称、网站地址和搜索地址');
      return;
    }

    final source = _draftSource();

    await ref.read(bookRepositoryProvider).saveBookSource(source);
    if (!mounted) return;
    await _alert('已保存 Web 书源');
    if (mounted) Navigator.pop(context);
  }

  BookSource _draftSource() {
    final name = _nameController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    final searchUrl = _searchUrlController.text.trim();
    return BookSource()
      ..bookSourceName = name.isEmpty ? '新建 Web 小说源' : name
      ..bookSourceUrl = baseUrl.isEmpty ? 'https://example.com' : baseUrl
      ..bookSourceType = 0
      ..bookSourceGroup = 'Web写源'
      ..searchUrl = searchUrl.isEmpty
          ? '/search?keyword={{key}}&page={{page}}'
          : searchUrl
      ..enabled = true
      ..ruleSearch = jsonEncode({
        'bookList': _bookListController.text.trim(),
        'name': _nameRuleController.text.trim(),
        'author': _authorRuleController.text.trim(),
        'coverUrl': _coverRuleController.text.trim(),
        'bookUrl': _bookUrlRuleController.text.trim(),
      })
      ..ruleBookInfo = jsonEncode({
        'name': 'h1@text',
        'author': '.author@text',
        'coverUrl': '.cover img@src',
        'intro': '.intro@text',
        'tocUrl': '.catalog a@href',
      })
      ..ruleToc = jsonEncode({
        'chapterList': _tocRuleController.text.trim(),
        'chapterName': '@text',
        'chapterUrl': '@href',
        'nextTocUrl': '',
      })
      ..ruleContent = jsonEncode({
        'content': _contentRuleController.text.trim(),
        'nextContentUrl': '',
        'replaceRegex': '',
      });
  }

  Future<void> _alert(String message) {
    return showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('提示'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
