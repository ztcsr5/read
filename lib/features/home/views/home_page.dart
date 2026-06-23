import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/colors.dart';
import '../../../widgets/ios_glass.dart';

class HomePage extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const HomePage({super.key, required this.navigationShell});

  void _onItemTapped(int index) {
    HapticFeedback.lightImpact();
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(child: navigationShell),
          Positioned(
            left: 12,
            right: 12,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IOSGlassPanel(
                    borderRadius: BorderRadius.circular(28),
                    blur: 28,
                    opacity: 0.78,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 26,
                      vertical: 9,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: CupertinoColors.black.withOpacity(0.10),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _GlassTabButton(
                          selected: navigationShell.currentIndex == 0,
                          icon: CupertinoIcons.house,
                          activeIcon: CupertinoIcons.house_fill,
                          label: '主页',
                          onTap: () => _onItemTapped(0),
                        ),
                        _GlassTabButton(
                          selected: navigationShell.currentIndex == 1,
                          icon: CupertinoIcons.square_grid_2x2,
                          activeIcon: CupertinoIcons.square_grid_2x2_fill,
                          label: '发现',
                          onTap: () => _onItemTapped(1),
                        ),
                        _GlassTabButton(
                          selected: navigationShell.currentIndex == 2,
                          icon: CupertinoIcons.settings,
                          activeIcon: CupertinoIcons.settings_solid,
                          label: '设置',
                          onTap: () => _onItemTapped(2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassTabButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final VoidCallback onTap;

  const _GlassTabButton({
    required this.selected,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final inactive = CupertinoTheme.of(context).brightness == Brightness.dark
        ? CupertinoColors.systemGrey2
        : CupertinoColors.systemGrey;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minSize: 0,
      onPressed: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: 64,
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? activeIcon : icon,
              size: 22,
              color: selected ? AppColors.primaryPurple : inactive,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.primaryPurple : inactive,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
