import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../data/models/book_source.dart';
import '../viewmodels/book_source_viewmodel.dart';

class SourceJsonEditorPage extends ConsumerStatefulWidget {
  final BookSource source;

  const SourceJsonEditorPage({super.key, required this.source});

  @override
  ConsumerState<SourceJsonEditorPage> createState() =>
      _SourceJsonEditorPageState();
}

class _SourceJsonEditorPageState extends ConsumerState<SourceJsonEditorPage> {
  late final TextEditingController _controller;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _prettyJson(widget.source));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111111) : const Color(0xFFF7F7FA);
    final editorBg = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF111827);

    return CupertinoPageScaffold(
      backgroundColor: bg,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('编辑书源 JSON'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _saving ? null : _save,
          child: _saving
              ? const CupertinoActivityIndicator()
              : const Text('保存'),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.source.bookSourceName,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.source.bookSourceUrl,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: CupertinoColors.systemGrey,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _actionButton('粘贴', _pasteFromClipboard),
                      _actionButton('格式化', _format),
                      _actionButton('重置', _reset),
                      _actionButton('校验', _validateOnly),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: CupertinoColors.destructiveRed,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                decoration: BoxDecoration(
                  color: editorBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF2C2C2E)
                        : const Color(0xFFE5E7EB),
                  ),
                ),
                child: CupertinoTextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  padding: const EdgeInsets.all(12),
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    height: 1.35,
                    fontFamily: 'Menlo',
                  ),
                  decoration: const BoxDecoration(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(String label, VoidCallback onPressed) {
    return CupertinoButton(
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: CupertinoColors.systemGrey5,
      borderRadius: BorderRadius.circular(8),
      onPressed: onPressed,
      child: Text(
        label,
        style: const TextStyle(
          color: CupertinoColors.activeBlue,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _format() {
    try {
      final decoded = _decodeSingleSourceJson(_controller.text);
      _controller.text = const JsonEncoder.withIndent('  ').convert(decoded);
      setState(() => _error = 'JSON 格式正确');
    } catch (e) {
      setState(() => _error = 'JSON 格式错误: $e');
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      setState(() => _error = '剪贴板没有可用文本');
      return;
    }
    _controller.text = text;
    _format();
  }

  void _reset() {
    _controller.text = _prettyJson(widget.source);
    setState(() => _error = null);
  }

  void _validateOnly() {
    try {
      final decoded = _decodeSingleSourceJson(_controller.text);
      final next = _bookSourceFromDecodedJson(decoded);
      final error = _validateSource(next);
      if (error != null) {
        setState(() => _error = error);
        return;
      }
      setState(() => _error = 'JSON 可保存');
    } catch (e) {
      setState(() => _error = 'JSON 格式错误: $e');
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final decoded = _decodeSingleSourceJson(_controller.text);
      final updated = _bookSourceFromDecodedJson(decoded)
        ..id = widget.source.id;
      final error = _validateSource(updated);
      if (error != null) throw FormatException(error);
      await ref.read(bookSourceViewModelProvider.notifier).saveSource(updated);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '保存失败: $e';
      });
    }
  }

  String _prettyJson(BookSource source) {
    return const JsonEncoder.withIndent('  ').convert(source.toJson());
  }

  Map<String, dynamic> _decodeSingleSourceJson(String text) {
    final decoded = jsonDecode(text);
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    if (decoded is List && decoded.length == 1 && decoded.first is Map) {
      return (decoded.first as Map).map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    if (decoded is List) {
      throw const FormatException('这里只编辑单个书源；批量 JSON 请回到书源管理导入');
    }
    throw const FormatException('根节点必须是书源 JSON 对象');
  }

  BookSource _bookSourceFromDecodedJson(Map<String, dynamic> decoded) {
    return BookSource.fromJson(decoded);
  }

  String? _validateSource(BookSource source) {
    if (source.bookSourceName.trim().isEmpty) {
      return 'bookSourceName 不能为空';
    }
    if (source.bookSourceUrl.trim().isEmpty) {
      return 'bookSourceUrl 不能为空';
    }
    if (source.bookSourceType == 0 &&
        (source.searchUrl?.trim().isEmpty ?? true)) {
      return '小说源 searchUrl 不能为空';
    }
    if (source.bookSourceType == 0 &&
        (source.ruleSearch?.trim().isEmpty ?? true)) {
      return '小说源 ruleSearch 不能为空';
    }
    return null;
  }
}
