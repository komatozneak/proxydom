import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/vpn_provider.dart';
import '../../application/vpn_status.dart';

/// Session clock under metrics — calm but readable when connected.
class UptimeRow extends ConsumerStatefulWidget {
  const UptimeRow({super.key});

  @override
  ConsumerState<UptimeRow> createState() => _UptimeRowState();
}

class _UptimeRowState extends ConsumerState<UptimeRow> {
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
    final status = ref.watch(vpnProvider);
    if (status is! VpnConnected) {
      return const SizedBox.shrink();
    }

    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final time = _formatUptime(_elapsed);

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.homeSessionLabel.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.4,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            time,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w500,
              letterSpacing: 1.2,
              height: 1.1,
              color: AppBrand.secondary.withValues(alpha: 0.92),
            ),
          ),
        ],
      ),
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
