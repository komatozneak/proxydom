import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/busy/busy_overlay.dart';
import '../../../core/diagnostics/product_log.dart';
import '../../../core/diagnostics/ui_log.dart';
import '../../../core/ios_store_gates.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/location_flag_icon.dart';
import '../../../core/widgets/teremok_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import 'vpn_platform_copy.dart';
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
import '../data/node_auto_selector.dart';
import '../data/node_display.dart';
import '../data/vpn_controller.dart';
import '../data/vpn_node.dart';

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

  List<VpnNode>? _nodes;
  List<ParsedShareLink> _imported = const [];
  List<ShareCatalog> _catalogs = const [];
  String? _selectedId;
  Object? _error;
  bool _loading = true;
  bool _lockdownHint = false;
  bool _fromCache = false;
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
    final canPop = GoRouter.maybeOf(context)?.canPop() ?? false;
    final busy = ref.watch(busyOverlayProvider).isBusy;
    ref.watch(vpnProvider);
    if (freeKeyClient) {
      ref.listen(importedProfilesProvider, (previous, next) {
        final links = next.valueOrNull;
        if (links == null) return;
        unawaited(_applyImported(links));
      });
    }

    return Scaffold(
      backgroundColor:
          freeKeyClient ? Colors.transparent : theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: freeKeyClient ? Colors.transparent : null,
        surfaceTintColor: freeKeyClient ? Colors.transparent : null,
        titleSpacing: freeKeyClient ? 44 : null,
        title: freeKeyClient
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.freeServers),
                  const SizedBox(width: 16),
                  _ServerCountChip(count: _imported.length),
                ],
              )
            : Text(l.regionTitle),
        leading: !freeKeyClient && canPop
            ? IconButton(
                icon: const AppIcon(AppIcons.back),
                onPressed: busy ? null : () => context.pop(),
              )
            : null,
        automaticallyImplyLeading: false,
      ),
      body: _buildBody(l, theme),
    );
  }

  bool _isTransientNetwork(Object e) {
    if (e is DioException) {
      return e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout;
    }
    final raw = e.toString().toLowerCase();
    return raw.contains('connection reset') ||
        raw.contains('connection abort') ||
        raw.contains('failed host lookup') ||
        raw.contains('network is unreachable') ||
        raw.contains('software caused connection abort');
  }

  Future<void> _applyImported(List<ParsedShareLink> links) async {
    final index = await Hy2ImportStore.instance.selectedIndex();
    final catalogs = await Hy2ImportStore.instance.catalogs();
    if (!mounted) return;
    setState(() {
      _imported = links;
      _catalogs = catalogs;
      _nodes = const [];
      _selectedId = links.isEmpty ? null : '$index';
      _loading = false;
      _error = null;
      _fromCache = false;
    });
  }

  Future<void> _load() async {
    if (freeKeyClient) {
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
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _lockdownHint = false;
      _fromCache = false;
    });

    final nodesRepo = ref.read(vpnNodesRepositoryProvider);
    var selectedId = await nodesRepo.getSelectedNodeId();
    selectedId ??= kRegionAutoId;

    // Stale-while-revalidate: never block the UI on a live /vpn/nodes hang
    // (Dio receiveTimeout 60s × retries ≈ 2 min — Pixel repro 2026-08-07).
    final cached = await nodesRepo.loadCachedNodes();
    if (cached != null && cached.isNotEmpty) {
      if (selectedId != kRegionAutoId &&
          !cached.any((n) => n.id == selectedId)) {
        selectedId = kRegionAutoId;
      }
      if (!mounted) return;
      setState(() {
        _nodes = cached;
        _selectedId = selectedId;
        _loading = false;
        _fromCache = true;
      });
    }

    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final result = await nodesRepo.listNodesDetailed(
          allowCacheFallback: true,
        );
        var nextSelected = await nodesRepo.getSelectedNodeId();
        nextSelected ??= kRegionAutoId;
        if (nextSelected != kRegionAutoId &&
            !result.nodes.any((n) => n.id == nextSelected)) {
          nextSelected = kRegionAutoId;
        }
        if (!mounted) return;
        setState(() {
          _nodes = result.nodes;
          _selectedId = nextSelected;
          _loading = false;
          _fromCache = result.fromCache;
          _error = null;
        });
        for (final n in result.nodes) {
          if (placeForKnownHost(n.host) != null) continue;
          unawaited(
            warmGeoCache(n.host).then((_) {
              if (mounted) setState(() {});
            }),
          );
        }
        return;
      } catch (e) {
        lastError = e;
        if (attempt < 2 && _isTransientNetwork(e)) {
          await Future<void>.delayed(
              Duration(milliseconds: 400 * (attempt + 1)));
          continue;
        }
        break;
      }
    }

    // Cache already painted the list — keep it; only hard-fail if nothing shown.
    if (_nodes != null && _nodes!.isNotEmpty) {
      return;
    }

    final e = lastError ?? StateError('unknown');
    final raw = e.toString();
    final looksLikeAbort = _isTransientNetwork(e) ||
        raw.contains('connection abort') ||
        raw.contains('Software caused connection abort') ||
        raw.contains('HttpException') ||
        raw.contains('Connection reset');
    final lockdown = looksLikeAbort
        ? await VpnController.instance.isLockdownEnabled()
        : false;
    if (!mounted) return;
    setState(() {
      _error = e;
      _lockdownHint = looksLikeAbort || lockdown;
      _loading = false;
    });
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

  Future<void> _pick(String id) async {
    if (ref.read(busyOverlayProvider).isBusy) {
      UiLog.action('locations', 'pick', result: 'ignored', reason: 'busy');
      return;
    }
    UiLog.action('locations', 'pick', extra: {'id': id});
    if (!mounted) return;
    setState(() => _selectedId = id);
    await _leaveForHouse('server_pick');
  }

  Future<void> _onLockedPremiumTap() async {
    UiLog.action('locations', 'premium', result: 'import');
    await context.push('/import');
  }

  /// Free/online egress + always keep Premium/locked rows in the pool (gray).
  bool _inProductPool(VpnNode n) {
    if (n.requiresPremium || n.locked || n.isYoutube) return true;
    return n.isConnected || n.isDefault;
  }

  bool _isTileLocked(VpnNode n, {required bool userPremium}) {
    final purpose = (n.purpose ?? '').toLowerCase();
    if (purpose == 'coming_soon' || n.host == '0.0.0.0') return true;
    if (n.requiresPremium && !userPremium) return true;
    if (!userPremium && n.locked) return true;
    return false;
  }

  String _friendlyError(AppL10n l) {
    if (_lockdownHint) return l.regionLoadErrorAbort;
    return l.networkErrorFriendly;
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
    final text = catalog.lines.join('\n');
    if (text.isEmpty || !mounted) return;
    final box = context.findRenderObject();
    final origin = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    await Share.share(
      text,
      subject: catalog.title,
      sharePositionOrigin: origin,
    );
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
      showTeremokSnackBar(context, l.freeRefreshDone(outcome.count));
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
      showTeremokSnackBar(context, l.freeRefreshFail);
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
    return ListTile(
      leading: PoolServerMark(label: label),
      title: Text(label.title),
      subtitle: Text(label.subtitle.isEmpty ? link.endpoint : label.subtitle),
      selected: selected,
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
      announceFrame: catalog.announceFrame,
      documentUrl: catalog.url,
      trafficMeta: catalog.trafficMeta,
    );
    final dark = theme.brightness == Brightness.dark;
    final showRefresh = catalog.url != null && catalog.url!.isNotEmpty;
    final planeUrl = notice.planeUrl?.trim() ?? '';
    final parkPlane = showRefresh && notice.visible && planeUrl.isNotEmpty;
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
              catalog.lines.length > 1 ? '$title · ${catalog.lines.length}' : title,
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
                      color: onFill,
                    ),
                  )
                : null,
            trash: _catalogIconButton(
              tooltip: l.freeDelete,
              onTap: () => _deleteProfile(catalog.id),
              icon: AppIcon(AppIcons.trash, size: 20, color: onFill),
            ),
            band: band,
            trashFill: catalogTrashFill(
              theme.colorScheme.surfaceContainerHighest,
              dark: dark,
            ),
            seamColor: theme.colorScheme.outline,
            notice: noticeBody.isEmpty
                ? null
                : Padding(
                    padding: EdgeInsets.fromLTRB(12, 0, parkPlane ? 8 : 4, 12),
                    child: SubscriptionNoticeView(
                      text: notice.text,
                      planeUrl: notice.planeUrl,
                      frame: notice.frame,
                      showPlane: !parkPlane,
                    ),
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
                    final schemeBlocked = !canDialScheme(link.scheme, ios: false);
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
    if (freeKeyClient) {
      return _buildImported(theme);
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppIcon(AppIcons.warning, size: 36),
              const SizedBox(height: 12),
              Text(
                _friendlyError(l),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _load,
                child: Text(l.homeRetry),
              ),
            ],
          ),
        ),
      );
    }

    final nodes = _nodes ?? const <VpnNode>[];
    if (nodes.isEmpty) {
      return Center(child: Text(l.regionEmpty));
    }

    const userPremium = false;

    // Free online/default + Premium/locked always visible (gray for Free).
    final pool = nodes.where(_inProductPool).toList();
    final sections = groupNodesByLocationSection(pool);
    final freeOnline =
        pool.where((n) => !n.requiresPremium && (n.isConnected || n.isDefault));

    var selectedId = _selectedId ?? kRegionAutoId;
    if (selectedId != kRegionAutoId) {
      VpnNode? selectedNode;
      for (final n in pool) {
        if (n.id == selectedId) {
          selectedNode = n;
          break;
        }
      }
      if (selectedNode == null ||
          _isTileLocked(selectedNode, userPremium: userPremium)) {
        selectedId = kRegionAutoId;
      }
    }

    final locale = Localizations.localeOf(context).languageCode;
    final autoSelected = selectedId == kRegionAutoId;
    final poolFlags = uniqueAutoPoolFlags(
      autoPoolFor(nodes, isPremium: userPremium),
    );
    final autoFlag = autoSelectionDisplayFlag(
      catalog: nodes,
      winnerId:
          autoSelected ? ref.read(vpnProvider.notifier).autoWinnerId : null,
      poolFlags: poolFlags,
    );

    Widget sectionHeader(String title) => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );

    List<Widget> sectionTiles(List<VpnNode> list) {
      final out = <Widget>[];
      for (var i = 0; i < list.length; i++) {
        final node = list[i];
        final place = placeForNode(node, index: i);
        final locked = _isTileLocked(node, userPremium: userPremium);
        final selected = !locked && selectedId == node.id;
        final placeSubtitle = place.displaySubtitle(locale).trim();
        // Locked Premium tiles still show the real marketing blurb — the
        // lock is communicated by the badge + gray styling, not the subtitle.
        final subtitle = placeSubtitle.isNotEmpty
            ? placeSubtitle
            : displaySubtitleForNode(node, l);
        out.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RegionTile(
              selected: selected,
              enabled: !locked,
              leading: LocationFlagIcon(flag: place.flag, size: 40),
              title: place.displayTitle(locale),
              subtitle: subtitle,
              trailingBadge:
                  selected ? l.regionSelected : l.locationsPremiumLocked,
              showBadge: selected || locked,
              signalGood: !locked,
              onTap: locked ? _onLockedPremiumTap : () => _pick(node.id),
            ),
          ),
        );
      }
      return out;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text(
          l.regionSubtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (_fromCache) ...[
          const SizedBox(height: 8),
          Text(
            l.regionCachedHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 16),
        RegionTile(
          selected: autoSelected,
          leading: LocationFlagIcon(
            key: kLocationsAutoFlagKey,
            flag: autoFlag,
            size: 40,
          ),
          title: l.regionAutoTitle,
          subtitle: l.regionAutoSubtitle,
          trailingBadge: l.regionSelected,
          showBadge: autoSelected,
          onTap: () => _pick(kRegionAutoId),
        ),
        if (sections[LocationSection.premium]!.isNotEmpty) ...[
          sectionHeader(regionSectionYoutubeForPlatform(l)),
          ...sectionTiles(sections[LocationSection.premium]!),
        ],
        if (sections[LocationSection.general]!.isNotEmpty) ...[
          sectionHeader(l.regionSectionGeneral),
          ...sectionTiles(sections[LocationSection.general]!),
        ],
        if (sections[LocationSection.other]!.isNotEmpty) ...[
          sectionHeader(l.regionSectionServers),
          ...sectionTiles(sections[LocationSection.other]!),
        ],
        if (freeOnline.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l.regionNoneOnline,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color:
            dark ? AppBrand.surfaceVariantDark : AppBrand.surfaceElevatedLight,
        borderRadius: BorderRadius.circular(AppBrand.radiusPill),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Text(
        '$count',
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: dark ? AppBrand.inkDark : AppBrand.inkLight,
        ),
      ),
    );
  }
}
