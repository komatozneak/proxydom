import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/diagnostics/ui_log.dart';
import '../../../core/ios_store_gates.dart';
import '../../../core/theme.dart';
import '../../../core/toasts/proxy_dom_toast.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_switch.dart';

import '../../../l10n/app_localizations.dart';
import '../../home/application/vpn_provider.dart';
import '../../home/application/vpn_status.dart';
import '../../vpn/data/vpn_controller.dart';
import '../data/browser_bridge.dart';
import '../data/installed_apps_channel.dart';
import '../data/site_player_discovery.dart';
import '../data/split_tunnel_prefs.dart';

/// Огонь IA: Приложения (default) | Сайты, under «Что работает без VPN?».
///
/// iOS: Apps tab parked (no consumer per-app VpnService.Builder / NE MDM).
class NoVpnScreen extends ConsumerStatefulWidget {
  const NoVpnScreen({super.key});

  @override
  ConsumerState<NoVpnScreen> createState() => _NoVpnScreenState();
}

class _NoVpnScreenState extends ConsumerState<NoVpnScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabs;
  final _search = TextEditingController();
  String _query = '';
  StreamSubscription<void>? _bridgeChanges;

  bool _loading = true;
  bool _pending = false;
  bool _reconnecting = false;
  bool _lockdownOn = false;

  /// Domains already looked at in this screen session. A page that has no
  /// players (or refuses the request) is not fetched again on every rebuild.
  final Set<String> _autoTried = <String>{};
  bool _autoRunning = false;

  /// Apps tab is Android-only.
  bool get _sitesOnly => sitesOnlySplit;

  List<SplitTunnelSite> _sites = const [];
  List<LauncherAppInfo> _apps = const [];
  Set<String> _disallowed = {};

  @override
  void initState() {
    super.initState();
    if (!_sitesOnly) {
      _tabs = TabController(length: 2, vsync: this);
    }
    _search.addListener(() {
      setState(() => _query = _search.text.trim().toLowerCase());
    });
    _bridgeChanges = BrowserBridge.instance.changes.listen((_) {
      if (mounted) unawaited(_reload());
    });
    _reload();
  }

  @override
  void dispose() {
    _bridgeChanges?.cancel();
    _tabs?.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    await SplitTunnelPrefs.purgePresetSites();
    final sites = await SplitTunnelPrefs.loadSites();
    final apps = _sitesOnly
        ? const <LauncherAppInfo>[]
        : await InstalledAppsChannel.listLauncherApps();
    if (!_sitesOnly) {
      await SplitTunnelPrefs.seedDefaultBypassIfNeeded(
        apps.map((a) => a.packageName),
      );
    }
    final disallowed = _sitesOnly
        ? <String>{}
        : await SplitTunnelPrefs.loadDisallowedPackages();
    final pendingAfterSeed = await SplitTunnelPrefs.hasPendingChanges();
    final lockdown = await VpnController.instance.queryLockdownState();
    if (!mounted) return;
    final vpn = ref.read(vpnProvider);
    final sessionLive = vpn is VpnConnected || vpn is VpnConnecting;
    setState(() {
      _sites = sites.where((s) => !s.isPreset).toList();
      _pending = sessionLive && pendingAfterSeed;
      _disallowed = disallowed;
      _apps = apps;
      _lockdownOn = lockdown == VpnLockdownState.enabled;
      _loading = false;
    });
    unawaited(_autoDiscoverPlayers());
  }

  Future<void> _afterMutation() async {
    final vpn = ref.read(vpnProvider);
    final pending = vpn is VpnConnected || vpn is VpnConnecting
        ? await SplitTunnelPrefs.hasPendingChanges()
        : false;
    final sites = await SplitTunnelPrefs.loadSites();
    final disallowed = await SplitTunnelPrefs.loadDisallowedPackages();
    if (!mounted) return;
    setState(() {
      _sites = sites.where((s) => !s.isPreset).toList();
      _disallowed = disallowed;
      _pending = pending;
    });
    unawaited(_autoDiscoverPlayers());
  }

  /// Attaches embedded player hosts without a button or a second gesture.
  ///
  /// Runs after the sites paint, once per domain per screen session. It is
  /// deliberately silent when a page has nothing to find: a normal user should
  /// never have to know that discovery exists.
  Future<void> _autoDiscoverPlayers() async {
    if (_autoRunning) return;
    final targets = _sites
        .where(
          (s) =>
              s.enabled && s.players.isEmpty && !_autoTried.contains(s.domain),
        )
        .toList();
    if (targets.isEmpty) return;
    _autoRunning = true;
    var found = 0;
    try {
      for (final site in targets) {
        _autoTried.add(site.domain);
        final players = await SitePlayerDiscovery.discover(site.domain);
        if (players.isEmpty) continue;
        final merged = normalizeSplitTunnelPlayers(site.domain, [
          ...site.players,
          ...players,
        ]);
        if (merged.length == site.players.length) continue;
        final saved = await SplitTunnelPrefs.updateSite(
          site.copyWith(players: merged),
        );
        if (saved) found += merged.length - site.players.length;
      }
      if (!mounted || found == 0) return;
      await _afterMutation();
      if (!mounted) return;
      UiLog.action(
        'no_vpn',
        'auto_players',
        result: 'ok',
        extra: {'count': found},
      );
      showProxyDomToast(
        AppL10n.of(context).splitTunnelPlayersFound(found),
        tone: ToastTone.success,
      );
    } finally {
      _autoRunning = false;
    }
  }

  Future<void> _reconnect() async {
    UiLog.action('no_vpn', 'reconnect');
    setState(() => _reconnecting = true);
    final l = AppL10n.of(context);
    try {
      final ok = await ref.read(vpnProvider.notifier).reconnectToApplyRouting();
      UiLog.action('no_vpn', 'reconnect', result: ok ? 'ok' : 'fail');
      if (!mounted) return;
      showProxyDomToast(
        ok ? l.splitTunnelApplied : l.splitTunnelApplyFailed,
        tone: ok ? ToastTone.success : ToastTone.failure,
      );
      await _afterMutation();
    } finally {
      if (mounted) setState(() => _reconnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final appsLabel = lang == 'en' ? 'Apps' : 'Приложения';
    final sitesLabel = lang == 'en' ? 'Sites' : 'Сайты';
    final appsSection = lang == 'en' ? 'Apps' : 'Приложения';

    final sheet = theme.brightness == Brightness.dark
        ? AppBrand.surfaceDark
        : AppBrand.surfaceElevatedLight;
    return Scaffold(
      backgroundColor: sheet,
      appBar: AppBar(
        backgroundColor: sheet,
        surfaceTintColor: sheet,
        title: Text(l.settingsNoVpn),
        leading: IconButton(
          icon: const AppIcon(AppIcons.back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/settings');
            }
          },
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: lang == 'en' ? 'Search' : 'Поиск',
                      prefixIcon: const AppIcon(AppIcons.search),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppBrand.radiusPill),
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                if (!_sitesOnly)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius:
                            BorderRadius.circular(AppBrand.radiusNavPill),
                      ),
                      child: TabBar(
                        controller: _tabs,
                        dividerColor: Colors.transparent,
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicator: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius:
                              BorderRadius.circular(AppBrand.radiusNavPill),
                          border: Border.all(color: AppBrand.primary),
                        ),
                        labelColor: theme.brightness == Brightness.dark
                            ? AppBrand.inkDark
                            : AppBrand.inkLight,
                        unselectedLabelColor:
                            theme.brightness == Brightness.dark
                                ? AppBrand.inkMutedDark
                                : theme.colorScheme.onSurfaceVariant,
                        tabs: [
                          Tab(text: appsLabel),
                          Tab(text: sitesLabel),
                        ],
                      ),
                    ),
                  ),
                if (_pending)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.outline.withValues(
                            alpha: 0.55,
                          ),
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              l.splitTunnelPendingBody,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _ReconnectKey(
                            reconnecting: _reconnecting,
                            onPressed: _reconnect,
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: _sitesOnly
                      ? _SitesTab(
                          sites: _filteredSites,
                          onToggleSite: (site, enabled) async {
                            UiLog.action(
                              'no_vpn',
                              'site',
                              extra: {'on': enabled},
                            );
                            await SplitTunnelPrefs.updateSite(
                              site.copyWith(enabled: enabled),
                            );
                            await _afterMutation();
                          },
                          onDeleteSite: _deleteSite,
                          onAddSite: _showAddSite,
                        )
                      : TabBarView(
                          controller: _tabs,
                          children: [
                            _AppsTab(
                              apps: _filteredApps,
                              disallowed: _disallowed,
                              sectionLabel: appsSection,
                              lockdownOn: _lockdownOn,
                              lockdownWarning: l.splitTunnelAppsLockdownWarning,
                              onToggle: (pkg, bypass) async {
                                UiLog.action(
                                  'no_vpn',
                                  'app',
                                  extra: {'bypass': bypass},
                                );
                                await SplitTunnelPrefs.setDisallowedPackage(
                                  pkg,
                                  bypass,
                                );
                                await _afterMutation();
                              },
                            ),
                            _SitesTab(
                              sites: _filteredSites,
                              onToggleSite: (site, enabled) async {
                                UiLog.action(
                                  'no_vpn',
                                  'site',
                                  extra: {'on': enabled},
                                );
                                await SplitTunnelPrefs.updateSite(
                                  site.copyWith(enabled: enabled),
                                );
                                await _afterMutation();
                              },
                              onDeleteSite: _deleteSite,
                              onAddSite: _showAddSite,
                            ),
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  List<LauncherAppInfo> get _filteredApps {
    final q = _query;
    final filtered = q.isEmpty
        ? _apps
        : _apps
            .where(
              (a) =>
                  a.label.toLowerCase().contains(q) ||
                  a.packageName.toLowerCase().contains(q),
            )
            .toList();
    // Apps that bypass the tunnel come first, then the rest; each group stays
    // alphabetical. The active block is what a person opens this tab to check.
    final sorted = [...filtered];
    sorted.sort((a, b) {
      final aOn = _disallowed.contains(a.packageName);
      final bOn = _disallowed.contains(b.packageName);
      if (aOn != bOn) return aOn ? -1 : 1;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return sorted;
  }

  List<SplitTunnelSite> get _filteredSites {
    if (_query.isEmpty) return _sites;
    return _sites
        .where(
          (s) =>
              s.domain.contains(_query) ||
              s.label.toLowerCase().contains(_query),
        )
        .toList();
  }

  Future<void> _deleteSite(SplitTunnelSite site) async {
    final l = AppL10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: Text(l.splitTunnelDelete),
        content: Text(l.splitTunnelDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.splitTunnelCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.splitTunnelDelete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      UiLog.action('no_vpn', 'delete_site',
          result: 'ignored', reason: 'confirm');
      return;
    }
    UiLog.action('no_vpn', 'delete_site');
    await SplitTunnelPrefs.deleteSite(site.id);
    await _afterMutation();
  }

  Future<void> _showAddSite() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useRootNavigator: true,
      builder: (ctx) => const _AddSiteSheet(),
    );
    if (!mounted) return;
    if (saved == true) await _afterMutation();
  }
}

class _AppsTab extends StatelessWidget {
  const _AppsTab({
    required this.apps,
    required this.disallowed,
    required this.sectionLabel,
    required this.lockdownOn,
    required this.lockdownWarning,
    required this.onToggle,
  });

  final List<LauncherAppInfo> apps;
  final Set<String> disallowed;
  final String sectionLabel;
  final bool lockdownOn;
  final String lockdownWarning;
  final Future<void> Function(String packageName, bool bypass) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled =
        apps.where((a) => disallowed.contains(a.packageName)).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (lockdownOn) ...[
          Text(
            lockdownWarning,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Text('• $sectionLabel', style: theme.textTheme.titleSmall),
            const Spacer(),
            Text(
              '$enabled / ${apps.length}',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (apps.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text(
              Localizations.localeOf(context).languageCode == 'en'
                  ? 'No apps found on this device.'
                  : 'На устройстве не найдено приложений.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final app in apps)
            _AllowRow(
              leading: _AppIconAvatar(
                iconPng: app.iconPng,
                fallbackLetter:
                    app.label.isNotEmpty ? app.label[0].toUpperCase() : '?',
              ),
              title: app.label,
              value: disallowed.contains(app.packageName),
              onChanged: (v) => onToggle(app.packageName, v),
            ),
      ],
    );
  }
}

/// One allowlist row, with the house switch. Material's adaptive switch drew a
/// grey pill here while the same setting on Settings was gold.
class _AllowRow extends StatelessWidget {
  const _AllowRow({
    this.leading,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final Widget? leading;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  if (subtitle != null) ...[
                    const SizedBox(height: 1),
                    Text(subtitle!, style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            AppSwitch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _AppIconAvatar extends StatelessWidget {
  const _AppIconAvatar({
    this.iconPng,
    required this.fallbackLetter,
  });

  final Uint8List? iconPng;
  final String fallbackLetter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = iconPng;
    if (bytes != null && bytes.isNotEmpty) {
      return ClipOval(
        child: Image.memory(
          bytes,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _glyphOrLetter(theme),
        ),
      );
    }
    return _glyphOrLetter(theme);
  }

  Widget _glyphOrLetter(ThemeData theme) {
    return CircleAvatar(
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      child: Text(
        fallbackLetter,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SitesTab extends StatefulWidget {
  const _SitesTab({
    required this.sites,
    required this.onToggleSite,
    required this.onDeleteSite,
    required this.onAddSite,
  });

  final List<SplitTunnelSite> sites;
  final Future<void> Function(SplitTunnelSite site, bool enabled) onToggleSite;
  final Future<void> Function(SplitTunnelSite site) onDeleteSite;
  final VoidCallback onAddSite;

  @override
  State<_SitesTab> createState() => _SitesTabState();
}

class _SitesTabState extends State<_SitesTab> {
  /// Swipe-to-delete looked the same as scrolling and left no undo. The pencil
  /// makes deletion a mode: nothing on a row can delete a site until the person
  /// has asked for the X, and the X still goes through the confirm dialog.
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppL10n.of(context);
    final sites = widget.sites;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // The preset services are no longer rows: they are already excluded
        // from the tunnel by default. This tab is only the person's own list.
        Text(
          l.splitTunnelSitesLead,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              '• ${l.splitTunnelCustomSection}',
              style: theme.textTheme.titleSmall,
            ),
            const Spacer(),
            Text(
              '${sites.where((s) => s.enabled).length} / ${sites.length}',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            AppRingButton(
              icon: _editing ? AppIcons.check : AppIcons.pencil,
              color: theme.colorScheme.primary,
              size: 36,
              iconSize: 18,
              tooltip: _editing ? l.splitTunnelEditDone : l.splitTunnelEdit,
              onPressed: () => setState(() => _editing = !_editing),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (sites.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              l.splitTunnelEmptyBody,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (final site in sites)
            Row(
              key: ValueKey(site.id),
              children: [
                Expanded(
                  child: _AllowRow(
                    title: site.label.isNotEmpty ? site.label : site.domain,
                    subtitle: site.label.isNotEmpty
                        ? site.domain
                        : (site.players.isEmpty
                            ? null
                            : l.splitTunnelPlayersCount(site.players.length)),
                    value: site.enabled,
                    onChanged: (v) => widget.onToggleSite(site, v),
                  ),
                ),
                if (_editing)
                  AppRingButton(
                    icon: AppIcons.x,
                    color: theme.colorScheme.error,
                    size: 36,
                    iconSize: 16,
                    tooltip: l.splitTunnelDelete,
                    onPressed: () => widget.onDeleteSite(site),
                  ),
              ],
            ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: widget.onAddSite,
          icon: const AppIcon(AppIcons.plus),
          label: Text(l.splitTunnelAddSite),
        ),
      ],
    );
  }
}

class _ReconnectKey extends StatelessWidget {
  const _ReconnectKey({
    required this.reconnecting,
    required this.onPressed,
  });

  final bool reconnecting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final l = AppL10n.of(context);
    final ink = dark ? AppBrand.inkGoldDark : AppBrand.inkGoldLight;
    final wash = AppBrand.mascotGold.withValues(alpha: dark ? 0.16 : 0.10);
    return TextButton.icon(
      onPressed: reconnecting ? null : onPressed,
      style: TextButton.styleFrom(
        foregroundColor: ink,
        backgroundColor: wash,
        disabledForegroundColor: ink.withValues(alpha: 0.55),
        disabledBackgroundColor: wash,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(0, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const StadiumBorder(),
        side: BorderSide(
          color: AppBrand.mascotGold.withValues(alpha: 0.35),
        ),
        textStyle: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      icon: reconnecting
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: ink),
            )
          : AppIcon(AppIcons.refresh, size: 15, color: ink),
      label: Text(
        reconnecting
            ? l.splitTunnelReconnectInProgress
            : l.splitTunnelReconnect,
      ),
    );
  }
}

class _AddSiteSheet extends StatefulWidget {
  const _AddSiteSheet();

  @override
  State<_AddSiteSheet> createState() => _AddSiteSheetState();
}

class _AddSiteSheetState extends State<_AddSiteSheet> {
  final _domain = TextEditingController();
  final _label = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _domain.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppL10n.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    final normalized = normalizeSplitTunnelDomain(_domain.text);
    if (normalized is! DomainNormalizeOk) {
      _fail(normalized as DomainNormalizeErr, l);
      return;
    }
    // The player lives on another host. Read the page now, while the person is
    // still on this sheet, so the site and its player are one saved thing.
    final players = await SitePlayerDiscovery.discover(normalized.domain);
    final result = await SplitTunnelPrefs.addSite(
      domain: normalized.domain,
      label: _label.text,
      players: players,
    );
    if (!mounted) return;
    if (result is DomainNormalizeOk) {
      UiLog.action(
        'no_vpn',
        'add_site',
        result: 'ok',
        extra: {'players': players.length},
      );
      if (players.isNotEmpty) {
        showProxyDomToast(
          l.splitTunnelPlayersFound(players.length),
          tone: ToastTone.success,
        );
      }
      Navigator.pop(context, true);
      return;
    }
    _fail(result as DomainNormalizeErr, l);
  }

  void _fail(DomainNormalizeErr err, AppL10n l) {
    UiLog.action('no_vpn', 'add_site', result: 'bad', reason: err.kind.name);
    setState(() {
      _saving = false;
      _error = switch (err.kind) {
        DomainNormalizeErrorKind.duplicate => l.splitTunnelDuplicateDomain,
        DomainNormalizeErrorKind.nonAscii => l.splitTunnelNonAsciiUnsupported,
        _ => l.splitTunnelInvalidDomain,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.splitTunnelAddSite,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _label,
            decoration: InputDecoration(
              labelText: l.splitTunnelSiteNameOptional,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _domain,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l.splitTunnelDomainLabel,
              hintText: l.splitTunnelDomainHint,
              errorText: _error,
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l.splitTunnelSave),
          ),
        ],
      ),
    );
  }
}
