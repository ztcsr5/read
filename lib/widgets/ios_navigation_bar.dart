import 'package:flutter/cupertino.dart';

class IosNavigationBar extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget? leading;

  const IosNavigationBar({
    super.key,
    required this.title,
    this.trailing,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoSliverNavigationBar(
      largeTitle: Text(title),
      leading: leading,
      trailing: trailing,
      border: null, // 移除底部的边框线，符合现代 iOS 风格
      backgroundColor: CupertinoTheme.of(context).barBackgroundColor.withOpacity(0.9),
    );
  }
}
