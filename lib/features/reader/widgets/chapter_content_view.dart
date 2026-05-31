import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../data/models/chapter.dart';

/// 章节内容视图
/// 显示单个章节的内容，支持自定义字体和样式
class ChapterContentView extends StatelessWidget {
  final Chapter chapter;
  final double fontSize;
  final double lineHeight;
  final double letterSpacing;
  final Color textColor;
  final Color backgroundColor;
  final String fontFamily;

  const ChapterContentView({
    super.key,
    required this.chapter,
    this.fontSize = 17.0,
    this.lineHeight = 1.8,
    this.letterSpacing = 0.3,
    this.textColor = CupertinoColors.black,
    this.backgroundColor = CupertinoColors.white,
    this.fontFamily = 'system',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 章节标题
          Padding(
            padding: const EdgeInsets.only(bottom: 24, top: 32),
            child: Text(
              chapter.title,
              style: TextStyle(
                fontSize: fontSize + 5,
                fontWeight: FontWeight.w700,
                color: textColor,
                height: 1.3,
                fontFamily: fontFamily == 'system' ? null : fontFamily,
              ),
            ),
          ),
          // 章节正文
          SelectableText(
            chapter.content ?? '内容加载中...',
            style: TextStyle(
              fontSize: fontSize,
              color: textColor.withOpacity(0.87),
              height: lineHeight,
              letterSpacing: letterSpacing,
              fontFamily: fontFamily == 'system' ? null : fontFamily,
            ),
          ),
          // 章节末尾间距
          const SizedBox(height: 60),
          // 分隔线
          Center(
            child: Container(
              width: 60,
              height: 1,
              color: textColor.withOpacity(0.1),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
