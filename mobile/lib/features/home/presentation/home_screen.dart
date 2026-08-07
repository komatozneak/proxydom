import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/connect_button.dart';
import '../../../core/widgets/signal_nest_hero.dart';
import '../../../l10n/app_localizations.dart';
import '../../vpn/data/node_display.dart';
import '../application/home_stats_provider.dart';
import '../application/vpn_provider.dart';
import '../application/vpn_status.dart';
import 'widgets/compact_metrics_row.dart';
import 'widgets/radial_gradient_ground.dart';
import 'widgets/server_card.dart';
import 'widgets/uptime_row.dart';

/// Variant 4 Home: Nest CTA + Server card (read-only) + compact metrics.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  String _serverTitle = '…';
  String _serverSubtitle = '';
  String _serverFlag = '🌐';

  /// Sticky key for last good Server card (egress host).
  String? _placeStickyKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshServerCard();
      ref.read(vpnProvider.notifier).syncFromNative();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(vpnProvider.notifier).syncFromNative();
    }
  }

  Future<void> _refreshServerCard() async {
    final l = AppL10n.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    try {
      if (!mounted) return;
      final vpnStatus = ref.read(vpnProvider);
      final config = ref.read(vpnProvider.notifier).config;
      final egressHost = config?.expectedEgressHost ??
          config?.singBoxConfig.primaryOutbound?.server;
      final displayLabel = ref.read(vpnProvider.notifier).displayLabel;

      if (egressHost == null || egressHost.isEmpty) {
        setState(() {
          _serverTitle = displayLabel ?? l.homeRegionAuto;
          _serverSubtitle = l.homeStatServer;
          _serverFlag = '🌐';
          _placeStickyKey = null;
        });
        return;
      }

      final stickyKey = 'egress:$egressHost';
      final place = await resolvePlaceForHost(
        egressHost,
        index: 0,
        fallbackLabel: vpnStatus is VpnConnected
            ? vpnStatus.serverName
            : (displayLabel ?? egressHost),
      );
      if (!mounted) return;

      final selectionChanged = _placeStickyKey != stickyKey;
      if (!isResolvedPlace(place) &&
          !selectionChanged &&
          isResolvedPlace(
            NodePlace(
              title: _serverTitle,
              subtitle: _serverSubtitle,
              flag: _serverFlag,
            ),
          )) {
        return;
      }

      setState(() {
        _serverTitle = place.displayTitle(locale);
        final city = place.displaySubtitle(locale);
        _serverSubtitle =
            city.isEmpty ? l.homeRegionAuto : '$city · ${l.homeRegionAuto}';
        _serverFlag = place.flag;
        if (isResolvedPlace(place)) {
          _placeStickyKey = stickyKey;
        }
      });
    } catch (_) {
      if (!mounted) return;
      if (isResolvedPlace(
        NodePlace(
          title: _serverTitle,
          subtitle: _serverSubtitle,
          flag: _serverFlag,
        ),
      )) {
        return;
      }
      setState(() {
        _serverTitle = l.homeRegion;
        _serverSubtitle = l.homeStatServer;
        _serverFlag = '🌐';
        _placeStickyKey = null;
      });
    }
  }

  Future<void> _onNestTap() async {
    final status = ref.read(vpnProvider);
    final notifier = ref.read(vpnProvider.notifier);
    if (status is VpnDisconnected || status is VpnError) {
      await notifier.connect();
      return;
    }
    if (status is VpnConnecting) {
      await notifier.disconnect();
      return;
    }
    if (status is VpnConnected) {
      await notifier.disconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final vpnStatus = ref.watch(vpnProvider);
    final pingAsync = ref.watch(homePingMsProvider);
    final pingMs =
        vpnStatus is VpnConnected ? pingAsync.asData?.value : null;

    ref.listen(vpnProvider, (prev, next) {
      if (prev.runtimeType != next.runtimeType) {
        unawaited(_refreshServerCard());
      }
    });

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: _DashboardBody(
                status: vpnStatus,
                maxHeight: constraints.maxHeight,
                serverTitle: _serverTitle,
                serverSubtitle: _serverSubtitle.isEmpty
                    ? l.homeRegionAuto
                    : _serverSubtitle,
                serverFlag: _serverFlag,
                pingMs: pingMs,
                onNestTap: _onNestTap,
                onPlaceRefresh: _refreshServerCard,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerStatefulWidget {
  const _DashboardBody({
    required this.status,
    required this.maxHeight,
    required this.serverTitle,
    required this.serverSubtitle,
    required this.serverFlag,
    required this.pingMs,
    required this.onNestTap,
    required this.onPlaceRefresh,
  });

  final VpnStatus status;
  final double maxHeight;
  final String serverTitle;
  final String serverSubtitle;
  final String serverFlag;
  final int? pingMs;
  final Future<void> Function() onNestTap;
  final Future<void> Function() onPlaceRefresh;

  @override
  ConsumerState<_DashboardBody> createState() => _DashboardBodyState();
}

class _DashboardBodyState extends ConsumerState<_DashboardBody> {
  String? _warmingHost;

  TreeState get _treeState => switch (widget.status) {
        VpnConnecting() => TreeState.connecting,
        VpnConnected() => TreeState.connected,
        VpnError() => TreeState.error,
        VpnDisconnected() => TreeState.disconnected,
      };

  Future<void> _warmGeoIfNeeded() async {
    if (widget.status is! VpnConnected) return;
    final vpnConfig = ref.read(vpnProvider.notifier).config;
    final host = vpnConfig?.expectedEgressHost ??
        vpnConfig?.singBoxConfig.primaryOutbound?.server;
    if (host == null || host == _warmingHost) return;
    _warmingHost = host;
    await warmGeoCache(host);
    if (mounted) await widget.onPlaceRefresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    unawaited(_warmGeoIfNeeded());
  }

  @override
  void didUpdateWidget(covariant _DashboardBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      _warmingHost = null;
      unawaited(_warmGeoIfNeeded());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppL10n.of(context);
    final size = MediaQuery.sizeOf(context);
    final status = widget.status;
    final treeState = _treeState;

    final statusLabel = switch (status) {
      VpnDisconnected() => l.homeDisconnected,
      VpnConnecting() => l.homeConnecting,
      VpnConnected() => l.homeConnected,
      VpnError() => l.homeError,
    };
    final statusHint = switch (status) {
      VpnDisconnected() => l.homeTapHint,
      VpnConnecting() => l.homeConnectingHint,
      VpnConnected() => l.homeConnectedHint,
      VpnError() => l.homeErrorFriendly,
    };

    final nestSize = math.min(
      320.0,
      math.min(size.width * 0.78, widget.maxHeight * 0.46),
    );

    return Column(
      children: [
        Expanded(
          child: Center(
            child: RadialGradientGround(
              state: treeState,
              child: SignalNestHero(
                state: treeState,
                onTap: () => widget.onNestTap(),
                size: nestSize,
              ),
            ),
          ),
        ),
        TreeStatusLabel(
          state: treeState,
          label: statusLabel,
        ),
        const SizedBox(height: 6),
        Text(
          statusHint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: status is VpnError
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        ServerCard(
          title: widget.serverTitle,
          subtitle: widget.serverSubtitle,
          flagEmoji: widget.serverFlag,
          pingMs: widget.pingMs,
        ),
        const SizedBox(height: 12),
        const CompactMetricsRow(),
        const UptimeRow(),
      ],
    );
  }
}
