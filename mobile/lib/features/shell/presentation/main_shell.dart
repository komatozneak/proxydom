import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/busy/busy_overlay.dart';
import '../../../core/busy/busy_overlay_host.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/teremok_nav_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../home/application/vpn_provider.dart';

/// Bumped when user opens the Locations tab — triggers a reload.
final modesTabTickProvider = StateProvider<int>((ref) => 0);

/// Authenticated shell — branch indices MUST match [AppRouter] StatefulShellRoute:
/// 0=Locations, 1=Home(VPN), 2=Settings.
class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const int locationsIndex = 0;
  static const int homeIndex = 1;
  static const int settingsIndex = 2;

  /// Legacy alias (Modes → Locations).
  static const int modesIndex = locationsIndex;

  void _onTap(WidgetRef ref, int index) {
    if (ref.read(busyOverlayProvider).isBusy) return;
    if (index == locationsIndex) {
      ref.read(modesTabTickProvider.notifier).state++;
    }
    if (index == homeIndex) {
      unawaited(ref.read(vpnProvider.notifier).syncFromNative());
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

    return Stack(
      children: [
        Scaffold(
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
                        icon: AppIcons.mapPin,
                        label: l.navLocations,
                        selected: selected == locationsIndex,
                        onTap: () => _onTap(ref, locationsIndex),
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
        ),
        const BusyOverlayHost(),
      ],
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? AppBrand.inkWithOpacity(0.08) : null,
              borderRadius: BorderRadius.circular(AppBrand.radiusNavPill),
            ),
            child: AppIcon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontSize: 10,
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
          child: TeremokNavIcon(selected: selected, size: 52),
        ),
      ),
    );
  }
}
