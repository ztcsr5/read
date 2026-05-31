import 'package:flutter/cupertino.dart';

import '../app/theme/colors.dart';
import '../app/theme/dimensions.dart';

/// A shimmer / skeleton loading effect for placeholder content.
///
/// Provides a gentle animated gradient that sweeps across the child, giving
/// the user visual feedback while content loads (Apple HIG progressive loading).
class ShimmerLoading extends StatefulWidget {
  const ShimmerLoading({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
    this.duration = const Duration(milliseconds: 1500),
    this.enabled = true,
  });

  /// The child widget to overlay the shimmer effect on.
  final Widget child;

  /// Base color of the shimmer (defaults to system gray 5/6).
  final Color? baseColor;

  /// Highlight color of the shimmer sweep.
  final Color? highlightColor;

  /// Duration of one shimmer sweep cycle.
  final Duration duration;

  /// Whether the shimmer animation is active.
  final bool enabled;

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    if (widget.enabled) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant ShimmerLoading oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.enabled && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final brightness = CupertinoTheme.brightnessOf(context);
    final base = widget.baseColor ??
        (brightness == Brightness.dark
            ? AppColors.systemGray5Dark
            : AppColors.systemGray5);
    final highlight = widget.highlightColor ??
        (brightness == Brightness.dark
            ? AppColors.systemGray4Dark
            : AppColors.systemGray6);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [base, highlight, base],
              stops: const [0.0, 0.5, 1.0],
              begin: const Alignment(-1.0, -0.3),
              end: const Alignment(1.0, 0.3),
              transform: _SlidingGradientTransform(
                slidePercent: _controller.value,
              ),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Slides the gradient along the horizontal axis for the shimmer effect.
class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform({required this.slidePercent});
  final double slidePercent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(
      bounds.width * (slidePercent * 2 - 1),
      0,
      0,
    );
  }
}

/// A pre-built shimmer placeholder shaped like a book card.
class ShimmerBookCard extends StatelessWidget {
  const ShimmerBookCard({
    super.key,
    this.width = AppDimensions.bookCoverGridWidth,
  });

  final double width;

  @override
  Widget build(BuildContext context) {
    final brightness = CupertinoTheme.brightnessOf(context);
    final placeholderColor = brightness == Brightness.dark
        ? AppColors.systemGray5Dark
        : AppColors.systemGray5;

    final coverHeight = width / AppDimensions.bookCoverAspectRatio;

    return ShimmerLoading(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover placeholder
          Container(
            width: width,
            height: coverHeight,
            decoration: BoxDecoration(
              color: placeholderColor,
              borderRadius: BorderRadius.circular(AppDimensions.radiusM),
            ),
          ),
          const SizedBox(height: AppDimensions.paddingS),
          // Title placeholder
          Container(
            width: width * 0.8,
            height: 14,
            decoration: BoxDecoration(
              color: placeholderColor,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: AppDimensions.paddingXS),
          // Author placeholder
          Container(
            width: width * 0.5,
            height: 12,
            decoration: BoxDecoration(
              color: placeholderColor,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
    );
  }
}

/// A pre-built shimmer placeholder shaped like a list row.
class ShimmerListRow extends StatelessWidget {
  const ShimmerListRow({super.key});

  @override
  Widget build(BuildContext context) {
    final brightness = CupertinoTheme.brightnessOf(context);
    final placeholderColor = brightness == Brightness.dark
        ? AppColors.systemGray5Dark
        : AppColors.systemGray5;

    return ShimmerLoading(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.contentMargin,
          vertical: AppDimensions.paddingM,
        ),
        child: Row(
          children: [
            // Thumbnail
            Container(
              width: AppDimensions.bookCoverListWidth,
              height: AppDimensions.bookCoverListWidth / AppDimensions.bookCoverAspectRatio,
              decoration: BoxDecoration(
                color: placeholderColor,
                borderRadius: BorderRadius.circular(AppDimensions.radiusS),
              ),
            ),
            const SizedBox(width: AppDimensions.paddingM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 16,
                    decoration: BoxDecoration(
                      color: placeholderColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: AppDimensions.paddingS),
                  Container(
                    width: 120,
                    height: 13,
                    decoration: BoxDecoration(
                      color: placeholderColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
