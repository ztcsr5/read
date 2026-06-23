import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';

class IOSGlassPanel extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final double blur;
  final double opacity;
  final Color? tint;
  final Border? border;
  final List<BoxShadow>? boxShadow;

  const IOSGlassPanel({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.padding = EdgeInsets.zero,
    this.blur = 24,
    this.opacity = 0.72,
    this.tint,
    this.border,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    final baseTint =
        tint ?? (isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF8F8F8));

    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: boxShadow,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: baseTint.withOpacity(opacity),
              borderRadius: borderRadius,
              border:
                  border ??
                  Border.all(
                    color:
                        (isDark ? CupertinoColors.white : CupertinoColors.black)
                            .withOpacity(isDark ? 0.08 : 0.06),
                    width: 0.5,
                  ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class IOSGlassBackground extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  const IOSGlassBackground({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.borderRadius = BorderRadius.zero,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [
                  Color(0xFF0E0E10),
                  Color(0xFF1B1722),
                  Color(0xFF11151C),
                ]
              : const [
                  Color(0xFFF8F4EC),
                  Color(0xFFF1E8D7),
                  Color(0xFFEDEAF2),
                ],
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
