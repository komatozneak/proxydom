import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/diagnostics/product_log.dart';
import '../../../core/diagnostics/ui_log.dart';
import '../../../core/ios_store_gates.dart';
import '../../../core/theme.dart';
import '../../../core/toasts/proxy_dom_toast.dart';
import '../../../core/widgets/app_icon.dart';

import '../../../core/widgets/terminal_type.dart';
import '../../../l10n/app_localizations.dart';
import '../../home/application/vpn_provider.dart';
import '../../home/application/vpn_status.dart';
import '../application/imported_profiles_provider.dart';
import '../data/hy2_import_store.dart';
import '../data/dial_set.dart';
import '../data/subscription_label.dart';
import '../data/subscription_notice.dart';
import 'free_client_chrome.dart';
import 'server_instrument.dart';
import 'server_instrument_parts.dart';
import 'subscription_notice_view.dart';
import '../data/share_link_parser.dart';

/// Key on the Locations Auto row flag (Home/Locations icon parity tests).
const kLocationsAutoFlagKey = ValueKey<String>('locations-auto-flag');

/// How wide the page reads on a window.
///
/// The same measure the home tab hangs its column in. It hangs off the reading
/// edge rather than centring: the heading above is on the gutter, and a card
/// that starts 200px to the right of its own title is the crooked page this
/// tab is meant to stop having.
const double _pageMeasure = 1080;

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
        // The heading shares the gutter with every other tab's page. It used to
        // reserve 44px for a leading button that no longer exists
        // (automaticallyImplyLeading is false below), which left this tab's
        // title sitting further right than Settings' or Home's.
        titleSpacing:
            windowsDesktop ? AppBrand.pageGutterWide : AppBrand.pageGutter,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(l.freeServers),
            const SizedBox(width: 12),
            // The count is a reading, not a badge. It was a 28px pill with its
            // own outline and a Material label inside, which weighed more than
            // the heading it sat next to and made the page open with furniture.
            _ServerCount(
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

  /// The saved documents a reload could actually reach.
  List<ShareCatalog> get _reloadableDocuments => [
        for (final catalog in _catalogs)
          if (catalog.url != null && catalog.url!.isNotEmpty) catalog,
      ];

  /// Rereads every saved document from the key at the foot of this page.
  Future<void> _refreshEveryDocument() async {
    final status = ref.read(vpnProvider);
    final live = status is VpnConnected || status is VpnConnecting;
    await refreshRemoteDocuments(
      context,
      scope: 'locations',
      bottomInset: kActionBarBottomInset,
      onSelectionLeft: () async {
        if (!live) return;
        await ref.read(vpnProvider.notifier).disconnect(reason: 'refresh');
      },
    );
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
      showProxyDomToast(l.freeShareFail, tone: ToastTone.failure);
      return;
    }
    if (!mounted) return;
    UiLog.action('locations', 'share', result: 'copied');
    showProxyDomToast(l.freeShareCopied, tone: ToastTone.success);
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
      showProxyDomToast(
        l.freeRefreshDone(outcome.count),
        tone: ToastTone.success,
      );
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
      showProxyDomToast(l.freeRefreshFail, tone: ToastTone.failure);
    } finally {
      if (mounted) setState(() => _refreshing.remove(catalog.id));
    }
  }

  NodeLine _nodeLine(AppL10n l, int index) {
    final link = _imported[index];
    final dialable = canDialLink(link);
    return NodeLine(
      label: labelForShareLink(link),
      protocol: protocolMark(link.scheme),
      dialable: dialable,
      endpoint: dialable ? link.endpoint : l.freeSchemeParked,
      selected: _selectedId == '$index',
      onTap: () {
        if (!dialable) {
          UiLog.action(
            'locations',
            'pick',
            result: 'blocked',
            reason: 'scheme',
            extra: {'scheme': link.scheme},
          );
          return;
        }
        _chooseImported(index, scheme: link.scheme);
      },
    );
  }

  Widget _catalogCard(ThemeData theme, AppL10n l, ShareCatalog catalog) {
    final title = catalog.title.trim().isEmpty ? l.freeServers : catalog.title;
    // Document order. The premium/general split moved YouTube, gaming and
    // India above the rest, so a line appeared to jump when a document came
    // back in a different order. The store already keeps the document order.
    final query = _query.trim().toLowerCase();
    final nodeIndexes = <int>[];
    for (final raw in catalog.lines) {
      final index = _imported.indexWhere((link) => link.raw == raw);
      if (index < 0) continue;
      if (query.isNotEmpty) {
        final link = _imported[index];
        final label = labelForShareLink(link);
        final hay =
            '${label.title} ${link.endpoint} ${link.scheme}'.toLowerCase();
        if (!hay.contains(query)) continue;
      }
      nodeIndexes.add(index);
    }
    // A profile with no matching lines is not drawn; the page says once that
    // nothing was found instead of repeating an empty card per document.
    if (query.isNotEmpty && nodeIndexes.isEmpty) {
      return const SizedBox.shrink();
    }
    final notice = profileNotice(
      announce: catalog.announce,
      supportUrl: catalog.supportUrl,
    );
    final planeUrl = notice.planeUrl?.trim() ?? '';
    final noticeBody = notice.text?.trim() ?? '';

    final selectedLabel = _selectedLabel();
    final russian = Localizations.localeOf(context).languageCode == 'ru';
    final parsed = inspectShareLines(catalog.lines);
    final unsupportedNote = parsed.skipped.isEmpty
        ? null
        : formatUnsupportedImport(
            countLine: l.freeImportCount(
              parsed.links.length,
              parsed.skipped.length,
            ),
            skipped: parsed.skipped,
          );

    // The gap between cards belongs to the list, not to the card: one number
    // for the distance between two profiles on this page.
    return ProfileInstrument(
      title: title,
      description: noticeBody,
      facts: profileFacts(
        trafficMeta: catalog.trafficMeta,
        russian: russian,
        // The seven-character key prefix is gone: it was crypto, not a fact
        // a person can use. Full key stays behind «Поделиться».
        keyHandle: '',
      ),
      updated: profileUpdatedLabel(
        lastUpdated: catalog.lastUpdated,
        russian: russian,
      ),
      selected: _catalogIsSelected(catalog),
      // The plate itself is not the pick: the line you tap is the line you get.
      // This callback was required and never called, which read as «this card
      // chooses something» to everyone but the person holding the mouse.
      onNodeTap: (_) {},
      nodes: [
        for (final index in nodeIndexes) _nodeLine(l, index),
      ],
      selectedNodeTitle: selectedLabel,
      telegramLabel: subscriptionPlaneIsTelegram(planeUrl)
          ? l.freeTelegram
          : l.freeSharePool,
      onTelegram:
          planeUrl.isEmpty ? null : () => openSubscriptionPlane(planeUrl),
      onRefresh: catalog.url == null || catalog.url!.isEmpty
          ? null
          : () => _refreshCatalog(catalog),
      refreshing: _refreshing.contains(catalog.id),
      onShare:
          catalog.subscriptionKey == null ? null : () => _shareCatalog(catalog),
      onDelete: () => _deleteProfile(catalog.id),
      showTelegraph: planeUrl.isNotEmpty,
      unsupportedNote: unsupportedNote,
    );
  }

  String _selectedLabel() {
    final index = int.tryParse(_selectedId ?? '');
    if (index == null || index < 0 || index >= _imported.length) return '';
    return labelForShareLink(_imported[index]).title;
  }

  bool _catalogIsSelected(ShareCatalog catalog) {
    for (final raw in catalog.lines) {
      final index = _imported.indexWhere((link) => link.raw == raw);
      if (index >= 0 && _selectedId == '$index') return true;
    }
    return false;
  }

  /// The page: one scroll of cards, one key bar under it.
  ///
  /// Both halves sit in the same measure and on the same gutter as the heading
  /// above. The list used to run 44/16 while the heading ran on the shared
  /// page gutter, so every card on this tab began 20px to the right of the
  /// word that names it, and the key bar below sat on a third number again.
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

    final query = _query.trim().toLowerCase();
    final hasMatch = query.isEmpty ||
        _imported.any((link) {
          final label = labelForShareLink(link);
          final hay =
              '${label.title} ${link.endpoint} ${link.scheme}'.toLowerCase();
          return hay.contains(query);
        });
    final body = _catalogs.isNotEmpty
        ? Column(
            children: [
              // A short profile does not need a search line; eight is where
              // scrolling starts and a query saves time.
              if (_imported.length > 8)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 12),
                  child: _SearchField(
                    hint: l.freeSearch,
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
              Expanded(
                child: !hasMatch
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            l.freeSearchEmpty,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.only(top: 2),
                        children: [
                          for (var i = 0; i < _catalogs.length; i++) ...[
                            if (i > 0) const SizedBox(height: 12),
                            _catalogCard(theme, l, _catalogs[i]),
                          ],
                        ],
                      ),
              ),
            ],
          )
        : Column(
            children: [
              // Nothing to search through yet: a search line over the empty
              // state asks a question the page has not earned yet.
              if (_imported.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 12),
                  child: _SearchField(
                    hint: l.freeSearch,
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: FreeClientEmptyState())
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final index = filtered[i];
                          final link = _imported[index];
                          final selected = _selectedId == '$index';
                          final schemeBlocked = !canDialLink(link);
                          return ImportedProfileCard(
                            name: link.name,
                            scheme: link.scheme,
                            endpoint: link.endpoint,
                            // The same label the pool lines are drawn from, so
                            // a pasted key and a node out of a list look like
                            // the same kind of thing wherever they are shown.
                            label: labelForShareLink(link),
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
            ],
          );

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: _gutter),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _pageMeasure),
                child: body,
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(_gutter, 10, _gutter, 12),
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _pageMeasure),
              // Add is the primary; reload is the one secondary tool this tab
              // owns. QR lives in the import field, so it is not a third peer.
              child: FreeClientActionBar(
                onPaste: () {
                  UiLog.action('locations', 'add');
                  context.push('/import');
                },
                onScan: () {},
                showScan: false,
                onRefresh: _reloadableDocuments.isEmpty
                    ? null
                    : () => _refreshEveryDocument(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The line every page in the app starts on.
  double get _gutter =>
      windowsDesktop ? AppBrand.pageGutterWide : AppBrand.pageGutter;

  Widget _buildBody(AppL10n l, ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return _buildImported(theme);
  }
}

/// The search line, in the app's own voice.
///
/// It was a filled Material field with an outline on all four sides: the last
/// piece of default Material on this tab, and it drew a box around the one
/// thing on the page that is not a server. A wash of ink and a hairline says
/// the same thing without it.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.hint, required this.onChanged});

  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final mute = dark ? AppBrand.inkMutedDark : AppBrand.inkMutedLight;
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(AppBrand.radiusPill),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.6),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          AppIcon(AppIcons.search, size: 17, color: mute),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              onChanged: onChanged,
              cursorColor: AppBrand.mascotGold,
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  color: mute.withValues(alpha: 0.7),
                  fontSize: 13.5,
                ),
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
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

/// How many servers this tab holds, as a reading beside its name.
///
/// It was a 28px pill with a fill, an outline and a Material label inside — a
/// badge in the weight of a heading, and the first thing the eye landed on
/// before the word that actually says what the page is. The count is a number
/// on this app's instruments, not a badge: mono, in the house gold, inside a
/// hairline circle that carries the same tracking as the reading under it.
class _ServerCount extends StatelessWidget {
  const _ServerCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final gold = dark ? AppBrand.mascotGoldLit : AppBrand.mascotGoldDeep;
    final wide = count > 9;
    return Container(
      width: wide ? null : 22,
      height: 22,
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: EdgeInsets.symmetric(horizontal: wide ? 7 : 0),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppBrand.mascotGold.withValues(alpha: 0.45)),
      ),
      child: Text(
        '$count',
        style: terminalText(
          context,
          size: 11.5,
          color: gold,
          weight: 700,
          spacing: 0.6,
        ),
      ),
    );
  }
}
