import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/teremok_nav_icon.dart';
import '../../../l10n/app_localizations.dart';

/// Bumped when user opens the Locations tab — triggers a reload.
final locationsTabTickProvider = StateProvider<int>((ref) => 0);

/// Authenticated shell: Locations / Home / Settings (Home centered).
class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// Branch order: 0=Locations, 1=Home, 2=Settings.
  static const int locationsIndex = 0;
  static const int homeIndex = 1;
  static const int settingsIndex = 2;

  void _onTap(WidgetRef ref, int index) {
    if (index == locationsIndex) {
      ref.read(locationsTabTickProvider.notifier).state++;
    }
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppL10n.of(context);
    final selected = navigationShell.currentIndex;

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        // Side tabs draw their own captions; center is VPN-only (Ogon pattern).
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        height: 72,
        onDestinationSelected: (i) => _onTap(ref, i),
        destinations: [
          NavigationDestination(
            icon: _SideNavGlyph(
              icon: AppIcons.globe,
              label: l.navLocations,
              selected: selected == locationsIndex,
            ),
            selectedIcon: _SideNavGlyph(
              icon: AppIcons.globeHemisphereWest,
              label: l.navLocations,
              selected: true,
            ),
            label: l.navLocations,
          ),
          NavigationDestination(
            icon: TeremokNavIcon(selected: selected == homeIndex),
            selectedIcon: const TeremokNavIcon(selected: true),
            // TalkBack / semantics only — not painted under the glyph.
            label: l.navHome,
          ),
          NavigationDestination(
            icon: _SideNavGlyph(
              icon: AppIcons.settings,
              label: l.navSettings,
              selected: selected == settingsIndex,
            ),
            selectedIcon: _SideNavGlyph(
              icon: AppIcons.gear,
              label: l.navSettings,
              selected: true,
            ),
            label: l.navSettings,
          ),
        ],
      ),
    );
  }
}

/// Icon + caption for side tabs when [NavigationBar] hides built-in labels.
class _SideNavGlyph extends StatelessWidget {
  const _SideNavGlyph({
    required this.icon,
    required this.label,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(icon, size: 22, color: color),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
