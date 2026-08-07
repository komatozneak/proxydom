import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/teremok_nav_icon.dart';
import '../../../l10n/app_localizations.dart';

/// Bumped when user opens the Modes tab — triggers a reload.
final modesTabTickProvider = StateProvider<int>((ref) => 0);

/// Authenticated shell: Modes / Home / Settings (Home centered).
class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// Branch order: 0=Modes, 1=Home, 2=Settings.
  static const int modesIndex = 0;
  static const int homeIndex = 1;
  static const int settingsIndex = 2;

  /// Legacy alias — prefer [modesIndex].
  static const int locationsIndex = modesIndex;

  void _onTap(WidgetRef ref, int index) {
    if (index == modesIndex) {
      ref.read(modesTabTickProvider.notifier).state++;
    }
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final selected = navigationShell.currentIndex;
    final elevated = theme.colorScheme.surfaceContainerHighest;
    final line = theme.colorScheme.outline;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: elevated,
          border: Border(top: BorderSide(color: line)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 76,
            child: Row(
              children: [
                Expanded(
                  child: _SideNavGlyph(
                    icon: AppIcons.sliders,
                    label: l.navModes,
                    selected: selected == modesIndex,
                    onTap: () => _onTap(ref, modesIndex),
                  ),
                ),
                Expanded(
                  child: _CenterNavMark(
                    selected: selected == homeIndex,
                    semanticLabel: l.navVpn,
                    onTap: () => _onTap(ref, homeIndex),
                  ),
                ),
                Expanded(
                  child: _SideNavGlyph(
                    icon: AppIcons.settings,
                    label: l.navSettings,
                    selected: selected == settingsIndex,
                    onTap: () => _onTap(ref, settingsIndex),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SideNavGlyph extends StatelessWidget {
  const _SideNavGlyph({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  static const _flipMs = Duration(milliseconds: 280);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? AppBrand.inkWithOpacity(0.08) : null,
              borderRadius: BorderRadius.circular(AppBrand.radiusNavPill),
            ),
            // Vertical flip: idle upright, active upside-down (180° around X).
            child: TweenAnimationBuilder<double>(
              duration: _flipMs,
              curve: Curves.easeInOutCubic,
              tween: Tween<double>(end: selected ? 1.0 : 0.0),
              builder: (context, t, child) {
                return Transform(
                  alignment: Alignment.center,
                  filterQuality: FilterQuality.medium,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001)
                    ..rotateX(math.pi * t),
                  child: child,
                );
              },
              child: AppIcon(icon, size: 20, color: color),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterNavMark extends StatelessWidget {
  const _CenterNavMark({
    required this.selected,
    required this.semanticLabel,
    required this.onTap,
  });

  final bool selected;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Semantics(
        button: true,
        selected: selected,
        label: semanticLabel,
        child: Center(
          child: TeremokNavIcon(selected: selected, size: 56),
        ),
      ),
    );
  }
}
