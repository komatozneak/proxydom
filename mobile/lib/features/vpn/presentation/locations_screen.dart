import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/diagnostics/product_log.dart';
import '../../../core/diagnostics/ui_log.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/proxydom_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import 'windows_share_qr.dart';
import '../../home/application/vpn_provider.dart';
import '../../home/application/vpn_status.dart';
import '../application/imported_profiles_provider.dart';
import '../data/hy2_import_store.dart';
import '../data/route_document.dart';
import '../data/subscription_label.dart';
import '../data/subscription_notice.dart';
import 'free_client_chrome.dart';
import 'pool_server_mark.dart';
import 'subscription_notice_view.dart';
import '../data/share_link_parser.dart';

/// Key on the Locations Auto row flag (Home/Locations icon parity tests).
const kLocationsAutoFlagKey = ValueKey<String>('locations-auto-flag');

/// Hot switch: Nest Connecting owns progress — do not block Locations with busy overlay.
@visibleForTesting
bool regionPickUsesBusyOverlay(VpnStatus status) {
  return status is! VpnConnected && status is! VpnConnecting;
}

/// Full-screen region list (Locations tab).
class LocationsScreen extends ConsumerStatefulWidget {
  const LocationsScreen({super.key});

  @override
  ConsumerState<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends ConsumerState<LocationsScreen> {
  String _query = '';

  List<ParsedShareLink> _imported = const [];
  List<ShareCatalog> _catalogs = const [];
  String? _selectedId;
  bool _loading = true;
  final _refreshing = <String>{};

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    ref.watch(vpnProvider);
    ref.listen(importedProfilesProvider, (previous, next) {
      final links = next.valueOrNull;
      if (links == null) return;
      unawaited(_applyImported(links));
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 44,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.freeServers),
            const SizedBox(width: 16),
            _ServerCountChip(
              count: _catalogs.isNotEmpty ? _catalogs.length : _imported.length,
            ),
          ],
        ),
        leading: null,
        automaticallyImplyLeading: false,
      ),
      body: _buildBody(l, theme),
    );
  }

  Future<void> _applyImported(List<ParsedShareLink> links) async {
    final index = await Hy2ImportStore.instance.selectedIndex();
    final catalogs = await Hy2ImportStore.instance.catalogs();
    if (!mounted) return;
    setState(() {
      _imported = links;
      _catalogs = catalogs;
      _selectedId = links.isEmpty ? null : '$index';
      _loading = false;
    });
  }

  Future<void> _load() async {
      // Paint the saved list before the subscription fetch. A 10s timeout
      // on a saved URL must not hide paste behind the spinner.
      try {
        await paintImportedServers(
          readLocal: () => Hy2ImportStore.instance.load(),
          refresh: () => Hy2ImportStore.instance.refreshSavedUrl(),
          paint: (links) async {
            if (!mounted) return;
            await _applyImported(links);
          },
        );
      } catch (_) {
        if (!mounted) return;
        setState(() => _loading = false);
      }
  }

  Future<void> _chooseImported(int index, {String? scheme}) async {
    UiLog.action(
      'locations',
      'select',
      extra: {
        'index': index,
        if (scheme != null) 'scheme': scheme,
      },
    );
    await Hy2ImportStore.instance.select(index);
    if (!mounted) return;
    setState(() => _selectedId = '$index');
    await _leaveForHouse('server_pick');
  }

  Future<void> _leaveForHouse(String reason) async {
    final status = ref.read(vpnProvider);
    final live = status is VpnConnected || status is VpnConnecting;
    UiLog.action(
      'locations',
      'home',
      extra: {'disconnect': live, 'why': reason},
    );
    if (live) {
      await ref.read(vpnProvider.notifier).disconnect(reason: reason);
    }
    if (!mounted) return;
    context.go('/home');
  }

  Future<void> _removeImported(int index) async {
    final ok = await confirmImportedDelete(context, catalog: false);
    if (!ok || !mounted) {
      UiLog.action('locations', 'delete', result: 'ignored', reason: 'confirm');
      return;
    }
    final selected = _selectedId == '$index';
    final status = ref.read(vpnProvider);
    final live = status is VpnConnected || status is VpnConnecting;
    UiLog.action(
      'locations',
      'delete',
      extra: {'index': index, 'disconnect': selected && live},
    );
    if (selected && live) {
      await ref.read(vpnProvider.notifier).disconnect();
    }
    await Hy2ImportStore.instance.removeAt(index);
    await _reloadLocal();
  }

  Future<void> _deleteProfile(String id) async {
    final ok = await confirmImportedDelete(context, catalog: true);
    if (!ok || !mounted) {
      UiLog.action('locations', 'delete_list',
          result: 'ignored', reason: 'confirm');
      return;
    }
    final status = ref.read(vpnProvider);
    final live = status is VpnConnected || status is VpnConnecting;
    UiLog.action('locations', 'delete_list', extra: {'disconnect': live});
    if (live) {
      await ref.read(vpnProvider.notifier).disconnect();
    }
    await Hy2ImportStore.instance.removeCatalog(id);
    await _reloadLocal();
  }

  /// Local delete must not refresh every saved URL. A 404 on one document
  /// would otherwise drop the others in the same pass.
  Future<void> _reloadLocal() async {
    final links = await Hy2ImportStore.instance.load();
    if (!mounted) return;
    await _applyImported(links);
  }

  Future<void> _shareCatalog(ShareCatalog catalog) async {
    final key = catalog.subscriptionKey;
    if (key == null || !mounted) {
      UiLog.action(
        'locations',
        'share',
        result: 'rejected',
        reason: 'empty',
      );
      return;
    }
    final l = AppL10n.of(context);
    try {
      await Clipboard.setData(ClipboardData(text: key));
    } on Object catch (e) {
      if (!mounted) return;
      UiLog.action(
        'locations',
        'share',
        result: 'fail',
        reason: e.runtimeType.toString(),
      );
      showProxyDomSnackBar(context, l.freeShareFail);
      return;
    }
    if (!mounted) return;
    UiLog.action('locations', 'share', result: 'copied');
    showProxyDomSnackBar(context, l.freeShareCopied);
  }

  Future<void> _refreshCatalog(ShareCatalog catalog) async {
    final url = catalog.url;
    if (url == null || url.isEmpty || _refreshing.contains(catalog.id)) {
      UiLog.action(
        'locations',
        'refresh',
        level: _refreshing.contains(catalog.id)
            ? ProductLogLevel.warn
            : ProductLogLevel.debug,
        result: 'rejected',
        reason: _refreshing.contains(catalog.id) ? 'busy' : 'no_url',
      );
      return;
    }
    UiLog.action(
      'locations',
      'refresh',
      level: ProductLogLevel.info,
    );
    final l = AppL10n.of(context);
    setState(() => _refreshing.add(catalog.id));
    try {
      final outcome = await Hy2ImportStore.instance.refreshCatalog(catalog.id);
      if (!mounted) return;
      await _applyImported(await Hy2ImportStore.instance.load());
      if (!mounted) return;
      final status = ref.read(vpnProvider);
      final live = status is VpnConnected || status is VpnConnecting;
      if (outcome.kind == ShareRefreshKind.deleted) {
        UiLog.action(
          'locations',
          'refresh',
          level: ProductLogLevel.info,
          result: 'deleted',
          extra: {'disconnect': outcome.selectionLeftThisList && live},
        );
        if (outcome.selectionLeftThisList && live) {
          await ref.read(vpnProvider.notifier).disconnect();
        }
        return;
      }
      if (outcome.kind == ShareRefreshKind.unchanged) {
        UiLog.action(
          'locations',
          'refresh',
          level: ProductLogLevel.info,
          result: 'unchanged',
        );
        return;
      }
      UiLog.action(
        'locations',
        'refresh',
        level: ProductLogLevel.info,
        result: 'replaced',
        extra: {
          'links': outcome.count,
          'restart': false,
        },
      );
      showProxyDomSnackBar(context, l.freeRefreshDone(outcome.count));
      if (outcome.selectionLeftThisList && live) {
        await ref.read(vpnProvider.notifier).disconnect(reason: 'refresh');
      }
    } on Exception catch (e) {
      if (!mounted) return;
      UiLog.action(
        'locations',
        'refresh',
        level: ProductLogLevel.warn,
        result: 'fail',
        reason: e.runtimeType.toString(),
      );
      showProxyDomSnackBar(context, l.freeRefreshFail);
    } finally {
      if (mounted) setState(() => _refreshing.remove(catalog.id));
    }
  }

  ({List<int> premium, List<int> general}) _catalogLineIndexes(
    ShareCatalog catalog,
  ) {
    final premium = <int>[];
    final general = <int>[];
    for (final raw in catalog.lines) {
      final index = _imported.indexWhere((link) => link.raw == raw);
      if (index < 0) continue;
      final label = labelForShareLink(_imported[index]);
      if (isPremiumPoolServer(label.title)) {
        premium.add(index);
      } else {
        general.add(index);
      }
    }
    return (premium: premium, general: general);
  }

  Widget _poolSection(ThemeData theme, String title, List<int> indexes) {
    if (indexes.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(title, style: theme.textTheme.titleSmall),
        ),
        for (final index in indexes) _poolRow(index),
      ],
    );
  }

  Widget _poolRow(int index) {
    final link = _imported[index];
    final label = labelForShareLink(link);
    final selected = _selectedId == '$index';
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: PoolServerMark(label: label),
      title: Text(label.title),
      subtitle: Text(label.subtitle.isEmpty ? link.endpoint : label.subtitle),
      selected: selected,
      selectedTileColor: theme.colorScheme.primaryContainer,
      onTap: () => _chooseImported(index),
    );
  }

  /// Fixed square. A progress indicator in a stretched row otherwise grows into
  /// a wide ellipse and the refresh cell no longer matches the icon buttons.
  Widget _catalogIconButton({
    Key? key,
    required String tooltip,
    required VoidCallback? onTap,
    required Widget icon,
  }) {
    return Tooltip(
      key: key,
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Center(child: icon),
      ),
    );
  }

  Widget _catalogCard(ThemeData theme, AppL10n l, ShareCatalog catalog) {
    final title = catalog.title.trim().isEmpty ? l.freeServers : catalog.title;
    final lines = _catalogLineIndexes(catalog);
    final hasLines = lines.premium.isNotEmpty || lines.general.isNotEmpty;
    final notice = profileNotice(
      announce: catalog.announce,
      supportUrl: catalog.supportUrl,
    );
    final dark = theme.brightness == Brightness.dark;
    final showRefresh = catalog.url != null && catalog.url!.isNotEmpty;
    final planeUrl = notice.planeUrl?.trim() ?? '';
    final parkPlane = planeUrl.isNotEmpty;
    final onFill = dark ? AppBrand.inkDark : AppBrand.inkLight;
    final band = dark ? AppBrand.noticeBandDark : AppBrand.noticeBand;
    final noticeBody = notice.text?.trim() ?? '';
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBrand.radiusCard),
        side: BorderSide(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CatalogProfileChrome(
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            share: _catalogIconButton(
              tooltip: l.freeSharePool,
              onTap: () => _shareCatalog(catalog),
              icon: const AppIcon(AppIcons.share, size: 20),
            ),
            refresh: showRefresh
                ? _catalogIconButton(
                    tooltip: l.freeRefresh,
                    onTap: _refreshing.contains(catalog.id)
                        ? null
                        : () => _refreshCatalog(catalog),
                    icon: _refreshing.contains(catalog.id)
                        ? SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: onFill,
                              constraints: const BoxConstraints.tightFor(
                                width: 20,
                                height: 20,
                              ),
                            ),
                          )
                        : AppIcon(AppIcons.refresh, size: 20, color: onFill),
                  )
                : null,
            plane: parkPlane
                ? _catalogIconButton(
                    key: kSubscriptionNoticePlaneKey,
                    tooltip: subscriptionPlaneIsTelegram(planeUrl)
                        ? 'Telegram'
                        : 'Link',
                    onTap: () => openSubscriptionPlane(planeUrl),
                    icon: AppIcon(
                      subscriptionPlaneIsTelegram(planeUrl)
                          ? AppIcons.paperPlane
                          : AppIcons.link,
                      size: 22,
                      color: catalogPlaneInk(dark: dark),
                    ),
                  )
                : null,
            trash: _catalogIconButton(
              tooltip: l.freeDelete,
              onTap: () => _deleteProfile(catalog.id),
              icon: const AppIcon(
                AppIcons.trash,
                size: 20,
                color: AppBrand.surfaceElevatedLight,
              ),
            ),
            band: band,
            trashFill: catalogTrashFill(
              theme.colorScheme.surfaceContainerHighest,
              dark: dark,
            ),
            seamColor: theme.colorScheme.outline,
            notice: noticeBody.isEmpty
                ? null
                : SubscriptionNoticeView(
                    text: notice.text,
                    planeUrl: notice.planeUrl,
                    frame: false,
                    showPlane: false,
                  ),
          ),
          if (hasLines) ...[
            Divider(
              height: 1,
              thickness: 1,
              color: theme.colorScheme.outline,
            ),
            _poolSection(theme, l.freePoolMarked, lines.premium),
            _poolSection(theme, l.freePoolGeneral, lines.general),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildImported(ThemeData theme) {
    final l = AppL10n.of(context);
    final filtered = <int>[];
    final q = _query.trim().toLowerCase();
    for (var i = 0; i < _imported.length; i++) {
      final link = _imported[i];
      final hay = '${link.name} ${link.endpoint} ${link.scheme}'.toLowerCase();
      if (q.isEmpty || hay.contains(q)) filtered.add(i);
    }
    final connected = ref.watch(vpnProvider) is VpnConnected;
    final grouped = _catalogs.isNotEmpty;
    if (grouped) {
      return Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(44, 8, 16, 0),
              children: [
                for (var i = 0; i < _catalogs.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _catalogCard(theme, l, _catalogs[i]),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
            child: FreeClientActionBar(
              onPaste: () {
                UiLog.action('locations', 'paste');
                context.push('/import?clipboard=1');
              },
              onScan: () {
                UiLog.action('locations', 'scan');
                openFreeClientCapture(context);
              },
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(44, 8, 16, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: l.freeSearch,
              prefixIcon: const AppIcon(AppIcons.search),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppBrand.radiusCard),
                borderSide: BorderSide(color: theme.colorScheme.outline),
              ),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: FreeClientEmptyState())
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(44, 0, 16, 0),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final index = filtered[i];
                    final link = _imported[index];
                    final selected = _selectedId == '$index';
                    final schemeBlocked =
                        !canDialScheme(link.scheme, ios: false);
                    return ImportedProfileCard(
                      name: link.name,
                      scheme: link.scheme,
                      endpoint: link.endpoint,
                      selected: selected,
                      connected: selected && connected,
                      dialable: !schemeBlocked,
                      onDelete: () => _removeImported(index),
                      onTap: () async {
                        if (schemeBlocked) {
                          UiLog.action(
                            'locations',
                            'pick',
                            result: 'blocked',
                            reason: 'scheme',
                            extra: {'scheme': link.scheme},
                          );
                          return;
                        }
                        await _chooseImported(index, scheme: link.scheme);
                      },
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
          child: FreeClientActionBar(
            onPaste: () {
              UiLog.action('locations', 'paste');
              context.push('/import?clipboard=1');
            },
            onScan: () {
              UiLog.action('locations', 'scan');
              openFreeClientCapture(context);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBody(AppL10n l, ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return _buildImported(theme);
  }
}

/// Shared region row (Locations tab / legacy sheet).
class RegionTile extends StatelessWidget {
  const RegionTile({
    super.key,
    required this.selected,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.trailingBadge,
    required this.showBadge,
    this.enabled = true,
    this.signalGood = true,
    this.onTap,
  });

  final bool selected;
  final bool enabled;
  final Widget leading;
  final String title;
  final String subtitle;
  final String trailingBadge;
  final bool showBadge;
  final bool signalGood;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = selected
        ? Border.all(color: AppBrand.primary, width: 1.5)
        : Border.all(color: theme.colorScheme.outlineVariant);

    return Material(
      color: enabled
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(AppBrand.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppBrand.radiusCard),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppBrand.radiusCard),
            border: border,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: enabled
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.outline,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (showBadge) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppBrand.inkWithOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    trailingBadge,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              _SignalBars(good: signalGood && enabled),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.good});

  final bool good;

  @override
  Widget build(BuildContext context) {
    final color = good ? AppBrand.success : AppBrand.warning;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final h = 6.0 + i * 3;
        return Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Container(
            width: 4,
            height: h,
            decoration: BoxDecoration(
              color: i < (good ? 4 : 2) ? color : color.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        );
      }),
    );
  }
}

class _ServerCountChip extends StatelessWidget {
  const _ServerCountChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final wide = count > 9;
    return Container(
      width: wide ? null : 28,
      height: 28,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      padding: EdgeInsets.symmetric(horizontal: wide ? 8 : 0),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color:
            dark ? AppBrand.surfaceVariantDark : AppBrand.surfaceElevatedLight,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Text(
        '$count',
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: dark ? AppBrand.inkDark : AppBrand.inkLight,
        ),
      ),
    );
  }
}
