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
import '../../../core/widgets/app_surface.dart';
import '../../../core/widgets/proxydom_ground.dart';
import '../../../core/widgets/connect_button.dart';
import '../../../core/widgets/house_pulsar.dart';
import '../../../core/widgets/signal_nest_hero.dart';
import '../../../core/widgets/proxydom_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/data/installed_apps_channel.dart';
import '../../settings/data/split_tunnel_prefs.dart';
import '../../vpn/application/imported_profiles_provider.dart';
import '../../vpn/data/hy2_import_store.dart';
import '../../vpn/data/subscription_label.dart';
import '../../vpn/data/subscription_traffic.dart';
import '../../vpn/data/node_display.dart';
import '../../vpn/data/vpn_controller.dart';
import '../../vpn/data/windows_tunnel_protocol.dart';
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

  int _noVpnEnabled = 0;
  int _noVpnTotal = 0;
  bool _openingSubscription = false;

  /// How lit the yard is, 0…1. The shell paints it; the home decides it.
  /// Resting is not dark — an unlit yard still has fireflies.
  static const double _yardResting = 0.30;

  double _yardGlow = _yardResting;

  Timer? _yardTimer;

  /// Publishes the lit level to the night behind the screen.
  void _setYard(double value) {
    setState(() => _yardGlow = value);
    GroundGlowScope.maybeOf(context)?.set(value);
  }

  /// A tap on the house wakes the yard for a beat, whatever the tunnel does.
  void _wakeYard() {
    _yardTimer?.cancel();
    _setYard(1.0);
    _yardTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) _setYard(_yardFor(ref.read(vpnProvider)));
    });
  }

  /// The tunnel decides how bright the house is.
  double _yardFor(Object status) {
    if (status is VpnConnected) return 1.0;
    if (status is VpnConnecting) return 0.75;
    return _yardResting;
  }

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
    _yardTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    GroundGlowScope.maybeOf(context)?.set(_yardGlow);
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
    final selected = await Hy2ImportStore.instance.selected();
      final trafficMeta = await Hy2ImportStore.instance.selectedTrafficMeta();
      if (!mounted) return;
      final ru = Localizations.localeOf(context).languageCode == 'ru';
      setState(() {
        _selectionIsAuto = false;
        _autoPoolFlags = const [];
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
  }

  Future<void> _onNestTap() async {
    // The house is the main button: touching it wakes the yard before anything
    // else happens, so the light answers the finger immediately instead of
    // waiting for the tunnel.
    _wakeYard();
    if (windowsDesktop && VpnController.instance.windowsBrokerCooling) {
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
      if (_importedScheme == null) {
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
    final vpnStatus = ref.watch(vpnProvider);

    ref.listen(importedProfilesProvider, (previous, next) {
      if (next.valueOrNull == null) return;
      unawaited(_refreshServerCard());
    });

    ref.listen(vpnProvider, (prev, next) {
      // The tunnel decides how bright the house is.
      if (_yardGlow != 1.0) _setYard(_yardFor(next));
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
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // A window has room to breathe and room to stop: cap the measure so
            // the panel never stretches into a banner, and pad like a desktop
            // rather than like a phone.
            final content = _DashboardBody(
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
            );
            if (windowsDesktop) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(32, 28, 36, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1080),
                    child: content,
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: content,
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

    // The house is the focal point. On a phone it fills the band between the
    // panel and the keys; in a window it has its own column and grows with the
    // frame, otherwise a tall window leaves the bottom half empty.
    final nestSize = windowsDesktop
        ? math.min(520.0, math.max(260.0, size.height * 0.55))
        : math.min(
            340.0,
            math.min(
              size.width * 0.88,
              math.max(200.0, widget.maxHeight - 340),
            ),
          );
    // Tell the night where the house is, so the bloom belongs to it and the
    // orbit clears the roof. Published during layout: the ground repaints from
    // its own ticker and picks the numbers up on the next frame.
    GroundGlowScope.maybeOf(context)
      ?..houseRadius = nestSize * 0.5
      ..houseCenter = Alignment(
        0,
        (nestSize * 0.5) / size.height - 0.5,
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

Future<void> _refreshHomeDocuments(BuildContext context) async {
  UiLog.action('home', 'refresh', level: ProductLogLevel.info);
  final l = AppL10n.of(context);
  try {
    final catalogs = await Hy2ImportStore.instance.catalogs();
    final remote = [
      for (final catalog in catalogs)
        if (catalog.url != null && catalog.url!.isNotEmpty) catalog,
    ];
    var failed = 0;
    for (final catalog in remote) {
      try {
        await Hy2ImportStore.instance.refreshCatalog(catalog.id);
      } on Exception {
        failed++;
      }
    }
    final links = await Hy2ImportStore.instance.load();
    if (!context.mounted) return;
    if (remote.isNotEmpty && failed == remote.length) {
      UiLog.action(
        'home',
        'refresh',
        level: ProductLogLevel.warn,
        result: 'fail',
      );
      showProxyDomSnackBar(context, l.freeRefreshFail);
      return;
    }
    UiLog.action(
      'home',
      'refresh',
      level: ProductLogLevel.info,
      result: 'ok',
      extra: {'links': links.length, 'failed': failed},
    );
    showProxyDomSnackBar(context, l.freeRefreshDone(links.length));
  } catch (_) {
    if (!context.mounted) return;
    UiLog.action(
      'home',
      'refresh',
      level: ProductLogLevel.warn,
      result: 'fail',
    );
    showProxyDomSnackBar(context, l.freeRefreshFail);
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

    // Disconnected is a normal state, not a failure: painting it alarm red
    // made the resting screen look broken. Red is reserved for VpnError.
    final accent = switch (status) {
      VpnConnected() => AppBrand.mascotGoldLit,
      VpnConnecting() => AppBrand.mascotEmber,
      VpnError() => AppBrand.destructive,
      _ => theme.colorScheme.onSurfaceVariant,
    };

    // The house is the main button, so it carries the state: the readout sits
    // under it as one line instead of a plate that competes with it.
    final readout = ConnectionReadout(
      status: statusText,
      profile: profile,
      traffic: traffic,
      trafficColor: trafficColor,
      uptime: uptime,
      accent: accent,
    );
    final hero = Column(
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
    );
    final actions = <Widget>[
      if (showVpnSettingsCta) ...[
        const SizedBox(height: 14),
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
              showProxyDomSnackBar(
                context,
                settingsKillSwitchOpenFailedForPlatform(l),
              );
            }
          },
          child: Text(l.settingsKillSwitchOpenVpn),
        ),
      ],
      if (status is VpnConnected && androidPerAppSplit) ...[
        const SizedBox(height: 10),
        _NoVpnHomeRow(
          label: l.homeNoVpnRow,
          enabled: noVpnEnabled,
          total: noVpnTotal,
          onTap: onOpenNoVpn,
        ),
      ],
      const SizedBox(height: 16),
      FreeClientActionBar(
        onPaste: () {
          UiLog.action('home', 'paste');
          context.push('/import?clipboard=1');
        },
        onScan: () {
          UiLog.action('home', 'scan');
          openFreeClientCapture(context);
        },
        onRefresh: () => _refreshHomeDocuments(context),
      ),
    ];

    // One composition for both: the house in the middle with the yard around it,
    // the readout under it, the keys under that. The mascot is the button, so
    // nothing else may sit above it or compete with it.
    if (windowsDesktop) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 700;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: narrow ? double.infinity : 560,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    hero,
                    const SizedBox(height: 18),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: nestSize * 1.05),
                      child: readout,
                    ),
                    if (errorHint != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        errorHint,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    ...actions,
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    return Column(
      children: [
        Expanded(child: hero),
        const SizedBox(height: 6),
        // The readout belongs to the house: same measure, not the full width
        // of a phone.
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: nestSize * 1.05),
          child: readout,
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
        const SizedBox(height: 14),
        ...actions,
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
    final line = theme.colorScheme.outline;
    final showAppsPin = !iosAppsSplitUnsupported;
    final mute = theme.colorScheme.onSurfaceVariant;
    final ink = theme.brightness == Brightness.dark
        ? AppBrand.inkDark
        : AppBrand.inkLight;

    return AppSurface(
      radius: AppBrand.radiusPill,
      clip: true,
      child: Material(
        type: MaterialType.transparency,
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
      ),
    );
  }
}
