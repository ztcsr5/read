import 'package:flutter/cupertino.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('关于阅读')),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 24),
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                color: CupertinoColors.activeBlue,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                CupertinoIcons.book_fill,
                color: CupertinoColors.white,
                size: 44,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '阅读',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: isDark ? CupertinoColors.white : CupertinoColors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '版本 1.0.0',
              style: TextStyle(
                fontSize: 15,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 28),
            _section(
              context,
              '这是什么',
              '一款面向 iPhone 的本地与网络阅读器。它支持导入 TXT/ePub，管理书架、目录、书签、阅读进度，也会逐步增强对开源阅读书源和订阅源的兼容。',
            ),
            _section(
              context,
              '当前重点',
              '稳定启动、文件导入、舒适阅读、书源解析、订阅阅读和 iOS 云端打包。现在仍是半成品，但会按真实使用问题持续打磨。',
            ),
            _section(
              context,
              '数据说明',
              '书籍、书签、阅读进度和设置默认保存在设备本地。遇到数据库损坏时，应用会尝试重建本地数据库以保证可以启动。',
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ],
      ),
    );
  }
}
