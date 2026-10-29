import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/busy/busy_overlay.dart';
import '../../../core/diagnostics/product_log.dart';
import '../../../core/diagnostics/ui_log.dart';
import '../../../core/ios_store_gates.dart';
import '../../../core/theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/toasts/proxy_dom_toast.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_surface.dart';
import '../../../core/widgets/house_orbit.dart';
import '../../../core/widgets/proxydom_ground.dart';
import '../../../core/widgets/connect_button.dart';
import '../../../core/widgets/house_pulsar.dart';
import '../../../core/widgets/signal_nest_hero.dart';

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
import '../../vpn/presentation/server_glyph.dart';
import '../../vpn/presentation/vpn_disclosure_dialog.dart';
import '../../vpn/presentation/vpn_platform_copy.dart';
import '../data/battery_prompt_prefs.dart';
import '../application/home_stats_provider.dart';
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

  /// True while the house is burning: pressed, connecting or connected. The
  /// button is dark at rest and lights on touch — the light is the state.
  bool _charged = false;

  Timer? _yardTimer;
  Timer? _chargeTimer;

  /// Publishes the lit level to the night behind the screen.
  void _setYard(double value) {
    GroundGlowScope.maybeOf(context)?.set(value);
    if (_yardGlow == value) return;
    setState(() => _yardGlow = value);
  }

  void _setCharged(bool value) {
    if (_charged == value) return;
    setState(() => _charged = value);
  }

  /// A tap on the house wakes the yard for a beat, whatever the tunnel does.
  ///
  /// The lamp goes out on its own, and how long that takes is the difference
  /// between a light and a delay. Too long and the house stays lit after you
  /// let go, which reads as the button having missed; too short and the yard
  /// snaps off, which reads as the button having broken. The charge holds for
  /// 820ms and the ground dies at 480 - ground always goes last, because a
  /// floor takes longer to cool than a lamp.
  void _wakeYard() {
    _yardTimer?.cancel();
    _chargeTimer?.cancel();
    _setYard(1.0);
    _setCharged(true);
    _chargeTimer = Timer(const Duration(milliseconds: 820), () {
      if (!mounted) return;
      _setCharged(_yardFor(ref.read(vpnProvider)) > _yardResting + 0.01);
    });
    _yardTimer = Timer(const Duration(milliseconds: 480), () {
      if (mounted) _setYard(_yardFor(ref.read(vpnProvider)));
    });
  }

  /// The tunnel decides how bright the house is.
  double _yardFor(Object status) {
    if (status is VpnConnected) return 1.0;
    if (status is VpnConnecting) return 0.75;
    return _yardResting;
  }

  /// Makes the lamp agree with the tunnel.
  ///
  /// A server pick drops the tunnel without touching the house. The press
  /// flash is the only other owner of the lamp, and it has its own timer: if
  /// that timer is quiet, a disconnected tunnel is a dark house. Skipping the
  /// update while the yard was already fully lit left the rings burning on a
  /// screen that already said it was disconnected.
  void _applyTunnelLight(VpnStatus status) {
    final live = status is VpnConnected || status is VpnConnecting;
    if (live) {
      _chargeTimer?.cancel();
      _yardTimer?.cancel();
      _setCharged(true);
      _setYard(_yardFor(status));
      return;
    }
    if (_chargeTimer?.isActive == true) return;
    _yardTimer?.cancel();
    _setCharged(false);
    _setYard(_yardResting);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The listener only hears changes. A house that opens onto a tunnel
      // that is already up (or already down) still has to match it.
      _applyTunnelLight(ref.read(vpnProvider));
      unawaited(_onHomeReady());
    });
  }

  @override
  void dispose() {
    _yardTimer?.cancel();
    _chargeTimer?.cancel();
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
        // The chip is a server selector: address, not the node's marketing
        // line. The port is dropped when it is the default 443 — it is the
        // same address and it is what made the line ellipsise.
        final endpoint = selected.endpoint;
        _serverSubtitle = endpoint.endsWith(':443')
            ? endpoint.substring(0, endpoint.length - 4)
            : endpoint;
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
      _applyTunnelLight(next);
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
              charged: _charged,
              serverTitle: _serverTitle == '…' && _selectionIsAuto
                  ? l.regionAutoTitle
                  : _serverTitle,
              serverSubtitle: _serverSubtitle.isEmpty
                  ? (_selectionIsAuto ? l.regionAutoSubtitle : l.homeStatServer)
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
                padding: const EdgeInsets.fromLTRB(
                  AppBrand.pageGutterWide,
                  28,
                  AppBrand.pageGutterWide,
                  28,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1080),
                    child: content,
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(
                AppBrand.pageGutter,
                8,
                AppBrand.pageGutter,
                12,
              ),
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
    required this.charged,
    required this.serverTitle,
    required this.serverSubtitle,
    this.trafficMeta,
    this.serverFlag,
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

  /// The house is burning: pressed, connecting or connected.
  final bool charged;
  final String serverTitle;
  final String serverSubtitle;
  final String? trafficMeta;
  final String? serverFlag;
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
    // The host of the line actually dialed. This used to read the egress host off
    // the backend config, which the local configurator never fetches, so the
    // read was always null and the warm-up never ran.
    final host = ref.read(vpnProvider.notifier).profileHost;
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
    // panel and the keys; in a window it keeps to the same share of the frame.
    // It used to be a fixed 300..440 of the window height: at the opening size
    // (826x591) that left the house wider than the column it stands in and the
    // artwork spilled over the readout above it. A window is a small window now,
    // so the house is sized for it.
    final nestSize = windowsDesktop
        ? math.min(300.0, math.max(200.0, size.height * 0.46))
        // A phone has no room to be generous: the house takes a little over half
        // the width and lets the night show around it. At 0.98 of the width it
        // became the wallpaper and the yard behind it stopped existing.
        : math.min(
            size.width * 0.78,
            math.max(210.0, widget.maxHeight * 0.34),
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

    final traffic = ref.watch(trafficStatsProvider).valueOrNull ??
        const VpnTrafficStats.zero();

    return _FreeClientHome(
      nestSize: nestSize,
      charged: widget.charged,
      treeState: treeState,
      status: status,
      serverTitle: widget.serverTitle,
      serverSubtitle: widget.serverSubtitle,
      serverFlag: widget.serverFlag,
      trafficMeta: widget.trafficMeta,
      speedDown: traffic.downlinkBps,
      speedUp: traffic.uplinkBps,
      onNestTap: widget.onNestTap,
      onOpenLocations: widget.onOpenLocations,
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
    required this.charged,
    required this.treeState,
    required this.status,
    required this.serverTitle,
    this.serverSubtitle,
    this.serverFlag,
    this.trafficMeta,
    required this.speedDown,
    required this.speedUp,
    required this.onNestTap,
    required this.onOpenLocations,
    required this.showVpnSettingsCta,
    required this.noVpnEnabled,
    required this.noVpnTotal,
    required this.onOpenNoVpn,
  });

  final double nestSize;

  /// The house is burning: pressed, connecting or connected.
  final bool charged;
  final TreeState treeState;
  final VpnStatus status;
  final String serverTitle;

  /// The node's own note, under the name in the terminal head.
  final String? serverSubtitle;

  /// The flag shown beside the server name in the terminal head.
  final String? serverFlag;
  final String? trafficMeta;
  final int speedDown;
  final int speedUp;
  final Future<void> Function() onNestTap;
  final VoidCallback onOpenLocations;
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
    final current = status;
    final uptime =
        current is VpnConnected ? _formatUptime(current.connectedSince) : null;
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
      VpnError(:final code)
          when code == 'share_ios_hy2_only' || code == 'share_unsupported' =>
        l.freeSchemeParked,
      VpnError(:final code) when code == 'device_limit' =>
        l.freeSubscriptionDeviceLimit,
      VpnError(:final code) when code == 'client_refused' =>
        l.freeSubscriptionClientRefused,
      VpnError(:final code) when code == kNodeAuthRefusedErrorCode =>
        l.homeNodeAuthRefused,
      VpnError() => l.homeErrorFriendly,
      _ => null,
    };

    // Disconnected is a normal state, not a failure: painting it alarm red
    // made the resting screen look broken. Red is reserved for VpnError.
    //
    // Connected is green, not gold. Gold is the house: it is what the button
    // wears, what the section rule wears, what the traffic fills with. Using
    // the house's own colour for "connected" said nothing — an all-gold screen
    // reported every state the same way. Green is the one hue in the palette
    // that means a thing is working, and it is the same green the rail gives a
    // chosen server.
    final ok = theme.brightness == Brightness.dark
        ? AppBrand.mossLight
        : AppBrand.moss;
    final accent = switch (status) {
      VpnConnected() => ok,
      VpnConnecting() => AppBrand.destructive,
      VpnError() => AppBrand.destructive,
      _ => theme.colorScheme.onSurfaceVariant,
    };

    // One tight cluster: status above, the house in the middle, the keys under.
    // Nothing is scattered across the screen — the eye has one place to land,
    // and that place is the power button.
    final isConnected = status is VpnConnected;
    final isConnecting = status is VpnConnecting;
    final statusInk = switch (status) {
      VpnConnected() => theme.brightness == Brightness.dark
          ? AppBrand.inkMossDark
          : AppBrand.inkMossLight,
      VpnConnecting() => theme.brightness == Brightness.dark
          ? AppBrand.inkDangerDark
          : AppBrand.inkDangerLight,
      VpnError() => theme.brightness == Brightness.dark
          ? AppBrand.inkDangerDark
          : AppBrand.inkDangerLight,
      _ => theme.colorScheme.onSurfaceVariant,
    };
    final String? houseLabel = empty
        ? l.homeAddServer
        : switch (status) {
            VpnConnected() => null,
            // While connecting the chip is the only status.
            VpnConnecting() => null,
            _ => l.homeConnect,
          };
    // The house keeps one action label only in the idle/error state. Connected
    // and connecting states live in the chip; a second "Отключить"/"Защищено"
    // under the house was a duplicate and made the hero top-heavy.
    final hero = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The button and the dance share one box, so the lights ring the roof
        // without pushing the layout wider than the screen.
        SizedBox(
          width: nestSize,
          height: nestSize,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // The house is a control, but the ring was a second, static
              // control around it. The orbit and the lit gradient are the
              // animation; there is no hoop.
              // The dance belongs to the house, not to the wallpaper: it is
              // drawn around the button and only while the button burns.
              Positioned.fill(
                child: HouseOrbit(
                  burning: charged ? 1.0 : (isConnecting ? 0.45 : 0.0),
                ),
              ),
              // The familiar pulse: it answers the finger whether or not
              // the tunnel has moved yet.
              if (charged || isConnecting) HousePulsar(diameter: nestSize),
              // The artwork is painted larger than the tap box: the mark
              // ships with a wide transparent margin, and at box size the house
              // read as a small token lost in the middle of the screen.
              // Scaling the painting rather than the box keeps the layout
              // honest — nothing overflows the column, the house just draws
              // past its own frame.
              // Unlit, not muddy: alpha-fading the mark turned the gold to mud. The house
              // stays crisp at rest and the difference is carried by the light
              // itself — no bloom, no orbit, no pulse until a finger lands on
              // it.
              AnimatedOpacity(
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOut,
                opacity: charged ? 1.0 : 0.74,
                child: Transform.scale(
                  // The artwork is drawn inside a frame with its own margin, so
                  // the scale that fills a window's empty column would eat a
                  // phone whole. A window has no empty column to fill any more —
                  // it opens at 826x591 — so both platforms use one scale and
                  // the house spills ~15% past its box instead of 45%.
                  scale: 1.16,
                  child: SignalNestHero(
                    key: kHomeSignalNestKey,
                    state: treeState,
                    onTap: () => onNestTap(),
                    size: nestSize,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // The label is the affordance: the house was a picture, and a picture
        // is not a button. It sits outside the tap box so TalkBack reads one
        // button, not a decorative image plus a label. Connecting has no label:
        // the chip is the one status on this screen.
        if (houseLabel != null)
          Text(
            houseLabel,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
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
              showProxyDomToast(
                settingsKillSwitchOpenFailedForPlatform(l),
                tone: ToastTone.failure,
              );
            }
          },
          child: Text(l.settingsKillSwitchOpenVpn),
        ),
      ],
      // On Android the row is always here, not only while connected: it used
      // to appear on connect and move the house and the keys under the finger.
      if (androidPerAppSplit) ...[
        const SizedBox(height: 10),
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.4,
          child: _NoVpnHomeRow(
            label: l.homeNoVpnRow,
            enabled: noVpnEnabled,
            total: noVpnTotal,
            onTap: onOpenNoVpn,
          ),
        ),
      ],
    ];

    // One composition for both: the house in the middle with the yard around it,
    // the readout under it, the keys under that. The mascot is the button, so
    // nothing else may sit above it or compete with it.
    // A home fills its screen or it looks abandoned: head anchored at the top,
    // the button in the middle, the actions at the bottom. One column, one
    // measure, so the eye runs straight down it.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 4),
            // Dense chrome caps at 1.5×; the hero copy and the rest of the
            // app still follow the system scale. At 2× the chip was showing
            // "Не подк…" and the address lost the host.
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.5,
              child: _ServerChip(
                title: empty ? l.homeAddServer : profile,
                subtitle: empty ? l.freeAddHint : (serverSubtitle ?? ''),
                flag: serverFlag,
                statusText: statusText,
                statusInk: statusInk,
                dotColor: accent,
                onTap: onOpenLocations,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              // Scales the button down on a short window instead of
              // overflowing it: a tunnel that cannot be pressed is worse than
              // a slightly smaller house.
              child: Center(
                child: FittedBox(fit: BoxFit.scaleDown, child: hero),
              ),
            ),
            if (!empty) ...[
              const SizedBox(height: 6),
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.4,
                child: _MetricsCard(
                  uptime: isConnected ? uptime : null,
                  downBps: isConnected ? speedDown : 0,
                  upBps: isConnected ? speedUp : 0,
                  traffic: traffic,
                  parsedTraffic: parsedTraffic,
                ),
              ),
            ],
            if (errorHint != null) ...[
              const SizedBox(height: 8),
              Text(
                errorHint,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 12),
            ],
            ...actions,
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
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

/// The server is a chip, not the hero: name, address, state, one chevron.
class _ServerChip extends StatelessWidget {
  const _ServerChip({
    required this.title,
    required this.subtitle,
    required this.flag,
    required this.statusText,
    required this.statusInk,
    required this.dotColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String? flag;
  final String statusText;
  final Color statusInk;
  final Color dotColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = theme.colorScheme.outline;
    final dark = theme.brightness == Brightness.dark;
    final pillFill = Color.lerp(
      theme.colorScheme.surface,
      dotColor,
      dark ? 0.18 : 0.09,
    )!;
    final pillLit = Color.lerp(
      pillFill,
      AppBrand.lightSource,
      dark ? 0.05 : 0.20,
    )!;
    final pillEdge = Color.lerp(
      theme.colorScheme.surface,
      dotColor,
      dark ? 0.55 : 0.35,
    )!;
    final pillShadow = dark
        ? Colors.black.withValues(alpha: 0.30)
        : Colors.black.withValues(alpha: 0.08);
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBrand.radiusCard),
        side: BorderSide(color: line.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // The same mark the list draws: a YouTube tile for a YouTube
              // line, a flag for a country. LocationFlagIcon's product branch
              // is not the list's mark and drew a red bar here.
              ServerGlyph(
                label: PoolServerLabel(
                  title: title,
                  subtitle: '',
                  tile: tileForName(title),
                  flag: flag ?? kFlagGlobe,
                ),
                size: 36,
              ),
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
                      style: theme.textTheme.titleMedium,
                    ),
                    if (subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Profile on the left, state pinned to the right edge. The state
              // is a small milled key, not bare text: a tinted plate, a lit top
              // edge and a soft shadow, the same light language as the house.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 190),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 7, 10, 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [pillLit, pillFill],
                    ),
                    border: Border.all(color: pillEdge),
                    boxShadow: [
                      BoxShadow(
                        color: pillShadow,
                        blurRadius: 6,
                        spreadRadius: -2,
                        offset: const Offset(0, 2),
                      ),
                      BoxShadow(
                        color: AppBrand.lightSource.withValues(
                          alpha: dark ? 0.05 : 0.35,
                        ),
                        blurRadius: 0,
                        spreadRadius: -1,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          statusText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: statusInk,
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            letterSpacing: 0.1,
                            height: 1.1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: dotColor,
                          border: Border.all(
                            color: Color.lerp(
                              dotColor,
                              AppBrand.lightSource,
                              0.35,
                            )!,
                            width: 1.4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: dotColor.withValues(alpha: 0.35),
                              blurRadius: 5,
                              spreadRadius: 1,
                            ),
                          ],
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
    );
  }
}

/// Time, speed and the remaining traffic. Values that do not exist are "—";
/// nothing is made up.
class _MetricsCard extends StatelessWidget {
  const _MetricsCard({
    required this.uptime,
    required this.downBps,
    required this.upBps,
    required this.traffic,
    required this.parsedTraffic,
  });

  final String? uptime;
  final int downBps;
  final int upBps;
  final String traffic;
  final SubscriptionTraffic? parsedTraffic;

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final line = theme.colorScheme.outline;
    final parsed = parsedTraffic;
    final used = parsed == null || parsed.unlimited
        ? 0.0
        : (parsed.upload + parsed.download) / parsed.total;
    final remaining = (1.0 - used).clamp(0.0, 1.0);
    // A tank gauge, not a spend meter: full is green, empty is red, and the
    // bar shrinks as the remaining traffic does. Green holds down to 60% so a
    // healthy tank reads green, not olive.
    final barColor = remaining >= 0.6
        ? AppBrand.success
        : remaining >= 0.3
            ? Color.lerp(
                AppBrand.flame,
                AppBrand.success,
                (remaining - 0.3) / 0.3,
              )!
            : Color.lerp(
                AppBrand.destructive,
                AppBrand.flame,
                remaining / 0.3,
              )!;
    final down = downBps > 0 ? VpnTrafficStats.formatSpeed(downBps) : '—';
    final up = upBps > 0 ? VpnTrafficStats.formatSpeed(upBps) : '—';
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBrand.radiusCard),
        side: BorderSide(color: line.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Metric(
                label: l.homeMetricTime,
                value: uptime ?? '—',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: windowsDesktop
                  ? const _PingMetric()
                  : _Metric(
                      label: l.homeMetricSpeed,
                      value: '↓ $down',
                      second: '↑ $up',
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Metric(
                label: l.homeMetricTraffic,
                value: traffic,
                bar: parsed == null || parsed.unlimited
                    ? null
                    : (remaining, barColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PingMetric extends ConsumerWidget {
  const _PingMetric();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppL10n.of(context);
    final russian = Localizations.localeOf(context).languageCode == 'ru';
    final ms = ref.watch(
      pingDelayMsProvider.select((value) => value.valueOrNull),
    );
    final text = formatPingMs(ms, russian: russian);
    final semantic = ms == null
        ? '${l.homeStatPing}: ${russian ? "нет данных" : "no data"}'
        : '${l.homeStatPing}: $text';
    return Semantics(
      container: true,
      label: semantic,
      child: ExcludeSemantics(
        child: _Metric(label: l.homeStatPing, value: text),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.second,
    this.bar,
  });

  final String label;
  final String value;
  final String? second;
  final (double, Color)? bar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mono = theme.textTheme.titleMedium?.copyWith(
      fontFamily: 'JetBrainsMono',
      fontSize: 14,
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: mono,
        ),
        if (second != null)
          Text(
            second!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: mono?.copyWith(fontSize: 12),
          ),
        if (bar != null) ...[
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 7,
              child: LayoutBuilder(
                builder: (context, constraints) =>
                    TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: bar!.$1),
                  duration: const Duration(milliseconds: 650),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => Stack(
                    children: [
                      Positioned.fill(
                        child: ColoredBox(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.10),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: constraints.maxWidth * value,
                        child: ColoredBox(color: bar!.$2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
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
