import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme.dart';
import '../../../../core/utils/format_utils.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/home_stats_provider.dart';
import '../../application/vpn_provider.dart';
import '../../application/vpn_status.dart';

enum MetricsDisplayState { hidden, shimmer, live }

/// Compact ↓ / ↑ / ping row — ping from libbox urlTest (no Dart Socket probe).
class CompactMetricsRow extends ConsumerWidget {
  const CompactMetricsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(vpnProvider);
    final trafficAsync = ref.watch(trafficStatsProvider);
    final pingAsync = ref.watch(homePingMsProvider);
    final isRu = Localizations.localeOf(context).languageCode == 'ru';

    final MetricsDisplayState display;
    if (status is! VpnConnected) {
      display = MetricsDisplayState.hidden;
    } else {
      final hasTraffic = trafficAsync.hasValue;
      final hasPing = pingAsync.asData?.value != null;
      display = (hasTraffic || hasPing)
          ? MetricsDisplayState.live
          : MetricsDisplayState.shimmer;
    }

    final pingLabel = formatPingMs(pingAsync.asData?.value, russian: isRu);
    final down = trafficAsync.asData?.value;
    final up = trafficAsync.asData?.value;

    return Semantics(
      label: 'connection stats',
      readOnly: true,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: AnimatedOpacity(
              opacity: display == MetricsDisplayState.hidden ? 0 : 1,
              duration: const Duration(milliseconds: 300),
              child: SizedBox(
                height: display == MetricsDisplayState.hidden ? 0 : 48,
                child: switch (display) {
                  MetricsDisplayState.hidden => const SizedBox.shrink(),
                  MetricsDisplayState.shimmer => const _ShimmerDots(),
                  MetricsDisplayState.live => _LiveMetrics(
                      ping: pingLabel,
                      download: down != null
                          ? formatBytesPerSec(down.downlinkBps, russian: isRu)
                          : null,
                      upload: up != null
                          ? formatBytesPerSec(up.uplinkBps, russian: isRu)
                          : null,
                    ),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveMetrics extends StatelessWidget {
  const _LiveMetrics({
    required this.ping,
    required this.download,
    required this.upload,
  });

  final String? ping;
  final String? download;
  final String? upload;

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: AppBrand.secondary,
    );
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    Widget cell(IconData icon, String? value, String label) {
      if (value == null) return const SizedBox.shrink();
      return Expanded(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(icon, size: 16, color: AppBrand.info),
            const SizedBox(width: 6),
            Flexible(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style,
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        if (ping != null) cell(AppIcons.gauge, ping, l.homeStatPing),
        if (download != null)
          cell(AppIcons.download, download, l.homeStatDownload),
        if (upload != null) cell(AppIcons.upload, upload, l.homeStatUpload),
      ],
    );
  }
}

class _ShimmerDots extends StatefulWidget {
  const _ShimmerDots();

  @override
  State<_ShimmerDots> createState() => _ShimmerDotsState();
}

class _ShimmerDotsState extends State<_ShimmerDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.3, end: 0.7).animate(_ctrl),
        child: Text(
          '• • •',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
            letterSpacing: 4,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
