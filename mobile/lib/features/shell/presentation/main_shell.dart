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
import '../../../core/widgets/proxydom_brand.dart';
import '../../../core/widgets/proxydom_ground.dart';
import '../../../core/widgets/windows_pane.dart';
import '../../../l10n/app_localizations.dart';
import '../../home/application/vpn_provider.dart';

/// Bumped when user opens the Locations tab — triggers a reload.
final modesTabTickProvider = StateProvider<int>((ref) => 0);

/// NotebookPaper grid cell. Drop the top rule and tabs by one cell.
const double _notebookCell = 28;

/// Previous bar was 76; one cell lower so the rule sits on the next grid line.
const double _navBarHeight = 76 - _notebookCell;

/// Side tabs (Сервера / Настройки). The old 0.68 scale made a 13 sp label
/// 8.8 sp; 12 sp is the floor, so the scale is gone.
const double _sideIconSize = 24;
const double _sidePadH = 10;
const double _sidePadV = 4;
const double _sideGap = 2;
const double _sideLabelSize = 12;

/// Top rule thickness on the nav sheet.

/// Center tab: a 44 dp contour house with a 12 sp caption inside a 62 dp box.
/// The mascot lives on Home, as the connect button; the dock is navigation.
const double _domButtonSize = 62;
const double _domCircleSize = 44;
const double _domRingWidth = 1.6;

/// How far the DOM circle rises above the nav band. The top rule moves up with it.
const double _domAboveBar = (_domButtonSize - _navBarHeight) / 2;

/// Centered on the band, the circle hangs this far under it.
/// A phone absorbs that in the home-indicator inset. Windows has no inset,
/// so the same hang leaves the window.
double _domButtonBottom(double inset) {
  if (windowsDesktop) return inset;
  return inset - _domAboveBar;
}

/// Below this the window is not small, it is minimized.
///
/// Windows hands a minimized window a 160x28 client rect (SM_CXMINIMIZED by
/// SM_CYMINIMIZED) and keeps layout running at that size, even though not one
/// pixel of it can be seen. The frame is fixed at 826x591, so no window that is
/// actually on screen can come anywhere near this number.
const double _minRealShell = 480;

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
      // The caption now lives above the router (see _WindowsWindowFrame), so
      // every route gets the same window buttons and drag band.
      final rail = WindowsNavRail(selected: selected, onSelect: _onTap);
      final shell = widget.navigationShell;
      page = Row(children: [rail, Expanded(child: shell)]);
      return _yard(
        context,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Nothing to draw on a minimized window, and laying the shell out
            // at 160x28 is not harmless: the caption alone is taller than 28,
            // so every minimize reported a RenderFlex overflow of 12 pixels on
            // the bottom, and any wide row could overflow to the right on the
            // same pass. Skip the layout rather than paper over each overflow.
            if (constraints.maxWidth < _minRealShell ||
                constraints.maxHeight < _minRealShell) {
              return const SizedBox.shrink();
            }
            return Scaffold(backgroundColor: Colors.transparent, body: page);
          },
        ),
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
              // Navigation is chrome: at 2× the 12 sp labels overlapped the
              // system bar. 1.3× keeps them legible without clipping.
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
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
                semanticLabel: l.navHome,
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

/// Desktop navigation pane.
///
/// Drawn the way Windows draws one: a flat pane with a hairline edge, a button
/// that folds it down to icons and back, the brand at the top, and items where
/// the selected one is a lit plate with an accent pill. Folded, the lockup
/// gives way to the app icon and every item keeps its name as a tooltip.
///
/// The pane is its own repaint boundary: the yard behind it animates forever,
/// and the pane must not be repainted with it.
///
/// Public so the shell and the capture harness render the same widget.
class WindowsNavRail extends StatefulWidget {
  const WindowsNavRail({
    super.key,
    required this.selected,
    required this.onSelect,
    this.initiallyExpanded = true,
  });

  final int selected;

  final ValueChanged<int> onSelect;

  final bool initiallyExpanded;

  static const double width = WindowsPane.width;
  static const double compactWidth = WindowsPane.compactWidth;

  static const double wideFrom = WindowsPane.wideFrom;

  static const Duration fold = WindowsPane.fold;

  @override
  State<WindowsNavRail> createState() => _WindowsNavRailState();
}

class _WindowsNavRailState extends State<WindowsNavRail> {
  late bool _expanded = widget.initiallyExpanded;

  double get _target =>
      _expanded ? WindowsNavRail.width : WindowsNavRail.compactWidth;

  @override
  void initState() {
    super.initState();
    // The caption paints this pane's column over its own band; tell it how
    // wide the column is, after this frame so the caption is not rebuilt
    // while the shell is building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) WindowsPane.currentWidth.value = _target;
    });
  }

  @override
  void dispose() {
    WindowsPane.currentWidth.value = null;
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    WindowsPane.currentWidth.value = _target;
  }

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

    return RepaintBoundary(
      child: AnimatedContainer(
        duration: WindowsNavRail.fold,
        curve: WindowsPane.foldCurve,
        width: _target,
        decoration: BoxDecoration(
          color: WindowsPane.panel(dark),
          border: Border(right: WindowsPane.edge(dark)),
        ),
        child: ClipRect(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= WindowsNavRail.wideFrom;
              final pad = wide ? 14.0 : 8.0;
              return Padding(
                padding: EdgeInsets.fromLTRB(pad, 8, pad, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: wide ? Alignment.centerLeft : Alignment.center,
                      child: _PaneButton(
                        icon: AppIcons.sidebar,
                        label: _expanded ? l.navPaneCollapse : l.navPaneExpand,
                        onTap: _toggle,
                      ),
                    ),
                    // The name sits in the caption above the pane, so the
                    // destinations start right under the fold button.
                    const SizedBox(height: 10),
                    for (final item in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: _RailItem(
                          icon: item.icon,
                          label: item.label,
                          selected: item.index == widget.selected,
                          compact: !wide,
                          onTap: () => widget.onSelect(item.index),
                        ),
                      ),
                    const Spacer(),
                    if (wide)
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
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The square button that folds the pane, like the one in Windows Settings.
class _PaneButton extends StatelessWidget {
  const _PaneButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;

  /// For screen readers only: a hover hint over a button whose click says
  /// what it does got in the way.
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? AppBrand.inkDark : AppBrand.inkLight;
    return Semantics(
      button: true,
      label: label,
      child: HoverBuilder(
        onTap: onTap,
        onKeyActivate: onTap,
        builder: (context, hovered) => Container(
          width: 40,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovered
                ? (dark
                    ? AppBrand.lightSource.withValues(alpha: 0.06)
                    : AppBrand.inkLight.withValues(alpha: 0.05))
                : null,
            borderRadius: BorderRadius.circular(6),
          ),
          child: AppIcon(icon, size: 18, color: ink.withValues(alpha: 0.82)),
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
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

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
    final accent = dark ? AppBrand.mossLight : AppBrand.moss;

    final item = Semantics(
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
                  ? AppBrand.lightSource.withValues(alpha: 0.07)
                  : AppBrand.inkLight.withValues(alpha: 0.06))
              : hovered
                  ? (dark
                      ? AppBrand.lightSource.withValues(alpha: 0.04)
                      : AppBrand.inkLight.withValues(alpha: 0.03))
                  : null;
          final icon = AppIcon(
            widget.icon,
            size: 19,
            color: widget.selected ? accent : ink.withValues(alpha: 0.78),
          );
          // The accent pill sits at the item's left edge, the way a Windows
          // navigation pane marks where you are, folded or not.
          final pill = AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            width: 3,
            height: widget.selected ? 16 : 0,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          );
          return Container(
            height: 40,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Positioned(left: 0, child: pill),
                if (widget.compact)
                  Center(child: icon)
                else
                  Padding(
                    padding: const EdgeInsets.only(left: 14, right: 10),
                    child: Row(
                      children: [
                        icon,
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: ink,
                              fontSize: 14,
                              fontWeight: widget.selected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
    return widget.compact ? Tooltip(message: widget.label, child: item) : item;
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
    final l = AppL10n.of(context);
    final active = AppBrand.mascotGold;
    final idle = theme.colorScheme.onSurfaceVariant;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: SizedBox(
        width: 84,
        height: _domButtonSize,
        child: Semantics(
          button: true,
          selected: selected,
          label: semanticLabel,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Material(
                type: MaterialType.transparency,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: onTap,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: _domCircleSize,
                    height: _domCircleSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? active
                            : theme.colorScheme.outline.withValues(alpha: 0.6),
                        width: _domRingWidth,
                      ),
                    ),
                    child: AppIcon(
                      AppIcons.house,
                      size: 24,
                      color: selected ? active : idle,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 1),
              ExcludeSemantics(
                child: Text(
                  l.navHome,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 12,
                    color: selected ? theme.colorScheme.onSurface : idle,
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
