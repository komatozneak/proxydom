import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/diagnostics/ui_log.dart';
import '../../../core/ios_store_gates.dart';
import '../../../core/theme.dart';
import '../../../core/toasts/proxy_dom_toast.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_switch.dart';

import '../../../l10n/app_localizations.dart';
import '../../home/application/vpn_provider.dart';
import '../../home/application/vpn_status.dart';
import '../../vpn/data/vpn_controller.dart';
import '../data/installed_apps_channel.dart';
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

  bool _loading = true;
  bool _pending = false;
  bool _reconnecting = false;
  bool _lockdownOn = false;

  /// Apps tab is Android-only (ADR 025, ADR 029).
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
    _reload();
  }

  @override
  void dispose() {
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
                  Material(
                    // tertiaryContainer is not set in AppTheme, so it falls
                    // back to `tertiary`: near-black in light, near-white in
                    // dark. bodySmall keeps onSurface, which is the same ink
                    // colour — the sentence was invisible in both themes and
                    // the strip looked like an empty band with a stray button.
                    // A surface token keeps the text on onSurfaceVariant.
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              l.splitTunnelPendingBody,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          FilledButton(
                            onPressed: _reconnecting ? null : _reconnect,
                            child: Text(
                              _reconnecting
                                  ? l.splitTunnelReconnectInProgress
                                  : l.splitTunnelReconnect,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: _sitesOnly
                      ? _SitesTab(
                          sites: _filteredSites,
                          showIosNote: true,
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

class _SitesTab extends StatelessWidget {
  const _SitesTab({
    required this.sites,
    required this.onToggleSite,
    required this.onDeleteSite,
    required this.onAddSite,
    this.showIosNote = false,
  });

  final List<SplitTunnelSite> sites;
  final Future<void> Function(SplitTunnelSite site, bool enabled) onToggleSite;
  final Future<void> Function(SplitTunnelSite site) onDeleteSite;
  final VoidCallback onAddSite;
  final bool showIosNote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppL10n.of(context);

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
        if (showIosNote) ...[
          const SizedBox(height: 8),
          Text(
            l.splitTunnelSitesIosNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
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
            Dismissible(
              key: ValueKey(site.id),
              direction: DismissDirection.endToStart,
              onDismissed: (_) => onDeleteSite(site),
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 16),
                color: theme.colorScheme.errorContainer,
                child: Text(l.splitTunnelDelete),
              ),
              child: _AllowRow(
                title: site.label.isNotEmpty ? site.label : site.domain,
                subtitle: site.label.isNotEmpty ? site.domain : null,
                value: site.enabled,
                onChanged: (v) => onToggleSite(site, v),
              ),
            ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onAddSite,
          icon: const AppIcon(AppIcons.plus),
          label: Text(l.splitTunnelAddSite),
        ),
      ],
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
    final result = await SplitTunnelPrefs.addSite(
      domain: _domain.text,
      label: _label.text,
    );
    if (!mounted) return;
    if (result is DomainNormalizeOk) {
      UiLog.action('no_vpn', 'add_site', result: 'ok');
      Navigator.pop(context, true);
      return;
    }
    final err = result as DomainNormalizeErr;
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
              helperText: l.splitTunnelDomainLatinHelper,
              errorText: _error,
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(l.splitTunnelSave),
          ),
        ],
      ),
    );
  }
}
