import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/busy/busy_overlay.dart';
import '../../../core/diagnostics/product_log.dart';
import '../../../core/diagnostics/ui_log.dart';
import '../../../core/ios_store_gates.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/connect_button.dart';
import '../../../core/widgets/house_pulsar.dart';
import '../../../core/widgets/signal_nest_hero.dart';
import '../../../core/widgets/teremok_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/data/installed_apps_channel.dart';
import '../../settings/data/split_tunnel_prefs.dart';
import '../../vpn/application/imported_profiles_provider.dart';
import '../../vpn/data/hy2_import_store.dart';
import '../../vpn/data/subscription_label.dart';
import '../../vpn/data/subscription_traffic.dart';
import '../../vpn/data/node_auto_selector.dart';
import '../../vpn/data/node_display.dart';
import '../../vpn/data/vpn_controller.dart';
import '../../vpn/data/windows_tunnel_protocol.dart';
import '../../vpn/data/vpn_node.dart';
import '../../vpn/domain/vpn_connect_error.dart';
import '../../vpn/presentation/free_client_chrome.dart';
import '../../vpn/presentation/vpn_disclosure_dialog.dart';
import '../../vpn/presentation/vpn_platform_copy.dart';
import '../../vpn/presentation/windows_share_qr.dart';
import '../data/battery_prompt_prefs.dart';
import '../application/vpn_provider.dart';
import '../application/vpn_status.dart';

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
  String? _trafficMeta;
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

  Future<void> _refreshEntitlement() async {}

  Future<void> _openSubscription() async {
    if (_openingSubscription || !mounted) {
      UiLog.action('home', 'import', result: 'ignored', reason: 'busy');
      return;
    }
    UiLog.action('home', 'import');
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
    if (iosAppsSplitUnsupported || windowsDesktop) {
      if (iosAppsSplitUnsupported) {
        await SplitTunnelPrefs.ensureIosSitesAllEnabledIfNeeded();
      }
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
      final trafficMeta = await Hy2ImportStore.instance.selectedTrafficMeta();
      if (!mounted) return;
      final ru = Localizations.localeOf(context).languageCode == 'ru';
      setState(() {
        _selectionIsAuto = false;
        _autoPoolFlags = const [];
        _placeStickyKey = selected?.name ?? 'import:empty';
        _trafficMeta = selected == null ? null : trafficMeta;
        if (selected == null) {
          _serverTitle = ru ? 'Нет ссылки' : 'No link';
          _serverSubtitle = ru ? 'Вставьте ключ' : 'Paste a key';
          _importedScheme = null;
          _serverFlag = kFlagGlobe;
        } else {
          final label = labelForShareLink(selected);
          _serverTitle = label.title;
          _serverSubtitle =
              label.subtitle.isEmpty ? selected.endpoint : label.subtitle;
          _importedScheme = selected.scheme;
          _serverFlag = label.flag.isEmpty ? kFlagGlobe : label.flag;
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
      const premium = false;
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
    if (windowsDesktop && VpnController.instance.windowsNestLocked) {
      UiLog.action(
        'home',
        'nest',
        level: ProductLogLevel.warn,
        result: 'rejected',
        reason: 'broker_cooldown',
      );
      return;
    }
    // Region switch owns the shell busy overlay — don't fight it.
    if (ref.read(busyOverlayProvider).isBusy) {
      final connecting = ref.read(vpnProvider) is VpnConnecting ||
          ref.read(vpnProvider.notifier).isConnectInFlight;
      UiLog.action(
        'home',
        'nest',
        level: ProductLogLevel.warn,
        result: 'rejected',
        reason: connecting ? 'already_connecting' : 'busy',
      );
      return;
    }

    final notifier = ref.read(vpnProvider.notifier);
    final status = ref.read(vpnProvider);
    final ui = status.runtimeType.toString();

    // Connecting: second tap cancels the walk (issue #147). Do not reconcile
    // with native here — getStatus() idle during Binding/Proving used to
    // demote Nest to rest while the tunnel was coming up.
    if (status is VpnConnecting || notifier.isConnectInFlight) {
      UiLog.action(
        'home',
        'nest',
        level: ProductLogLevel.info,
        extra: {'do': 'disconnect', 'ui': ui},
      );
      await notifier.disconnect();
      return;
    }

    if (status is VpnDisconnected || status is VpnError) {
      if (freeKeyClient && _importedScheme == null) {
        UiLog.action('home', 'nest', result: 'import', extra: {'ui': ui});
        context.push('/import');
        return;
      }
      final allowed = await VpnDisclosureDialog.ensureAccepted(context);
      if (!allowed || !mounted) {
        UiLog.action(
          'home',
          'nest',
          result: 'ignored',
          reason: allowed ? 'unmounted' : 'disclosure',
        );
        return;
      }
      UiLog.action(
        'home',
        'nest',
        level: ProductLogLevel.info,
        extra: {'do': 'connect', 'ui': ui},
      );
      await notifier.connect();
      return;
    }

    if (status is VpnConnected) {
      UiLog.action(
        'home',
        'nest',
        level: ProductLogLevel.info,
        extra: {'do': 'disconnect', 'ui': ui},
      );
      await notifier.disconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final vpnStatus = ref.watch(vpnProvider);

    if (freeKeyClient) {
      ref.listen(importedProfilesProvider, (previous, next) {
        if (next.valueOrNull == null) return;
        unawaited(_refreshServerCard());
      });
    }

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
      backgroundColor:
          freeKeyClient ? Colors.transparent : theme.colorScheme.surface,
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
                trafficMeta: _trafficMeta,
                serverFlag: _serverFlag,
                selectionIsAuto: _selectionIsAuto,
                autoPoolFlags: _autoPoolFlags,
                noVpnEnabled: _noVpnEnabled,
                noVpnTotal: _noVpnTotal,
                onNestTap: _onNestTap,
                onPlaceRefresh: _refreshServerCard,
                onOpenLocations: () {
                  UiLog.action('home', 'open', extra: {'route': '/locations'});
                  context.go('/locations');
                },
                onOpenSubscription: _openSubscription,
                onOpenNoVpn: () async {
                  UiLog.action('home', 'open',
                      extra: {'route': '/settings/no-vpn'});
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
    this.trafficMeta,
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
  final String? trafficMeta;
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
  Timer? _uptimeTick;

  @override
  void initState() {
    super.initState();
    _uptimeTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || widget.status is! VpnConnected) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _uptimeTick?.cancel();
    super.dispose();
  }

  /// Last Free meter so a background refresh does not unmount the bar.

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
      unawaited(widget.onPlaceRefresh());
      // Session end → traffic just got scraped server-side; refresh the meter.
      if (oldWidget.status is VpnConnected &&
          widget.status is VpnDisconnected) {
        // Local profiles have no server-side traffic meter.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final status = widget.status;
    final treeState = _treeState;
    final showVpnSettingsCta =
        status is VpnError && status.code == kVpnConflictErrorCode;

    final nestSize = freeKeyClient
        ? math.min(
            340.0,
            math.min(
              size.width * 0.88,
              math.max(200.0, widget.maxHeight - 340),
            ),
          )
        : math.min(
            320.0,
            math.min(size.width * 0.78, widget.maxHeight * 0.46),
          );

    return _FreeClientHome(
      nestSize: nestSize,
      treeState: treeState,
      status: status,
      serverTitle: widget.serverTitle,
      trafficMeta: widget.trafficMeta,
      onNestTap: widget.onNestTap,
      showVpnSettingsCta: showVpnSettingsCta,
      noVpnEnabled: widget.noVpnEnabled,
      noVpnTotal: widget.noVpnTotal,
      onOpenNoVpn: widget.onOpenNoVpn,
    );
  }
}

class _FreeClientHome extends StatelessWidget {
  const _FreeClientHome({
    required this.nestSize,
    required this.treeState,
    required this.status,
    required this.serverTitle,
    this.trafficMeta,
    required this.onNestTap,
    required this.showVpnSettingsCta,
    required this.noVpnEnabled,
    required this.noVpnTotal,
    required this.onOpenNoVpn,
  });

  final double nestSize;
  final TreeState treeState;
  final VpnStatus status;
  final String serverTitle;
  final String? trafficMeta;
  final Future<void> Function() onNestTap;
  final bool showVpnSettingsCta;
  final int noVpnEnabled;
  final int noVpnTotal;
  final VoidCallback onOpenNoVpn;

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final empty = serverTitle == '…' ||
        serverTitle == 'Нет ссылки' ||
        serverTitle == 'No link';
    final parsedTraffic = parseSubscriptionTraffic(trafficMeta);
    final traffic = formatSubscriptionTraffic(
      parsedTraffic,
      russian: Localizations.localeOf(context).languageCode == 'ru',
    );
    final trafficColor = switch (trafficRemainderBand(parsedTraffic)) {
      TrafficRemainderBand.above20 => AppBrand.success,
      TrafficRemainderBand.from5to20 => AppBrand.flame,
      TrafficRemainderBand.below5 => AppBrand.destructive,
      TrafficRemainderBand.none => null,
    };
    final current = status;
    final uptime = current is VpnConnected
        ? _formatUptime(current.connectedSince)
        : null;
    final profile = empty ? l.freeNoProfile : serverTitle;
    final statusText = switch (status) {
      VpnConnecting() => l.homeConnecting,
      VpnConnected() => l.homeConnected,
      VpnError(:final code) when code == kVpnConflictErrorCode =>
        l.homeVpnConflictTitle,
      VpnError(:final code) when code == kVpnProbeFailedErrorCode =>
        l.homeVpnProbeFailedTitle,
      VpnError(:final code, :final message)
          when windowsBrokerOwnsCaption(code) =>
        windowsGateCaption(code, message, l.homeError),
      VpnError() => l.homeError,
      VpnDisconnected() => l.homeDisconnected,
    };
    final errorHint = switch (status) {
      VpnError(:final code, :final message)
          when code == kVpnConflictErrorCode =>
        (message.isNotEmpty && message != 'vpn_conflict')
            ? homeVpnConflictHintNamedForPlatform(l, message)
            : homeVpnConflictHintForPlatform(l),
      VpnError(:final code, :final message)
          when code == kVpnProbeFailedErrorCode =>
        l.homeVpnProbeFailedHint(
          message.isNotEmpty ? message : l.homeRegion,
        ),
      VpnError(:final code) when windowsBrokerOwnsCaption(code) => null,
      VpnError(:final code) when code == 'permission_denied' =>
        homeVpnPermissionHintForPlatform(l),
      VpnError(:final code) when code == kVpnPathIncompatibleErrorCode =>
        l.homePathIncompatibleHint,
      VpnError(:final code) when code == 'share_ios_hy2_only' ||
              code == 'share_unsupported' =>
        l.freeSchemeParked,
      VpnError(:final code) when code == 'device_limit' =>
        l.freeSubscriptionDeviceLimit,
      VpnError(:final code) when code == 'client_refused' =>
        l.freeSubscriptionClientRefused,
      VpnError() => l.homeErrorFriendly,
      _ => null,
    };

    final accent = status is VpnConnected
        ? AppBrand.success
        : status is VpnConnecting
            ? AppBrand.warning
            : AppBrand.destructive;

    return Column(
      children: [
        ConnectionStatusPanel(
          status: statusText,
          profile: profile,
          traffic: traffic,
          trafficColor: trafficColor,
          uptime: uptime,
          accent: accent,
        ),
        if (errorHint != null) ...[
          const SizedBox(height: 8),
          Text(
            errorHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_showsEmptyHint) ...[
                const SizedBox(
                  height: 96,
                  width: double.infinity,
                  child: Center(child: FreeClientEmptyState(compact: true)),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: nestSize,
                height: nestSize,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    if (status is VpnConnecting || status is VpnConnected)
                      HousePulsar(diameter: nestSize),
                    SignalNestHero(
                      key: kHomeSignalNestKey,
                      state: treeState,
                      onTap: () => onNestTap(),
                      size: nestSize,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showVpnSettingsCta) ...[
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () async {
              final opened = await VpnController.instance.openVpnSettings();
              UiLog.action(
                'home',
                'vpn_settings',
                result: opened ? 'ok' : 'fail',
              );
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
        if (status is VpnConnected && androidPerAppSplit) ...[
          const SizedBox(height: 8),
          _NoVpnHomeRow(
            label: l.homeNoVpnRow,
            enabled: noVpnEnabled,
            total: noVpnTotal,
            onTap: onOpenNoVpn,
          ),
        ],
        const SizedBox(height: 12),
        FreeClientActionBar(
          onPaste: () {
            UiLog.action('home', 'paste');
            context.push('/import?clipboard=1');
          },
          onScan: () {
            UiLog.action('home', 'scan');
            openFreeClientCapture(context);
          },
        ),
      ],
    );
  }

  bool get _showsEmptyHint {
    final noProfile = serverTitle == '…' ||
        serverTitle == 'Нет ссылки' ||
        serverTitle == 'No link';
    return noProfile &&
        status is! VpnConnecting &&
        status is! VpnConnected &&
        status is! VpnError;
  }

  String _formatUptime(DateTime since) {
    final elapsed = DateTime.now().difference(since);
    String two(int value) => value.toString().padLeft(2, '0');
    final hours = two(elapsed.inHours);
    final minutes = two(elapsed.inMinutes % 60);
    final seconds = two(elapsed.inSeconds % 60);
    return '$hours:$minutes:$seconds';
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
    final mute = theme.colorScheme.onSurfaceVariant;
    final ink = theme.brightness == Brightness.dark
        ? AppBrand.inkDark
        : AppBrand.inkLight;

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
            padding: const EdgeInsets.symmetric(vertical: 10),
            // Same two Expanded halves + 8dp gap as FreeClientActionBar.
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Ghost icon+gap so the label sits on the «Вставить» line.
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(width: 18),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: AppIcon(
                            AppIcons.chevronLeft,
                            size: 18,
                            color: mute,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 8,
                  child: Center(
                    child: Container(
                      width: 1.5,
                      height: 22,
                      color: line,
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (showAppsPin)
                          // Ghost icon+gap so the count sits on the «QR» text line.
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(width: 18),
                              const SizedBox(width: 8),
                              Text(
                                '$enabled / $total',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: ink,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: AppIcon(
                            AppIcons.chevronRight,
                            size: 18,
                            color: mute,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
