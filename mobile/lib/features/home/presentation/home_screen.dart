import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/busy/busy_overlay.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/connect_button.dart';
import '../../../core/widgets/signal_nest_hero.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/data/installed_apps_channel.dart';
import '../../settings/data/split_tunnel_prefs.dart';
import '../../vpn/data/node_display.dart';
import '../../vpn/data/vpn_controller.dart';
import '../../vpn/data/vpn_node.dart';
import '../../vpn/domain/vpn_connect_error.dart';
import '../../vpn/presentation/vpn_disclosure_dialog.dart';
import '../application/home_stats_provider.dart';
import '../application/vpn_provider.dart';
import '../application/vpn_status.dart';
import 'widgets/radial_gradient_ground.dart';
import 'widgets/server_card.dart';

/// Variant 4 Home: Nest CTA + NoVPN row + Server card (location | session | ping).
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
  bool _selectionIsAuto = true;

  /// Sticky key for last good Server card (selected id or egress).
  String? _placeStickyKey;

  int _noVpnEnabled = 0;
  int _noVpnTotal = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_onHomeReady());
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
      unawaited(ref.read(vpnProvider.notifier).onAppResumed());
      unawaited(_refreshNoVpnCounter());
      unawaited(_refreshServerCard());
    }
  }

  Future<void> _onHomeReady() async {
    await _refreshNoVpnCounter();
    await _refreshServerCard();
    await ref.read(vpnProvider.notifier).syncFromNative();
  }

  Future<void> _refreshNoVpnCounter() async {
    final apps = await InstalledAppsChannel.listLauncherApps(includeIcons: false);
    final disallowed = await SplitTunnelPrefs.loadDisallowedPackages();
    final counter = noVpnAppsCounter(
      launcherPackages: apps.map((a) => a.packageName),
      disallowedPackages: disallowed,
    );
    if (!mounted) return;
    setState(() {
      _noVpnEnabled = counter.enabled;
      _noVpnTotal = counter.total;
    });
  }

  Future<void> _refreshServerCard() async {
    final l = AppL10n.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    try {
      if (!mounted) return;
      final vpnStatus = ref.read(vpnProvider);
      final config = ref.read(vpnProvider.notifier).config;
      final egressHost = config?.expectedEgressHost;
      final displayLabel = ref.read(vpnProvider.notifier).displayLabel;
      final nodesRepo = ref.read(vpnNodesRepositoryProvider);
      final selectedId =
          await nodesRepo.getSelectedNodeId() ?? kRegionAutoId;
      final isAuto =
          selectedId.isEmpty || selectedId == kRegionAutoId;

      NodePlace? place;
      String stickyKey;

      if (!isAuto) {
        List<VpnNode> catalog = const [];
        try {
          catalog = await nodesRepo.listNodes();
        } catch (_) {
          catalog = await nodesRepo.loadCachedNodes() ?? const [];
        }
        VpnNode? node;
        for (final n in catalog) {
          if (n.id == selectedId) {
            node = n;
            break;
          }
        }
        if (node != null) {
          place = placeForNode(node);
          stickyKey = 'selected:${node.id}';
        } else {
          stickyKey = 'selected:$selectedId';
        }
      } else {
        stickyKey = 'auto:${egressHost ?? displayLabel ?? 'none'}';
      }

      if (place == null) {
        if (displayLabel != null &&
            displayLabel.trim().isNotEmpty &&
            !_looksLikeRawHost(displayLabel)) {
          place = NodePlace(title: displayLabel.trim(), subtitle: '', flag: '🌐');
        } else if (egressHost != null && egressHost.isNotEmpty) {
          place = await resolvePlaceForHost(
            egressHost,
            index: 0,
            fallbackLabel: vpnStatus is VpnConnected
                ? vpnStatus.serverName
                : displayLabel,
          );
        } else {
          place = NodePlace(
            title: displayLabel ?? l.homeRegionAuto,
            subtitle: '',
            flag: '🌐',
          );
        }
      }

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
        _selectionIsAuto = isAuto;
        _serverTitle = place!.displayTitle(locale);
        final city = place.displaySubtitle(locale).trim();
        if (isAuto) {
          _serverSubtitle =
              city.isEmpty ? l.homeRegionAuto : '$city · ${l.homeRegionAuto}';
        } else {
          _serverSubtitle = city;
        }
        _serverFlag = place.flag;
        if (isResolvedPlace(place) ||
            place.title.isNotEmpty && place.title != '…') {
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
        _selectionIsAuto = true;
      });
    }
  }

  static bool _looksLikeRawHost(String raw) {
    final t = raw.trim().toLowerCase();
    if (t.contains('.')) return true;
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(t)) return true;
    return false;
  }

  Future<void> _onNestTap() async {
    // Region switch owns the shell busy overlay — don't fight it.
    if (ref.read(busyOverlayProvider).isBusy) return;

    final notifier = ref.read(vpnProvider.notifier);
    final before = ref.read(vpnProvider);
    await notifier.reconcileWithNative();
    if (!mounted) return;

    final status = ref.read(vpnProvider);
    // Healed stuck connecting → connected on this tap: show Connected; next tap disconnects.
    if (before is VpnConnecting && status is VpnConnected) {
      return;
    }
    // Tray key was on, Home said Disconnected: paint Connected, do not tear down.
    if ((before is VpnDisconnected || before is VpnError) &&
        status is VpnConnected) {
      return;
    }

    if (status is VpnDisconnected || status is VpnError) {
      final again = ref.read(vpnProvider);
      if (again is VpnDisconnected || again is VpnError) {
        final ok = await ensureVpnDisclosureAccepted(context);
        if (!mounted || !ok) return;
        await notifier.connect();
      }
      return;
    }

    if (status is VpnConnecting || notifier.isConnectInFlight) {
      await notifier.disconnect();
      return;
    }

    if (status is VpnConnected) {
      final again = ref.read(vpnProvider);
      if (again is VpnConnected) {
        await notifier.disconnect();
      }
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
                    ? (_selectionIsAuto ? l.homeRegionAuto : l.homeStatServer)
                    : _serverSubtitle,
                serverFlag: _serverFlag,
                pingMs: pingMs,
                noVpnEnabled: _noVpnEnabled,
                noVpnTotal: _noVpnTotal,
                onNestTap: _onNestTap,
                onPlaceRefresh: _refreshServerCard,
                onOpenLocations: () => context.go('/locations'),
                onOpenNoVpn: () async {
                  await context.push('/settings/no-vpn');
                  if (mounted) unawaited(_refreshNoVpnCounter());
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
    required this.pingMs,
    required this.noVpnEnabled,
    required this.noVpnTotal,
    required this.onNestTap,
    required this.onPlaceRefresh,
    required this.onOpenLocations,
    required this.onOpenNoVpn,
  });

  final VpnStatus status;
  final double maxHeight;
  final String serverTitle;
  final String serverSubtitle;
  final String serverFlag;
  final int? pingMs;
  final int noVpnEnabled;
  final int noVpnTotal;
  final Future<void> Function() onNestTap;
  final Future<void> Function() onPlaceRefresh;
  final VoidCallback onOpenLocations;
  final VoidCallback onOpenNoVpn;

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
    final host = vpnConfig?.expectedEgressHost;
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
      VpnError(:final code) when code == kVpnProbeFailedErrorCode =>
        l.homeVpnProbeFailedTitle,
      VpnError(:final code) when code == 'tt_provision_failed' =>
        l.homeTtProvisionFailedTitle,
      VpnError(:final code) when code == kVpnConflictErrorCode =>
        l.homeVpnConflictTitle,
      VpnError(:final code) when code == 'device_limit_reached' =>
        l.settingsSeatDeviceLimit,
      VpnError(:final code) when code == 'quota_exceeded' =>
        l.homeQuotaExceededTitle,
      VpnError() => l.homeError,
    };
    final statusHint = switch (status) {
      VpnDisconnected() => l.homeTapHint,
      VpnConnecting(:final hint) =>
        (hint != null && hint.isNotEmpty) ? hint : l.homeConnectingHint,
      VpnConnected() => l.homeConnectedHint,
      VpnError(:final code, :final message)
          when code == kVpnProbeFailedErrorCode =>
        l.homeVpnProbeFailedHint(
          message.isNotEmpty ? message : l.homeRegion,
        ),
      VpnError(:final code) when code == 'tt_provision_failed' =>
        l.homeTtProvisionFailedHint,
      VpnError(:final code, :final message)
          when code == kVpnConflictErrorCode =>
        (message.isNotEmpty && message != 'vpn_conflict')
            ? l.homeVpnConflictHintNamed(message)
            : l.homeVpnConflictHint,
      VpnError(:final code) when code == 'permission_denied' =>
        l.homeVpnPermissionHint,
      VpnError(:final code) when code == 'device_limit_reached' =>
        l.settingsDevicesHint,
      VpnError(:final code) when code == 'quota_exceeded' =>
        l.homeQuotaExceededHint,
      VpnError() => l.homeErrorFriendly,
    };
    final showVpnSettingsCta =
        status is VpnError && status.code == kVpnConflictErrorCode;
    final showDevicesCta =
        status is VpnError && status.code == 'device_limit_reached';
    final showQuotaCta =
        status is VpnError && status.code == 'quota_exceeded';

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
        if (showVpnSettingsCta) ...[
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () async {
              final opened = await VpnController.instance.openVpnSettings();
              if (!context.mounted) return;
              if (!opened) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l.settingsKillSwitchOpenFailed)),
                );
              }
            },
            child: Text(l.settingsKillSwitchOpenVpn),
          ),
        ],
        if (showDevicesCta) ...[
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () => context.push('/settings/devices'),
            child: Text(l.devicesLimitOpenManage),
          ),
        ],
        if (showQuotaCta) ...[
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () => context.push('/locked'),
            child: Text(l.homeQuotaUpgradeCta),
          ),
        ],
        const SizedBox(height: 16),
        _NoVpnHomeRow(
          label: l.homeNoVpnRow,
          enabled: widget.noVpnEnabled,
          total: widget.noVpnTotal,
          onTap: widget.onOpenNoVpn,
        ),
        const SizedBox(height: 8),
        ServerCard(
          title: widget.serverTitle,
          subtitle: widget.serverSubtitle,
          flagEmoji: widget.serverFlag,
          pingMs: widget.pingMs,
          onTap: widget.onOpenLocations,
        ),
      ],
    );
  }
}

class _NoVpnHomeRow extends StatelessWidget {
  const _NoVpnHomeRow({
    required this.label,
    required this.enabled,
    required this.total,
    required this.onTap,
  });

  final String label;
  final int enabled;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final elevated = theme.colorScheme.surfaceContainerHighest;
    final line = theme.colorScheme.outline;

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
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '$enabled / $total',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppBrand.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                AppIcon(
                  AppIcons.chevronRight,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
