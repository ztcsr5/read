import 'package:flutter/cupertino.dart';
import 'colors.dart';

class AppTypography {
  static const String _fontFamilyText = '.SF Pro Text';
  static const String _fontFamilyDisplay = '.SF Pro Display';

  // Light Theme Typography
  static const TextStyle largeTitleLight = TextStyle(
    fontFamily: _fontFamilyDisplay,
    fontSize: 34.0,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.37,
    color: AppColors.label,
  );

  static const TextStyle title1Light = TextStyle(
    fontFamily: _fontFamilyDisplay,
    fontSize: 28.0,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.36,
    color: AppColors.label,
  );

  static const TextStyle title2Light = TextStyle(
    fontFamily: _fontFamilyDisplay,
    fontSize: 22.0,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.35,
    color: AppColors.label,
  );

  static const TextStyle headlineLight = TextStyle(
    fontFamily: _fontFamilyText,
    fontSize: 17.0,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.41,
    color: AppColors.label,
  );

  static const TextStyle bodyLight = TextStyle(
    fontFamily: _fontFamilyText,
    fontSize: 17.0,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.41,
    color: AppColors.label,
  );

  static const TextStyle subheadlineLight = TextStyle(
    fontFamily: _fontFamilyText,
    fontSize: 15.0,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.24,
    color: AppColors.label,
  );

  static const TextStyle footnoteLight = TextStyle(
    fontFamily: _fontFamilyText,
    fontSize: 13.0,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.08,
    color: AppColors.secondaryLabel,
  );

  // Dark Theme Typography
  static const TextStyle largeTitleDark = TextStyle(
    fontFamily: _fontFamilyDisplay,
    fontSize: 34.0,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.37,
    color: AppColors.labelDark,
  );

  static const TextStyle title1Dark = TextStyle(
    fontFamily: _fontFamilyDisplay,
    fontSize: 28.0,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.36,
    color: AppColors.labelDark,
  );

  static const TextStyle title2Dark = TextStyle(
    fontFamily: _fontFamilyDisplay,
    fontSize: 22.0,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.35,
    color: AppColors.labelDark,
  );

  static const TextStyle headlineDark = TextStyle(
    fontFamily: _fontFamilyText,
    fontSize: 17.0,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.41,
    color: AppColors.labelDark,
  );

  static const TextStyle bodyDark = TextStyle(
    fontFamily: _fontFamilyText,
    fontSize: 17.0,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.41,
    color: AppColors.labelDark,
  );

  static const TextStyle subheadlineDark = TextStyle(
    fontFamily: _fontFamilyText,
    fontSize: 15.0,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.24,
    color: AppColors.labelDark,
  );

  static const TextStyle footnoteDark = TextStyle(
    fontFamily: _fontFamilyText,
    fontSize: 13.0,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.08,
    color: AppColors.secondaryLabelDark,
  );
}
