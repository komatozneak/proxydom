import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/busy/busy_overlay.dart';
import '../../../core/ios_store_gates.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/connect_button.dart';
import '../../../core/widgets/signal_nest_hero.dart';
import '../../../core/widgets/teremok_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../../session/application/session_provider.dart';
import '../../session/data/account_session_snapshot.dart';
import '../../settings/application/subscription_status_provider.dart';
import '../../settings/data/installed_apps_channel.dart';
import '../../settings/data/split_tunnel_prefs.dart';
import '../../settings/data/subscription_status.dart';
import '../../vpn/data/hy2_import_store.dart';
import '../../vpn/data/vpn_service_config.dart';
import '../../vpn/data/node_auto_selector.dart';
import '../../vpn/data/node_display.dart';
import '../../vpn/data/vpn_controller.dart';
import '../../vpn/data/vpn_node.dart';
import '../../vpn/domain/vpn_connect_error.dart';
import '../../vpn/presentation/free_client_chrome.dart';
import '../../vpn/presentation/vpn_disclosure_dialog.dart';
import '../../vpn/presentation/vpn_platform_copy.dart';
import '../data/battery_prompt_prefs.dart';
import '../application/vpn_provider.dart';
import '../application/vpn_status.dart';
import 'widgets/free_quota_bar.dart';
import 'widgets/radial_gradient_ground.dart';
import 'widgets/server_card.dart';

/// Test keys: quota meter sits above Living House.
const kHomeQuotaBarKey = ValueKey<String>('home_quota_bar');
const kHomeSignalNestKey = ValueKey<String>('home_signal_nest');

/// Variant 4 Home: Nest CTA + NoVPN row + Server card (location | session).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  String _serverTitle = '…';
  String _serverSubtitle = '';
  String? _importedScheme;
  String _serverFlag = kFlagGlobe;
  bool _selectionIsAuto = true;
  List<String> _autoPoolFlags = const [kFlagGlobe];

  /// Sticky key for last good Server card (selected id or egress).
  String? _placeStickyKey;

  int _noVpnEnabled = 0;
  int _noVpnTotal = 0;
  bool _openingSubscription = false;

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
      unawaited(_refreshEntitlement());
    }
  }

  Future<void> _maybeAskBattery() async {
    if (!freeKeyClient) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (await BatteryPromptPrefs.isDismissed()) return;
    if (!mounted) return;
    final l = AppL10n.of(context);
    final allow = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.freeBatteryTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(l.freeBatteryBody),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l.freeBatteryAllow),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l.freeBatteryDismiss),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || allow == null) return;
    await BatteryPromptPrefs.dismiss();
    if (allow) {
      await VpnController.instance.requestBatteryExemption();
    }
  }

  Future<void> _refreshEntitlement() async {
    if (freeKeyClient) return;
    await ref.read(sessionProvider.notifier).refresh();
    await ref.read(subscriptionStatusProvider.notifier).refresh();
  }

  Future<void> _openSubscription() async {
    if (_openingSubscription || !mounted) return;
    _openingSubscription = true;
    try {
      await context.push('/import');
    } finally {
      if (mounted) _openingSubscription = false;
    }
  }

  Future<void> _onHomeReady() async {
    await _refreshNoVpnCounter();
    if (!mounted) return;
    await _refreshServerCard();
    if (!mounted) return;
    await ref.read(vpnProvider.notifier).syncFromNative();
    if (!mounted) return;
    await ref.read(vpnProvider.notifier).reconcileWithNative();
    if (!mounted) return;
    unawaited(_refreshEntitlement());
  }

  /// Android: live Apps pin + default bypass seed.
  /// iOS: one-shot enable all Sites «Основные» (NoVPN UI is hidden).
  Future<void> _refreshNoVpnCounter() async {
    if (kIsWeb) return;
    if (iosAppsSplitUnsupported) {
      await SplitTunnelPrefs.ensureIosSitesAllEnabledIfNeeded();
      return;
    }
    try {
      final apps =
          await InstalledAppsChannel.listLauncherApps(includeIcons: false);
      await SplitTunnelPrefs.seedDefaultBypassIfNeeded(
        apps.map((app) => app.packageName),
      );
      final disallowed = await SplitTunnelPrefs.loadDisallowedPackages();
      final counter = noVpnAppsCounter(
        launcherPackages: apps.map((app) => app.packageName),
        disallowedPackages: disallowed,
      );
      if (!mounted) return;
      setState(() {
        _noVpnEnabled = counter.enabled;
        _noVpnTotal = counter.total;
      });
    } catch (_) {
      // Unsupported platform / missing plugin: leave pin at last known count.
    }
  }

  Future<void>? _serverCardInFlight;

  Future<void> _refreshServerCard() {
    return _serverCardInFlight ??= _refreshServerCardBody().whenComplete(() {
      _serverCardInFlight = null;
    });
  }

  Future<void> _refreshServerCardBody() async {
    if (freeKeyClient) {
      final selected = await Hy2ImportStore.instance.selected();
      if (!mounted) return;
      final ru = Localizations.localeOf(context).languageCode == 'ru';
      setState(() {
        _selectionIsAuto = false;
        _autoPoolFlags = const [];
        _placeStickyKey = selected?.name ?? 'import:empty';
        if (selected == null) {
          _serverTitle = ru ? 'Нет ссылки' : 'No link';
          _serverSubtitle = ru ? 'Вставьте ключ' : 'Paste a key';
          _importedScheme = null;
          _serverFlag = kFlagGlobe;
        } else {
          _serverTitle = selected.name;
          _serverSubtitle = selected.endpoint;
          _importedScheme = selected.scheme;
          _serverFlag = kFlagGlobe;
        }
      });
      return;
    }
    final l = AppL10n.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    try {
      if (!mounted) return;
      final vpnStatus = ref.read(vpnProvider);
      final config = ref.read(vpnProvider.notifier).config;
      final egressHost = config?.expectedEgressHost;
      final displayLabel = ref.read(vpnProvider.notifier).displayLabel;
      final nodesRepo = ref.read(vpnNodesRepositoryProvider);
      final selectedId = await nodesRepo.getSelectedNodeId() ?? kRegionAutoId;
      final isAuto = selectedId.isEmpty || selectedId == kRegionAutoId;

      List<VpnNode> catalog = const [];
      try {
        catalog = await nodesRepo.loadCachedNodes() ?? const [];
        if (catalog.isEmpty) {
          catalog = await nodesRepo.listNodes();
        }
      } catch (_) {
        catalog = await nodesRepo.loadCachedNodes() ?? const [];
      }
      final premium =
          ref.read(subscriptionStatusProvider).asData?.value.unlocksPremium ??
              false;
      final poolFlags = uniqueAutoPoolFlags(
        autoPoolFor(catalog, isPremium: premium),
      );

      NodePlace? place;
      VpnNode? placeNode;
      String stickyKey;

      if (!isAuto) {
        for (final n in catalog) {
          if (n.id == selectedId) {
            placeNode = n;
            break;
          }
        }
        if (placeNode != null) {
          place = placeForNode(placeNode);
          stickyKey = 'selected:${placeNode.id}';
        } else {
          stickyKey = 'selected:$selectedId';
        }
      } else if (vpnStatus is VpnConnecting) {
        // Keep «Автоматически» while Auto proves; ServerCard cycles pool flags.
        stickyKey = 'auto:connecting';
        placeNode = null;
        place = NodePlace(
          title: l.regionAutoTitle,
          subtitle: l.regionAutoSubtitle,
          flag: poolFlags.isNotEmpty ? poolFlags.first : kFlagGlobe,
        );
      } else {
        final winnerId = ref.read(vpnProvider.notifier).autoWinnerId;
        stickyKey = 'auto:${winnerId ?? egressHost ?? displayLabel ?? 'none'}';
        placeNode = autoWinnerNode(catalog, winnerId);
        placeNode ??= catalogNodeForHost(catalog, egressHost);
        if (placeNode != null) {
          place = placeForNode(placeNode);
        }
      }

      if (place == null) {
        final sanitized =
            displayLabel == null ? '' : sanitizeHomeLabel(displayLabel);
        final fallbackLabel = sanitized.isNotEmpty
            ? sanitized
            : (vpnStatus is VpnConnected
                ? sanitizeHomeLabel(vpnStatus.serverName)
                : '');
        if (fallbackLabel.isNotEmpty && !_looksLikeRawHost(fallbackLabel)) {
          final productFlag = flagForProductLabel(fallbackLabel);
          place = placeFromProductLabel(
            fallbackLabel,
            flag: productFlag == kFlagGlobe && poolFlags.isNotEmpty
                ? poolFlags.first
                : productFlag,
          );
        } else if (egressHost != null && egressHost.isNotEmpty) {
          place = await resolvePlaceForHost(
            egressHost,
            index: 0,
            fallbackLabel: fallbackLabel.isNotEmpty ? fallbackLabel : null,
          );
          // Keep title free of · Premium if resolve used unsanitized meta.
          final cleaned = sanitizeHomeLabel(place.title);
          if (cleaned.isNotEmpty && cleaned != place.title) {
            place = NodePlace(
              title: cleaned,
              subtitle: place.subtitle,
              titleEn: place.titleEn,
              subtitleEn: place.subtitleEn,
              flag: place.flag,
            );
          }
        } else {
          place = NodePlace(
            title: sanitized.isNotEmpty ? sanitized : l.homeRegionAuto,
            subtitle: '',
            flag: autoSelectionDisplayFlag(
              catalog: catalog,
              winnerId:
                  isAuto ? ref.read(vpnProvider.notifier).autoWinnerId : null,
              poolFlags: poolFlags,
            ),
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
        if (isAuto && (placeNode == null || vpnStatus is VpnConnecting)) {
          _serverTitle = l.regionAutoTitle;
          _serverSubtitle = l.regionAutoSubtitle;
          _serverFlag = autoSelectionDisplayFlag(
            catalog: catalog,
            winnerId: vpnStatus is VpnConnecting
                ? null
                : ref.read(vpnProvider.notifier).autoWinnerId,
            poolFlags: poolFlags,
          );
        } else if (place != null) {
          _serverTitle = place.displayTitle(locale);
          final city = place.displaySubtitle(locale).trim();
          if (placeNode != null) {
            _serverSubtitle =
                city.isNotEmpty ? city : displaySubtitleForNode(placeNode, l);
          } else {
            _serverSubtitle = city;
          }
          _serverFlag = place.flag;
        }
        _autoPoolFlags = poolFlags;
        if (isAuto && placeNode == null) {
          _placeStickyKey = stickyKey;
        } else if (place != null &&
            (isResolvedPlace(place) ||
                place.title.isNotEmpty && place.title != '…')) {
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
        _serverFlag = kFlagGlobe;
        _placeStickyKey = null;
        _selectionIsAuto = true;
        _autoPoolFlags = const [kFlagGlobe];
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
    final status = ref.read(vpnProvider);

    // Connecting: second tap cancels the walk (issue #147). Do not reconcile
    // with native here — getStatus() idle during Binding/Proving used to
    // demote Nest to rest while the tunnel was coming up.
    if (status is VpnConnecting || notifier.isConnectInFlight) {
      await notifier.disconnect();
      return;
    }

    if (status is VpnDisconnected || status is VpnError) {
      if (freeKeyClient && _importedScheme == null) {
        context.push('/import');
        return;
      }
      final allowed = await VpnDisclosureDialog.ensureAccepted(context);
      if (!allowed || !mounted) return;
      await notifier.connect();
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
      if (prev is! VpnConnected && next is VpnConnected) {
        unawaited(_maybeAskBattery());
      }
      if (prev is VpnConnected &&
          next is VpnConnected &&
          prev.serverName == next.serverName &&
          prev.protocol == next.protocol) {
        return;
      }
      unawaited(_refreshServerCard());
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
                serverTitle: _serverTitle == '…' && _selectionIsAuto
                    ? l.regionAutoTitle
                    : _serverTitle,
                serverSubtitle: _serverSubtitle.isEmpty
                    ? (_selectionIsAuto
                        ? l.regionAutoSubtitle
                        : l.homeStatServer)
                    : _serverSubtitle,
                importedScheme: _importedScheme,
                serverFlag: _serverFlag,
                selectionIsAuto: _selectionIsAuto,
                autoPoolFlags: _autoPoolFlags,
                noVpnEnabled: _noVpnEnabled,
                noVpnTotal: _noVpnTotal,
                onNestTap: _onNestTap,
                onPlaceRefresh: _refreshServerCard,
                onOpenLocations: () => context.go('/locations'),
                onOpenSubscription: _openSubscription,
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
    this.importedScheme,
    required this.serverFlag,
    required this.selectionIsAuto,
    required this.autoPoolFlags,
    required this.noVpnEnabled,
    required this.noVpnTotal,
    required this.onNestTap,
    required this.onPlaceRefresh,
    required this.onOpenLocations,
    required this.onOpenSubscription,
    required this.onOpenNoVpn,
  });

  final VpnStatus status;
  final double maxHeight;
  final String serverTitle;
  final String serverSubtitle;
  final String? importedScheme;
  final String serverFlag;
  final bool selectionIsAuto;
  final List<String> autoPoolFlags;
  final int noVpnEnabled;
  final int noVpnTotal;
  final Future<void> Function() onNestTap;
  final Future<void> Function() onPlaceRefresh;
  final VoidCallback onOpenLocations;
  final VoidCallback onOpenSubscription;
  final VoidCallback onOpenNoVpn;

  @override
  ConsumerState<_DashboardBody> createState() => _DashboardBodyState();
}

class _DashboardBodyState extends ConsumerState<_DashboardBody> {
  String? _warmingHost;

  /// Last Free meter so a background refresh does not unmount the bar.
  SubscriptionStatus? _stickyMeteredQuota;

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

  String get _displayFlag {
    if (widget.selectionIsAuto) {
      final flag = widget.serverFlag.trim();
      if (flag.isEmpty || flag == kFlagGlobe || flag == '🌍') {
        return widget.autoPoolFlags.isNotEmpty
            ? widget.autoPoolFlags.first
            : kFlagGlobe;
      }
    }
    return widget.serverFlag;
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
      unawaited(widget.onPlaceRefresh());
      // Session end → traffic just got scraped server-side; refresh the meter.
      if (oldWidget.status is VpnConnected &&
          widget.status is VpnDisconnected) {
        unawaited(ref.read(subscriptionStatusProvider.notifier).refresh());
      }
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
            ? homeVpnConflictHintNamedForPlatform(l, message)
            : homeVpnConflictHintForPlatform(l),
      VpnError(:final code) when code == 'permission_denied' =>
        homeVpnPermissionHintForPlatform(l),
      VpnError(:final code) when code == 'device_limit_reached' =>
        l.settingsDevicesHint,
      VpnError(:final code) when code == 'quota_exceeded' =>
        l.iosBillingUnavailableBody,
      VpnError(:final code) when code == kVpnPathIncompatibleErrorCode =>
        l.homePathIncompatibleHint,
      VpnError() => l.homeErrorFriendly,
    };
    final showVpnSettingsCta =
        status is VpnError && status.code == kVpnConflictErrorCode;
    final showDevicesCta = !hideInAppPlategaCheckout &&
        status is VpnError &&
        status.code == 'device_limit_reached';
    final showQuotaCta = status is VpnError && status.code == 'quota_exceeded';
    final liveQuota = ref.watch(subscriptionStatusProvider).asData?.value;
    if (liveQuota != null) {
      _stickyMeteredQuota = liveQuota.showsMeteredQuotaBar ? liveQuota : null;
    }
    final quota = liveQuota != null && liveQuota.showsMeteredQuotaBar
        ? liveQuota
        : _stickyMeteredQuota;
    final russian = Localizations.localeOf(context).languageCode == 'ru';
    const gib = 1024.0 * 1024.0 * 1024.0;

    final nestSize = freeKeyClient
        ? math.min(
            320.0,
            math.min(
              size.width * 0.84,
              math.max(200.0, widget.maxHeight - 340),
            ),
          )
        : math.min(
            320.0,
            math.min(size.width * 0.78, widget.maxHeight * 0.46),
          );

    if (freeKeyClient) {
      return _FreeClientHome(
        nestSize: nestSize,
        treeState: treeState,
        status: status,
        serverTitle: widget.serverTitle,
        importedScheme: widget.importedScheme,
        onNestTap: widget.onNestTap,
        showVpnSettingsCta: showVpnSettingsCta,
      );
    }

    return Column(
      children: [
        if (quota != null && quota.showsMeteredQuotaBar) ...[
          FreeQuotaBar(
            key: kHomeQuotaBarKey,
            remainingFraction: quota.quotaRemainingFraction,
            title: l.homeTrafficRemainder,
            amountLabel: l.homeTrafficAmount(
              formatGib(
                (quota.quotaBytesRemaining ?? 0) / gib,
                russian: russian,
              ),
              formatGib(
                (quota.quotaBytesLimit ?? 0) / gib,
                russian: russian,
              ),
            ),
            exhaustedLabel: l.homeTrafficExhausted,
            teaser: null,
            ctaLabel: null,
            onTap: widget.onOpenSubscription,
          ),
          const SizedBox(height: 8),
        ],
        if (_showTelegramRestoreBanner(
          quota: liveQuota,
          session: ref.watch(sessionProvider).valueOrNull,
        )) ...[
          _TelegramRestoreBanner(
            vpnConnected: status is VpnConnected,
            onTap: () {
              if (status is VpnConnected) {
                context.push('/restore');
              }
            },
          ),
          const SizedBox(height: 8),
        ],
        Expanded(
          child: Center(
            child: RadialGradientGround(
              state: treeState,
              child: SignalNestHero(
                key: kHomeSignalNestKey,
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
                showTeremokSnackBar(
                  context,
                  settingsKillSwitchOpenFailedForPlatform(l),
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
            onPressed: () => context.push('/import'),
            child: Text(
              Localizations.localeOf(context).languageCode == 'ru'
                  ? 'Вставить ссылку'
                  : 'Paste link',
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (hideInAppPlategaCheckout) ...[
          FilledButton.tonal(
            onPressed: () => context.push('/import'),
            child: Text(
              Localizations.localeOf(context).languageCode == 'ru'
                  ? 'Вставить ссылку'
                  : 'Paste link',
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (!hideInAppPlategaCheckout) ...[
          _NoVpnHomeRow(
            label: l.homeNoVpnRow,
            enabled: widget.noVpnEnabled,
            total: widget.noVpnTotal,
            onTap: widget.onOpenNoVpn,
          ),
          const SizedBox(height: 8),
        ],
        ServerCard(
          title: widget.serverTitle,
          subtitle: widget.serverSubtitle,
          flagEmoji: _displayFlag,
          selectionIsAuto: widget.selectionIsAuto,
          autoPoolFlags: widget.autoPoolFlags,
          onTap: widget.onOpenLocations,
        ),
      ],
    );
  }
}

class _FreeClientHome extends StatelessWidget {
  const _FreeClientHome({
    required this.nestSize,
    required this.treeState,
    required this.status,
    required this.serverTitle,
    this.importedScheme,
    required this.onNestTap,
    required this.showVpnSettingsCta,
  });

  final double nestSize;
  final TreeState treeState;
  final VpnStatus status;
  final String serverTitle;
  final String? importedScheme;
  final Future<void> Function() onNestTap;
  final bool showVpnSettingsCta;

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final empty = serverTitle == '…' ||
        serverTitle == 'Нет ссылки' ||
        serverTitle == 'No link';
    final current = status;
    final String protocol;
    final String? uptime;
    if (current is VpnConnected) {
      protocol = current.protocol;
      uptime = _formatUptime(current.connectedSince);
    } else {
      final scheme = importedScheme;
      protocol = scheme == null || scheme.isEmpty
          ? '—'
          : friendlyProtocolLabel(scheme);
      uptime = null;
    }
    final profile = empty ? l.freeNoProfile : serverTitle;
    final statusText = status is VpnConnecting
        ? l.homeConnecting
        : empty
            ? l.homeDisconnected
            : status is VpnError
                ? l.homeError
                : status is VpnConnected
                    ? l.homeConnected
                    : l.homeDisconnected;

    return Column(
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: nestSize,
                height: nestSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: nestSize,
                      height: nestSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppBrand.livingHouse.withValues(alpha: 0.10),
                      ),
                    ),
                    SignalNestHero(
                      key: kHomeSignalNestKey,
                      state: treeState,
                      onTap: () => onNestTap(),
                      size: nestSize,
                    ),
                  ],
                ),
              ),
              ConnectionStatusPanel(
                status: statusText,
                profile: profile,
                protocol: protocol,
                uptime: uptime,
              ),
              if (empty && status is! VpnConnected && status is! VpnConnecting) ...[
                const SizedBox(height: 16),
                const FreeClientEmptyState(compact: true),
              ],
              if (showVpnSettingsCta) ...[
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () async {
                    final opened =
                        await VpnController.instance.openVpnSettings();
                    if (!context.mounted) return;
                    if (!opened) {
                      showTeremokSnackBar(
                        context,
                        settingsKillSwitchOpenFailedForPlatform(l),
                      );
                    }
                  },
                  child: Text(l.settingsKillSwitchOpenVpn),
                ),
              ],
            ],
          ),
        ),
        FreeClientActionBar(
          primaryAdd: empty,
          onAdd: () => context.push('/import'),
          onPaste: () => context.push('/import?clipboard=1'),
          onScan: () => context.push('/scan'),
        ),
      ],
    );
  }

  String _formatUptime(DateTime since) {
    final d = DateTime.now().difference(since);
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

bool _showTelegramRestoreBanner({
  required SubscriptionStatus? quota,
  required AccountSessionSnapshot? session,
}) {
  // Bound contact is not "restore". Username-only missed contact_linked.
  if (session == null) return false;
  if (session.contactLinked || session.telegramUsername != null) return false;
  if (quota != null && quota.unlocksPremium) return false;
  if (session.hasAccess) return false;
  return true;
}

class _TelegramRestoreBanner extends StatelessWidget {
  const _TelegramRestoreBanner({
    required this.vpnConnected,
    required this.onTap,
  });

  final bool vpnConnected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBrand.radiusCard),
        side: BorderSide(color: theme.colorScheme.outline),
      ),
      child: InkWell(
        onTap: vpnConnected ? onTap : null,
        borderRadius: BorderRadius.circular(AppBrand.radiusCard),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const AppIcon(AppIcons.siteTelegram, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  vpnConnected
                      ? l.homeTelegramRestoreCta
                      : l.homeTelegramRestoreConnectFirst,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
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
    final showAppsPin = !iosAppsSplitUnsupported;

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
                if (showAppsPin) ...[
                  Text(
                    '$enabled / $total',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: AppBrand.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
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
