import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/location_flag_icon.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/vpn_provider.dart';
import '../../application/vpn_status.dart';

/// Auto Connecting flag hop (Free LV→US, Premium + gaming/YouTube).
const Duration kAutoFlagCycleDuration = Duration(milliseconds: 750);

/// Server pill: region left | session column right. Tappable → Locations.
class ServerCard extends ConsumerWidget {
  const ServerCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.flagEmoji,
    this.selectionIsAuto = false,
    this.autoPoolFlags = const [],
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String flagEmoji;

  /// Auto row: Connecting cycles [autoPoolFlags] instead of a frozen first hop.
  final bool selectionIsAuto;
  final List<String> autoPoolFlags;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l = AppL10n.of(context);
    final elevated = theme.colorScheme.surfaceContainerHighest;
    final line = theme.colorScheme.outline;
    final status = ref.watch(vpnProvider);
    final connected = status is VpnConnected;
    final cycleFlags =
        selectionIsAuto && status is VpnConnecting && autoPoolFlags.length > 1;

    return Material(
      color: elevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBrand.radiusPill),
        side: BorderSide(color: line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppBrand.radiusPill),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: connected ? 72 : 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Left: flag + place
                Expanded(
                  child: Row(
                    children: [
                      if (cycleFlags)
                        _CyclingLocationFlag(flags: autoPoolFlags)
                      else
                        LocationFlagIcon(flag: flagEmoji, size: 48),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle.isEmpty ? l.homeStatServer : subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontSize: 13,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Right: session timer (connected only)
                if (connected) ...[
                  const SizedBox(width: 12),
                  const SizedBox(
                    width: 108,
                    child: _SessionColumn(),
                  ),
                ],
                if (onTap != null) ...[
                  const SizedBox(width: 4),
                  AppIcon(
                    AppIcons.chevronRight,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cycles Auto-pool flags while Connecting so Free (2) and Premium (4) move.
class _CyclingLocationFlag extends StatefulWidget {
  const _CyclingLocationFlag({required this.flags});

  final List<String> flags;

  @override
  State<_CyclingLocationFlag> createState() => _CyclingLocationFlagState();
}

class _CyclingLocationFlagState extends State<_CyclingLocationFlag> {
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _armTimer();
  }

  @override
  void didUpdateWidget(covariant _CyclingLocationFlag oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.flags, widget.flags)) {
      _index = 0;
      _armTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _armTimer() {
    _timer?.cancel();
    if (widget.flags.length < 2) return;
    _timer = Timer.periodic(kAutoFlagCycleDuration, (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % widget.flags.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final flag = widget.flags[_index % widget.flags.length];
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      child: LocationFlagIcon(
        key: ValueKey<String>(flag),
        flag: flag,
        size: 48,
      ),
    );
  }
}

/// Right column: СЕССИЯ + timer.
class _SessionColumn extends ConsumerStatefulWidget {
  const _SessionColumn();

  @override
  ConsumerState<_SessionColumn> createState() => _SessionColumnState();
}

class _SessionColumnState extends ConsumerState<_SessionColumn> {
  Timer? _timer;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _sync();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _sync());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _sync() {
    final status = ref.read(vpnProvider);
    if (status is! VpnConnected) {
      if (_elapsed != Duration.zero && mounted) {
        setState(() => _elapsed = Duration.zero);
      }
      return;
    }
    final next = DateTime.now().difference(status.connectedSince);
    if (mounted) setState(() => _elapsed = next);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final time = _formatUptime(_elapsed);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          l.homeSessionLabel.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 10,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          time,
          textAlign: TextAlign.right,
          style: theme.textTheme.titleLarge?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            height: 1.05,
            color: AppBrand.secondary.withValues(alpha: 0.92),
          ),
        ),
      ],
    );
  }

  static String _formatUptime(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:$m:$s';
    }
    return '$m:$s';
  }
}
