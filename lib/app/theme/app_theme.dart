import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'colors.dart';
import 'typography.dart';

enum ThemeType { system, light, dark, eyeCare }

/// 主题状态提供者
final themeProvider = StateProvider<ThemeType>((ref) => ThemeType.system);

class AppTheme {
  /// 浅色主题 - 模仿 Apple 播客
  static const CupertinoThemeData lightTheme = CupertinoThemeData(
    brightness: Brightness.light,
    primaryColor: AppColors.primaryPurple,
    primaryContrastingColor: CupertinoColors.white,
    scaffoldBackgroundColor: AppColors.systemBackground,
    barBackgroundColor: AppColors.navBarBackground,
    textTheme: CupertinoTextThemeData(
      primaryColor: CupertinoColors.black,
      textStyle: AppTypography.bodyLight,
      navLargeTitleTextStyle: AppTypography.largeTitleLight,
      navTitleTextStyle: AppTypography.headlineLight,
    ),
  );

  /// 深色主题
  static const CupertinoThemeData darkTheme = CupertinoThemeData(
    brightness: Brightness.dark,
    primaryColor: AppColors.primaryPurpleDark,
    primaryContrastingColor: CupertinoColors.black,
    scaffoldBackgroundColor: AppColors.systemBackgroundDark,
    barBackgroundColor: AppColors.navBarBackgroundDark,
    textTheme: CupertinoTextThemeData(
      primaryColor: CupertinoColors.white,
      textStyle: AppTypography.bodyDark,
      navLargeTitleTextStyle: AppTypography.largeTitleDark,
      navTitleTextStyle: AppTypography.headlineDark,
    ),
  );

  /// 护眼主题
  static const CupertinoThemeData eyeCareTheme = CupertinoThemeData(
    brightness: Brightness.light,
    primaryColor: Color(0xFFD08A44),
    primaryContrastingColor: CupertinoColors.white,
    scaffoldBackgroundColor: AppColors.eyeCareBackground,
    barBackgroundColor: AppColors.eyeCareNavBar,
    textTheme: CupertinoTextThemeData(
      primaryColor: Color(0xFF3C3C3C),
      textStyle: TextStyle(
        fontFamily: '.SF Pro Text',
        fontSize: 17.0,
        letterSpacing: -0.41,
        color: Color(0xFF3C3C3C),
      ),
      navLargeTitleTextStyle: TextStyle(
        fontFamily: '.SF Pro Display',
        fontSize: 34.0,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.37,
        color: Color(0xFF3C3C3C),
      ),
      navTitleTextStyle: TextStyle(
        fontFamily: '.SF Pro Text',
        fontSize: 17.0,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.41,
        color: Color(0xFF3C3C3C),
      ),
    ),
  );

  /// 获取当前主题数据
  static CupertinoThemeData getTheme(
    ThemeType type, {
    Brightness platformBrightness = Brightness.light,
  }) {
    switch (type) {
      case ThemeType.system:
        return platformBrightness == Brightness.dark ? darkTheme : lightTheme;
      case ThemeType.light:
        return lightTheme;
      case ThemeType.dark:
        return darkTheme;
      case ThemeType.eyeCare:
        return eyeCareTheme;
    }
  }
}
