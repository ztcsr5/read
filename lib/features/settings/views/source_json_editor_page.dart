import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
                  Row(
                    children: [
                      _actionButton('格式化', _format),
                      const SizedBox(width: 8),
                      _actionButton('重置', _reset),
                      const SizedBox(width: 8),
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
      minSize: 32,
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
      final decoded = jsonDecode(_controller.text);
      _controller.text = const JsonEncoder.withIndent('  ').convert(decoded);
      setState(() => _error = 'JSON 格式正确');
    } catch (e) {
      setState(() => _error = 'JSON 格式错误: $e');
    }
  }

  void _reset() {
    _controller.text = _prettyJson(widget.source);
    setState(() => _error = null);
  }

  void _validateOnly() {
    try {
      final decoded = jsonDecode(_controller.text);
      if (decoded is! Map) {
        setState(() => _error = '根节点必须是一个 JSON 对象');
        return;
      }
      final next = BookSource.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (next.bookSourceUrl.trim().isEmpty) {
        setState(() => _error = 'bookSourceUrl 不能为空');
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
      final decoded = jsonDecode(_controller.text);
      if (decoded is! Map) {
        throw const FormatException('根节点必须是一个 JSON 对象');
      }
      final updated = BookSource.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      )..id = widget.source.id;
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
}
