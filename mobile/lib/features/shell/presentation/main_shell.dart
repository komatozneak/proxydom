import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/busy/busy_overlay.dart';
import '../../../core/diagnostics/ui_log.dart';
import '../../../core/busy/busy_overlay_host.dart';
import '../../../core/ios_store_gates.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/notebook_paper.dart';
import '../../../core/widgets/proxydom_nav_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../home/application/vpn_provider.dart';

/// Bumped when user opens the Locations tab — triggers a reload.
final modesTabTickProvider = StateProvider<int>((ref) => 0);

/// NotebookPaper grid cell. Drop the top rule and tabs by one cell.
const double _notebookCell = 28;

/// Previous bar was 76; one cell lower so the rule sits on the next grid line.
const double _navBarHeight = 76 - _notebookCell;

/// Side tabs (Сервера / Настройки): 15% smaller, then another 20%.
const double _sideScale = 0.85 * 0.8;

const double _sideIconSize = 32 * _sideScale;
const double _sidePadH = 14 * _sideScale;
const double _sidePadV = 6 * _sideScale;
const double _sideGap = 2 * _sideScale;
const double _sideLabelSize = 13 * _sideScale;

/// Top rule thickness on the nav sheet.
const double _navBarRuleWidth = 2.5;

/// DOM mark, larger than the nav band and centered on Сервера / Настройки.
const double _domButtonSize = 62;

/// Selection ring, same width as a chosen side tab. Size of the circle stays put.
const double _domRingWidth = 1.6;

/// `logo_mark_nav.png` is 1024px. Reach is the distance from the center to
/// the farthest house pixel (420.4px, 440.13px once the light stroke is on).
/// The bitmap is only a little larger than the ring: that pixel lands on the
/// inside of the selection circle, and the circle itself stays 62.
const double _navMarkPx = 1024;
const double _houseReachPx = 420.4;
const double _houseReachLightPx = 440.13;

double _domHouseExtent(bool light) {
  final reach = light ? _houseReachLightPx : _houseReachPx;
  final innerRadius = (_domButtonSize - _domRingWidth * 2) / 2;
  return innerRadius * _navMarkPx / reach;
}

/// How far the DOM circle rises above the nav band. The top rule moves up with it.
const double _domAboveBar = (_domButtonSize - _navBarHeight) / 2;

/// Centered on the band, the circle hangs this far under it.
/// A phone absorbs that in the home-indicator inset. Windows has no inset,
/// so the same hang leaves the window.
double _domButtonBottom(double inset) {
  if (windowsDesktop) return inset;
  return inset - _domAboveBar;
}

/// Authenticated shell — branch indices MUST match [AppRouter] StatefulShellRoute:
/// 0=Locations, 1=Home(VPN), 2=Settings.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const int locationsIndex = 0;
  static const int homeIndex = 1;
  static const int settingsIndex = 2;

  /// Legacy alias (Modes → Locations).
  static const int modesIndex = locationsIndex;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  void _onTap(int index) {
    const names = ['servers', 'home', 'settings'];
    final name = index >= 0 && index < names.length ? names[index] : '$index';
    if (ref.read(busyOverlayProvider).isBusy) {
      UiLog.action(
        'shell',
        'tab',
        result: 'ignored',
        reason: 'busy',
        extra: {'tab': name},
      );
      return;
    }
    UiLog.action('shell', 'tab', extra: {'tab': name});
    if (index == MainShell.locationsIndex) {
      ref.read(modesTabTickProvider.notifier).state++;
    }
    if (index == MainShell.homeIndex) {
      unawaited(ref.read(vpnProvider.notifier).syncFromNative());
    }
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final selected = widget.navigationShell.currentIndex;
    final paper = theme.brightness == Brightness.dark
        ? AppBrand.paperDark
        : AppBrand.paperLight;
    final bar = SafeArea(
      top: false,
      child: SizedBox(
        height: _navBarHeight + _domAboveBar,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: _navBarHeight,
            child: Row(
              children: [
                Expanded(
                  child: _SideNavGlyph(
                    icon: AppIcons.mapPin,
                    label: Localizations.localeOf(context).languageCode == 'ru'
                        ? 'Сервера'
                        : 'Servers',
                    selected: selected == MainShell.locationsIndex,
                    onTap: () => _onTap(MainShell.locationsIndex),
                  ),
                ),
                const Expanded(child: SizedBox.shrink()),
                Expanded(
                  child: _SideNavGlyph(
                    icon: AppIcons.settings,
                    label: l.navSettings,
                    selected: selected == MainShell.settingsIndex,
                    onTap: () => _onTap(MainShell.settingsIndex),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Stack(
      children: [
        Scaffold(
          backgroundColor: paper,
          body: _PaperStatusScrim(
            dark: theme.brightness == Brightness.dark,
            child: NotebookPaper(child: widget.navigationShell),
          ),
          bottomNavigationBar: NotebookPaper(
            emphasized: true,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: AppBrand.paperMargin.withValues(alpha: 0.72),
                    width: _navBarRuleWidth,
                  ),
                ),
              ),
              child: bar,
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          height: _domButtonSize,
          bottom: _domButtonBottom(MediaQuery.paddingOf(context).bottom),
          child: Center(
            child: _CenterNavMark(
              selected: selected == MainShell.homeIndex,
              semanticLabel: l.navVpn,
              onTap: () => _onTap(MainShell.homeIndex),
            ),
          ),
        ),
        const BusyOverlayHost(),
      ],
    );
  }
}

/// Status band. Same sheet as the bar under Сервера / Home / Настройки.
/// The margin rule sits on the bottom edge, facing the page.
class _PaperStatusScrim extends StatelessWidget {
  const _PaperStatusScrim({
    required this.dark,
    required this.child,
  });

  final bool dark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      ),
      child: Stack(
        children: [
          child,
          if (top > 0)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: top,
              child: NotebookPaper(
                emphasized: true,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: AppBrand.paperMargin.withValues(alpha: 0.72),
                        width: _navBarRuleWidth,
                      ),
                    ),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
        ],
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final ink = dark ? AppBrand.inkDark : AppBrand.inkLight;
    final chip =
        dark ? AppBrand.surfaceVariantDark : AppBrand.surfaceElevatedLight;

    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(
              horizontal: _sidePadH,
              vertical: _sidePadV,
            ),
            decoration: BoxDecoration(
              color: chip,
              borderRadius: BorderRadius.circular(AppBrand.radiusNavPill),
              border: Border.all(
                color:
                    selected ? AppBrand.paperMargin : theme.colorScheme.outline,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: AppIcon(icon, size: _sideIconSize, color: ink),
          ),
          const SizedBox(height: _sideGap),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: ink,
              fontSize: _sideLabelSize,
              height: 1,
              fontWeight: FontWeight.w700,
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
    final theme = Theme.of(context);
    final light = theme.brightness == Brightness.light;
    final house = _domHouseExtent(light);
    return SizedBox(
      width: _domButtonSize,
      height: _domButtonSize,
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        clipBehavior: Clip.none,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Semantics(
            button: true,
            selected: selected,
            label: semanticLabel,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: selected
                    ? Border.all(
                        color: AppBrand.paperMargin,
                        width: _domRingWidth,
                      )
                    : null,
              ),
              child: ClipOval(
                child: OverflowBox(
                  maxWidth: house,
                  maxHeight: house,
                  child: ProxyDomNavIcon(
                    selected: selected,
                    size: house,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
