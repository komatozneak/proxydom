import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/busy/busy_overlay.dart';
import '../../../core/busy/busy_overlay_host.dart';
import '../../../core/diagnostics/ui_log.dart';
import '../../../core/ios_store_gates.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/interaction.dart';
import '../../../core/widgets/mossy_rail.dart';
import '../../../core/widgets/proxydom_ground.dart';
import '../../../core/widgets/proxydom_mark.dart';
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
  /// How lit the yard is. The home screen writes to it through
  /// [GroundGlowScope]; this class owns the painter.
  final GroundGlow _glow = GroundGlow();

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
    final dark = theme.brightness == Brightness.dark;

    // The night is behind everything, and the rail sits on it like furniture
    // in a room. Both platforms share it — the house is the only light source
    // in the app, and it should light the window the same way.
    Widget page = widget.navigationShell;

    if (windowsDesktop) {
      page = Row(
        children: [
          WindowsNavRail(selected: selected, onSelect: _onTap),
          Expanded(child: page),
        ],
      );
      return _yard(
        context,
        child: Scaffold(backgroundColor: Colors.transparent, body: page),
      );
    }

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
    return _yard(
      context,
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: Colors.transparent,
            body: _StatusBarStyle(dark: dark, child: page),
            bottomNavigationBar: MossySlab(
              light: !dark,
              child: bar,
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
      ),
    );
  }

  /// Puts the night behind a screen and publishes the glow to whatever is on
  /// top, so the home can wake the yard from inside a nested navigator.
  ///
  /// A window has a pointer, so the yard answers it: the background layers
  /// shift at different rates with the cursor. A phone has no pointer, and
  /// there the painter drifts on its own clock instead.
  Widget _yard(BuildContext context, {required Widget child}) {
    final body = GroundGlowScope(
      notifier: _glow,
      child: ListenableBuilder(
        listenable: _glow,
        builder: (context, _) => ProxydomGround(state: _glow, child: child),
      ),
    );
    if (!windowsDesktop) return body;
    return MouseRegion(
      onHover: (event) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        _glow
          ..pointerDriven = true
          ..pointer = Offset(
            ((event.localPosition.dx / box.size.width) - 0.5).clamp(-1.0, 1.0),
            ((event.localPosition.dy / box.size.height) - 0.5).clamp(-1.0, 1.0),
          );
      },
      onExit: (_) => _glow.pointer = Offset.zero,
      child: body,
    );
  }
}

/// Desktop navigation rail.
///
/// Same three destinations as the phone dock, drawn the way a window draws
/// them: a mark, then a vertical list of items where the selected one is a lit
/// plate with an accent bar, and where the pointer gets hover and the keyboard
/// gets a focus ring.
///
/// Public so the shell and the capture harness render the same widget.
class WindowsNavRail extends StatelessWidget {
  const WindowsNavRail({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final int selected;

  final ValueChanged<int> onSelect;

  static const double width = 212;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppL10n.of(context);
    final dark = theme.brightness == Brightness.dark;
    final ink = dark ? AppBrand.inkDark : AppBrand.inkLight;
    final mute = dark ? AppBrand.inkMutedDark : AppBrand.inkMutedLight;

    final items = <({IconData icon, String label, int index})>[
      (
        icon: AppIcons.mapPin,
        label: Localizations.localeOf(context).languageCode == 'ru'
            ? 'Сервера'
            : 'Servers',
        index: MainShell.locationsIndex,
      ),
      (icon: AppIcons.house, label: l.navVpn, index: MainShell.homeIndex),
      (
        icon: AppIcons.settings,
        label: l.navSettings,
        index: MainShell.settingsIndex,
      ),
    ];

    return MossyRail(
      light: !dark,
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 22, 14, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 26),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        Localizations.localeOf(context).languageCode == 'ru'
                            ? 'Прокси Дом'
                            : 'Proxy Dom',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: ink,
                          // The wordmark carries the weight the monogram used
                          // to: the mark sits beside it now, not before it.
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                          fontSize: 17,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // The DOM mark beside the name: the mascot in monochrome
                    // with the letters cut out of it. It was a badge before the
                    // name; a mark after it reads as a signature.
                    ProxyDomMark(size: 26, ink: ink),
                  ],
                ),
              ),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _RailItem(
                    icon: item.icon,
                    label: item.label,
                    selected: item.index == selected,
                    onTap: () => onSelect(item.index),
                  ),
                ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 4),
                child: Text(
                  Localizations.localeOf(context).languageCode == 'ru'
                      ? 'Прокси Дом · утилита'
                      : 'Proxy Dom · utility',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: mute.withValues(alpha: 0.65),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({
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
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  final FocusNode _focus = FocusNode(debugLabel: 'RailItem');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final ink = dark ? AppBrand.inkDark : AppBrand.inkLight;

    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      child: HoverBuilder(
        onTap: widget.onTap,
        focusNode: _focus,
        onKeyActivate: widget.onTap,
        builder: (context, hovered) {
          final fill = widget.selected
              ? (dark
                    ? AppBrand.mossDeep.withValues(alpha: 0.92)
                    : AppBrand.mossLight.withValues(alpha: 0.12))
              : hovered
                  ? (dark
                        ? AppBrand.lightSource.withValues(alpha: 0.045)
                        : AppBrand.inkLight.withValues(alpha: 0.035))
                  : null;
          return AnimatedContainer(
            duration: AppBrand.motionReveal,
            curve: AppBrand.motionRevealCurve,
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: widget.selected
                    ? (dark
                          ? AppBrand.moss.withValues(alpha: 0.35)
                          : AppBrand.moss.withValues(alpha: 0.28))
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                // The accent bar is moss: the selection belongs to the stone the
                // rail is made of, not to the house on the other side of it.
                AnimatedContainer(
                  duration: AppBrand.motionReveal,
                  curve: AppBrand.motionRevealCurve,
                  width: 3,
                  height: 20,
                  margin: const EdgeInsets.only(right: 11),
                  decoration: BoxDecoration(
                    color: widget.selected
                        ? (dark ? AppBrand.mossLight : AppBrand.moss)
                        : AppBrand.shadeSource.withValues(alpha: 0.0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                AppIcon(
                  widget.icon,
                  size: 19,
                  color: widget.selected
                      ? (dark ? AppBrand.mossLight : AppBrand.moss)
                      : ink.withValues(alpha: 0.78),
                ),
                const SizedBox(width: 11),
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: ink,
                      fontSize: 14.5,
                      fontWeight:
                          widget.selected ? FontWeight.w700 : FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Status-bar band. The night runs under it on the phone, so the only job
/// left is telling the system which way the icons should be drawn.
class _StatusBarStyle extends StatelessWidget {
  const _StatusBarStyle({required this.dark, required this.child});

  final bool dark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      ),
      child: child,
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
    // The active place wears moss, like the rail's selected item: the
    // selection belongs to the slab, not to the house above it.
    final tint = selected
        ? (dark ? AppBrand.mossLight : AppBrand.moss)
        : ink.withValues(alpha: 0.72);

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
              color: selected
                  ? (dark
                        ? AppBrand.mossDeep.withValues(alpha: 0.92)
                        : AppBrand.mossLight.withValues(alpha: 0.12))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppBrand.radiusNavPill),
              border: Border.all(
                color: selected
                    ? AppBrand.moss.withValues(alpha: 0.4)
                    : Colors.transparent,
                width: 1,
              ),
            ),
            child: AppIcon(icon, size: _sideIconSize, color: tint),
          ),
          const SizedBox(height: _sideGap),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: tint,
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
