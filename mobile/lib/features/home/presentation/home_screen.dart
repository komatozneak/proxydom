import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../../core/widgets/connect_button.dart';
import '../../../core/widgets/signal_nest_hero.dart';
import '../../../l10n/app_localizations.dart';
import '../../vpn/data/node_display.dart';
import '../../vpn/data/vpn_node.dart';
import '../application/vpn_provider.dart';
import '../application/vpn_status.dart';
import 'widgets/compact_metrics_row.dart';
import 'widgets/radial_gradient_ground.dart';
import 'widgets/server_card.dart';
import 'widgets/uptime_row.dart';

/// Variant 4 Home: Nest CTA + Server card + compact metrics (hide-until-connected).
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
  bool _isAuto = true;
  /// Sticky key for last good Server card (node id or egress host).
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
    final nodesRepo = ref.read(vpnNodesRepositoryProvider);
    try {
      final selectedId = await nodesRepo.getSelectedNodeId();
      if (!mounted) return;
      final isAuto = selectedId == null || selectedId == kRegionAutoId;
      final nodes = await nodesRepo.listNodes();
      if (!mounted) return;

      VpnNode? node;
      var index = 0;
      if (isAuto) {
        node = nodes.where((n) => n.isDefault).firstOrNull ??
            nodes.where((n) => n.isConnected).firstOrNull;
      } else {
        index = nodes.indexWhere((n) => n.id == selectedId);
        if (index >= 0) {
          node = nodes[index];
        } else {
          node = nodes.where((n) => n.isDefault).firstOrNull ?? nodes.firstOrNull;
          index = 0;
        }
      }

      if (node == null) {
        setState(() {
          _serverTitle = l.homeRegionAuto;
          _serverSubtitle = l.homeStatServer;
          _serverFlag = '🌐';
          _isAuto = true;
          _placeStickyKey = null;
        });
        return;
      }

      // Prefer selected node geo; when Auto+connected, resolve actual egress.
      final vpnStatus = ref.read(vpnProvider);
      final config = ref.read(vpnProvider.notifier).config;
      final egressHost = config?.expectedEgressHost ??
          config?.singBoxConfig.primaryOutbound?.server;

      late final NodePlace place;
      late final String stickyKey;
      if (isAuto && vpnStatus is VpnConnected && egressHost != null) {
        stickyKey = 'egress:$egressHost';
        place = await resolvePlaceForHost(
          egressHost,
          index: index,
          fallbackLabel: vpnStatus.serverName,
        );
      } else {
        stickyKey = 'node:${node.id}';
        place = await resolvePlaceForNode(node, index: index);
      }
      if (!mounted) return;

      // Sticky last-good geo: connect refresh often misses GeoIP through TUN.
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
        setState(() => _isAuto = isAuto);
        return;
      }

      setState(() {
        _serverTitle = place.displayTitle(locale);
        final city = place.displaySubtitle(locale);
        _serverSubtitle = isAuto
            ? (city.isEmpty
                ? l.homeRegionAuto
                : '$city · ${l.homeRegionAuto}')
            : city;
        _serverFlag = place.flag;
        _isAuto = isAuto;
        if (isResolvedPlace(place)) {
          _placeStickyKey = stickyKey;
        }
      });
    } catch (_) {
      // Keep sticky card on transient list/geo failures (esp. mid-connect).
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
        _isAuto = true;
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
      // Cancel stuck / in-flight connect (preparing forever, permission hang).
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

    ref.listen(vpnProvider, (prev, next) {
      if (prev.runtimeType != next.runtimeType) {
        unawaited(_refreshServerCard());
      }
    });

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(l.homeTitle),
        centerTitle: true,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: _DashboardBody(
                status: vpnStatus,
                maxHeight: constraints.maxHeight,
                serverTitle: _serverTitle,
                serverSubtitle: _isAuto && _serverSubtitle.isEmpty
                    ? l.homeRegionAuto
                    : _serverSubtitle,
                serverFlag: _serverFlag,
                onNestTap: _onNestTap,
                onPlaceRefresh: _refreshServerCard,
                onServerTap: () async {
                  context.go('/locations');
                },
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
    required this.onNestTap,
    required this.onServerTap,
    required this.onPlaceRefresh,
  });

  final VpnStatus status;
  final double maxHeight;
  final String serverTitle;
  final String serverSubtitle;
  final String serverFlag;
  final Future<void> Function() onNestTap;
  final Future<void> Function() onServerTap;
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

    // Fit one viewport with bottom nav — no scroll on Home.
    final nestSize = math.min(
      260.0,
      math.min(size.width * 0.62, widget.maxHeight * 0.36),
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
          label: statusLabel.toUpperCase(),
        ),
        if (status is VpnError) ...[
          const SizedBox(height: 8),
          Text(
            l.homeErrorFriendly,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 16),
        ServerCard(
          title: widget.serverTitle,
          subtitle: widget.serverSubtitle,
          flagEmoji: widget.serverFlag,
          onTap: () => widget.onServerTap(),
        ),
        const SizedBox(height: 12),
        const CompactMetricsRow(),
        const UptimeRow(),
      ],
    );
  }
}
