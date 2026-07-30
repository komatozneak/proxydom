import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../home/application/vpn_provider.dart';
import '../../home/application/vpn_status.dart';
import '../data/split_tunnel_prefs.dart';

/// Phase 1 Sites-only: bundled RU toggle + custom domains + reconnect-to-apply.
class SplitTunnelSitesScreen extends ConsumerStatefulWidget {
  const SplitTunnelSitesScreen({super.key});

  @override
  ConsumerState<SplitTunnelSitesScreen> createState() =>
      _SplitTunnelSitesScreenState();
}

class _SplitTunnelSitesScreenState
    extends ConsumerState<SplitTunnelSitesScreen> {
  bool _loading = true;
  bool _bundledRu = true;
  bool _pending = false;
  bool _reconnecting = false;
  List<SplitTunnelSite> _sites = const [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final bundled = await SplitTunnelPrefs.isBundledRuEnabled();
    final sites = await SplitTunnelPrefs.loadSites();
    final pending = await SplitTunnelPrefs.hasPendingChanges();
    if (!mounted) return;
    setState(() {
      _bundledRu = bundled;
      _sites = sites;
      _pending = pending;
      _loading = false;
    });
  }

  Future<void> _afterMutation() async {
    final vpn = ref.read(vpnProvider);
    final pending = vpn is VpnConnected || vpn is VpnConnecting
        ? await SplitTunnelPrefs.hasPendingChanges()
        : false;
    final sites = await SplitTunnelPrefs.loadSites();
    final bundled = await SplitTunnelPrefs.isBundledRuEnabled();
    if (!mounted) return;
    setState(() {
      _sites = sites;
      _bundledRu = bundled;
      _pending = pending;
    });
  }

  List<SplitTunnelSite> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _sites;
    return _sites
        .where(
          (s) =>
              s.domain.contains(q) ||
              s.label.toLowerCase().contains(q),
        )
        .toList();
  }

  Future<void> _setBundled(bool value) async {
    await SplitTunnelPrefs.setBundledRuEnabled(value);
    await _afterMutation();
  }

  Future<void> _toggleSite(SplitTunnelSite site, bool enabled) async {
    await SplitTunnelPrefs.updateSite(site.copyWith(enabled: enabled));
    await _afterMutation();
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
    if (ok != true || !mounted) return;
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

  Future<void> _showBundledInfo() async {
    final l = AppL10n.of(context);
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: Text(l.splitTunnelBundledInfoTitle),
        content: SingleChildScrollView(
          child: Text(l.splitTunnelBundledInfoBody),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.splitTunnelBundledInfoClose),
          ),
        ],
      ),
    );
  }

  Future<void> _reconnect() async {
    if (_reconnecting) return;
    setState(() => _reconnecting = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l = AppL10n.of(context);
    final ok = await ref.read(vpnProvider.notifier).reconnectToApplyRouting();
    if (!mounted) return;
    setState(() => _reconnecting = false);
    await _reload();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(ok ? l.splitTunnelApplied : l.splitTunnelApplyFailed),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final vpn = ref.watch(vpnProvider);
    final showPending = _pending &&
        (vpn is VpnConnected || vpn is VpnConnecting || _reconnecting);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.settingsSplitTunnel),
        leading: IconButton(
          icon: const AppIcon(AppIcons.back, size: 22),
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
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: l.splitTunnelSearchHint,
                    prefixIcon: const AppIcon(AppIcons.search, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.splitTunnelBundledSection,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _BundledHelpButton(onPressed: _showBundledInfo),
                  ],
                ),
                Text(
                  l.splitTunnelBundledLead,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Material(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 8, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                l.splitTunnelBundledRuTitle,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Switch.adaptive(
                              value: _bundledRu,
                              onChanged: _setBundled,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l.splitTunnelBundledRuSubtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.splitTunnelCustomSection,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      l.splitTunnelCustomCount(_sites.length),
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        Text(
                          l.splitTunnelEmptyTitle,
                          style: theme.textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l.splitTunnelEmptyBody,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else
                  Material(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < _filtered.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              indent: 16,
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.5),
                            ),
                          _SiteTile(
                            site: _filtered[i],
                            onToggle: (v) => _toggleSite(_filtered[i], v),
                            onDelete: () => _deleteSite(_filtered[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _showAddSite,
                  icon: const AppIcon(AppIcons.plus, size: 18),
                  label: Text(l.splitTunnelAddSite),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                if (showPending) ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppBrand.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppBrand.accent.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l.splitTunnelPendingTitle,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l.splitTunnelPendingBody,
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
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
                ],
              ],
            ),
    );
  }
}

/// Noticeable but calm "?" affordance for the bundled-list help dialog.
class _BundledHelpButton extends StatelessWidget {
  const _BundledHelpButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppL10n.of(context);
    final color = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85);

    return IconButton(
      tooltip: l.splitTunnelBundledInfoTitle,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: color.withValues(alpha: 0.55),
            width: 1.4,
          ),
        ),
        child: AppIcon(AppIcons.question, size: 14, color: color),
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
  final _nameCtrl = TextEditingController();
  final _domainCtrl = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _domainCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(AppL10n l) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await SplitTunnelPrefs.addSite(
      domain: _domainCtrl.text,
      label: _nameCtrl.text,
    );
    if (!mounted) return;
    if (result is DomainNormalizeOk) {
      Navigator.pop(context, true);
      return;
    }
    final kind = (result as DomainNormalizeErr).kind;
    setState(() {
      _saving = false;
      _error = switch (kind) {
        DomainNormalizeErrorKind.duplicate => l.splitTunnelDuplicateDomain,
        DomainNormalizeErrorKind.nonAscii => l.splitTunnelNonAsciiUnsupported,
        _ => l.splitTunnelInvalidDomain,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.splitTunnelAddSite,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: l.splitTunnelSiteNameOptional,
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _domainCtrl,
            decoration: InputDecoration(
              labelText: l.splitTunnelDomainLabel,
              hintText: l.splitTunnelDomainHint,
              helperText: _error == null ? l.splitTunnelDomainLatinHelper : null,
              errorText: _error,
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : () => _submit(l),
            child: Text(l.splitTunnelSave),
          ),
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: Text(l.splitTunnelCancel),
          ),
        ],
      ),
    );
  }
}

class _SiteTile extends StatelessWidget {
  const _SiteTile({
    required this.site,
    required this.onToggle,
    required this.onDelete,
  });

  final SplitTunnelSite site;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final title = site.label.isNotEmpty ? site.label : site.domain;
    final subtitle = site.label.isNotEmpty ? site.domain : null;

    return ListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: l.splitTunnelDelete,
            onPressed: onDelete,
            icon: const AppIcon(AppIcons.trash, size: 18),
          ),
          Switch.adaptive(
            value: site.enabled,
            onChanged: onToggle,
          ),
        ],
      ),
    );
  }
}
