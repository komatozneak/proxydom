import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../home/application/vpn_provider.dart';
import '../../home/application/vpn_status.dart';
import '../../settings/data/split_tunnel_prefs.dart';
import '../../settings/data/vpn_route_mode.dart';
import '../../shell/presentation/main_shell.dart';

/// Bottom-nav «Режимы»: Умный / Обычный / По сайтам (+ site pool only in sites).
class ModesScreen extends ConsumerStatefulWidget {
  const ModesScreen({super.key});

  @override
  ConsumerState<ModesScreen> createState() => _ModesScreenState();
}

class _ModesScreenState extends ConsumerState<ModesScreen> {
  VpnRouteMode _mode = VpnRouteMode.smart;
  List<SplitTunnelSite> _sites = const [];
  bool _loading = true;
  bool _reconnectInFlight = false;
  _ReconnectPhase _reconnectPhase = _ReconnectPhase.idle;
  Timer? _toggleReconnectDebounce;
  final _customDomainCtrl = TextEditingController();

  List<SplitTunnelSite> get _presetSites =>
      _sites.where((s) => s.isPreset).toList();

  List<SplitTunnelSite> get _customSites =>
      _sites.where((s) => !s.isPreset).toList();

  @override
  void initState() {
    super.initState();
    Future.microtask(_reload);
  }

  @override
  void dispose() {
    _toggleReconnectDebounce?.cancel();
    _customDomainCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final mode = await VpnRouteModePrefs.getMode();
    var sites = const <SplitTunnelSite>[];
    if (mode == VpnRouteMode.sites) {
      await SplitTunnelPrefs.ensurePresetSites();
      sites = await SplitTunnelPrefs.loadSites();
    }
    if (!mounted) return;
    setState(() {
      _mode = mode;
      _sites = sites;
      _loading = false;
    });
  }

  Future<void> _afterMutation() async {
    final mode = await VpnRouteModePrefs.getMode();
    var sites = const <SplitTunnelSite>[];
    if (mode == VpnRouteMode.sites) {
      sites = await SplitTunnelPrefs.loadSites();
    }
    if (!mounted) return;
    setState(() {
      _sites = sites;
      _mode = mode;
    });
  }

  Future<void> _selectMode(VpnRouteMode next) async {
    if (next == _mode) return;
    if (next == VpnRouteMode.full) {
      final ok = await _confirmFullTunnel();
      if (!ok || !mounted) return;
    }
    if (next == VpnRouteMode.sites) {
      await SplitTunnelPrefs.ensurePresetSites();
    }
    await VpnRouteModePrefs.setMode(next);
    await _afterMutation();
    final vpn = ref.read(vpnProvider);
    if (vpn is VpnConnected && mounted) {
      await _reconnect();
    }
  }

  Future<bool> _confirmFullTunnel() async {
    final l = AppL10n.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l.modesConfirmFullTitle),
          content: Text(l.modesConfirmFullBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.modesConfirmFullCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: AppBrand.destructive,
                foregroundColor: AppBrand.surfaceElevatedLight,
              ),
              child: Text(l.modesConfirmFullOk),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  Future<void> _toggleSite(SplitTunnelSite site, bool enabled) async {
    await SplitTunnelPrefs.updateSite(site.copyWith(enabled: enabled));
    await _afterMutation();
    _scheduleReconnectIfConnected();
  }

  bool get _overlayVisible => _reconnectPhase != _ReconnectPhase.idle;

  void _scheduleReconnectIfConnected() {
    final vpn = ref.read(vpnProvider);
    if (vpn is! VpnConnected || !mounted) return;
    if (_reconnectPhase == _ReconnectPhase.idle) {
      setState(() => _reconnectPhase = _ReconnectPhase.working);
    }
    _toggleReconnectDebounce?.cancel();
    _toggleReconnectDebounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      unawaited(_reconnect());
    });
  }

  Future<void> _reconnect() async {
    if (_reconnectInFlight) return;
    _reconnectInFlight = true;
    if (_reconnectPhase == _ReconnectPhase.idle && mounted) {
      setState(() => _reconnectPhase = _ReconnectPhase.working);
    }
    try {
      final ok =
          await ref.read(vpnProvider.notifier).reconnectToApplyRouting();
      if (!mounted) return;
      setState(
        () => _reconnectPhase =
            ok ? _ReconnectPhase.success : _ReconnectPhase.failed,
      );
      // Short beat so the check / fail state is readable — not a SnackBar.
      await Future<void>.delayed(
        Duration(milliseconds: ok ? 700 : 900),
      );
    } finally {
      _reconnectInFlight = false;
      if (mounted) {
        setState(() => _reconnectPhase = _ReconnectPhase.idle);
        await _afterMutation();
      }
    }
  }

  Future<void> _addCustomSite() async {
    final l = AppL10n.of(context);
    final raw = _customDomainCtrl.text;
    final result = await SplitTunnelPrefs.addSite(domain: raw);
    if (!mounted) return;
    if (result is DomainNormalizeOk) {
      _customDomainCtrl.clear();
      FocusScope.of(context).unfocus();
      await _afterMutation();
      _scheduleReconnectIfConnected();
      return;
    }
    final err = result as DomainNormalizeErr;
    final msg = switch (err.kind) {
      DomainNormalizeErrorKind.duplicate => l.splitTunnelDuplicateDomain,
      DomainNormalizeErrorKind.nonAscii => l.splitTunnelNonAsciiUnsupported,
      _ => l.splitTunnelInvalidDomain,
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _deleteCustomSite(SplitTunnelSite site) async {
    final l = AppL10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
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
    _scheduleReconnectIfConnected();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final vpn = ref.watch(vpnProvider);
    final vpnOff = vpn is VpnDisconnected || vpn is VpnError;

    ref.listen<int>(modesTabTickProvider, (prev, next) {
      if (prev != null && next != prev && !_loading) {
        unawaited(_reload());
      }
    });

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  AbsorbPointer(
                    absorbing: _overlayVisible,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                      children: [
                        Text(
                          l.modesTitle,
                          style: theme.textTheme.displayMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l.modesSubtitle,
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 20),
                        _ModeCard(
                          selected: _mode == VpnRouteMode.smart,
                          title: l.modeSmartTitle,
                          body: l.modeSmartBody,
                          badge: l.modeSmartBadge,
                          onTap: () => _selectMode(VpnRouteMode.smart),
                        ),
                        const SizedBox(height: 10),
                        _ModeCard(
                          selected: _mode == VpnRouteMode.full,
                          title: l.modeFullTitle,
                          body: l.modeFullBody,
                          onTap: () => _selectMode(VpnRouteMode.full),
                        ),
                        const SizedBox(height: 10),
                        _ModeCard(
                          selected: _mode == VpnRouteMode.sites,
                          title: l.modeSitesTitle,
                          body: l.modeSitesBody,
                          onTap: () => _selectMode(VpnRouteMode.sites),
                        ),
                        if (vpnOff) ...[
                          const SizedBox(height: 14),
                          _VpnOffBanner(
                            title: l.modesVpnOffTitle,
                            body: l.modesVpnOffBody,
                            onTap: () => context.go('/home'),
                          ),
                        ],
                        if (_mode == VpnRouteMode.sites) ...[
                          const SizedBox(height: 24),
                          Text(
                            l.modesSitesSectionSites.toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _SitesCard(
                            sites: _presetSites,
                            onToggle: _toggleSite,
                          ),
                          const SizedBox(height: 24),
                          Text(
                            l.modesSitesCustomSection.toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _CustomSiteAddRow(
                            controller: _customDomainCtrl,
                            hint: l.modesSitesCustomHint,
                            onAdd: _addCustomSite,
                          ),
                          if (_customSites.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _SitesCard(
                              sites: _customSites,
                              onToggle: _toggleSite,
                              onDelete: _deleteCustomSite,
                            ),
                          ],
                          const SizedBox(height: 14),
                          Text(
                            l.modesSitesAllowlistHint,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l.modesSitesMetaNote,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.85),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_overlayVisible)
                    Positioned.fill(
                      child: _ReconnectingScrim(
                        phase: _reconnectPhase,
                        workingTitle: l.modesReconnectingTitle,
                        workingBody: l.modesReconnectingBody,
                        successTitle: l.modesReconnectedTitle,
                        failedTitle: l.modesReconnectFailedTitle,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.selected,
    required this.title,
    required this.body,
    required this.onTap,
    this.badge,
  });

  final bool selected;
  final String title;
  final String body;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = theme.colorScheme.outline;
    final elevated = theme.colorScheme.surfaceContainerHighest;

    return Material(
      color: elevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBrand.radiusCard),
        side: BorderSide(
          color: selected ? theme.colorScheme.onSurface : line,
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: selected
                    ? AppIcon(
                        AppIcons.checkCircleFill,
                        size: 22,
                        color: theme.colorScheme.onSurface,
                      )
                    : AppIcon(
                        AppIcons.checkCircle,
                        size: 22,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppBrand.inkWithOpacity(0.08),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              badge!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(body, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VpnOffBanner extends StatelessWidget {
  const _VpnOffBanner({
    required this.title,
    required this.body,
    required this.onTap,
  });

  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppBrand.inkWithOpacity(0.06),
      borderRadius: BorderRadius.circular(AppBrand.radiusCard),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppBrand.radiusCard),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppBrand.primary,
                  shape: BoxShape.circle,
                ),
                child: const Text(
                  '!',
                  style: TextStyle(
                    color: AppBrand.surfaceElevatedLight,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(body, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              AppIcon(
                AppIcons.chevronRight,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ReconnectPhase { idle, working, success, failed }

class _ReconnectingScrim extends StatelessWidget {
  const _ReconnectingScrim({
    required this.phase,
    required this.workingTitle,
    required this.workingBody,
    required this.successTitle,
    required this.failedTitle,
  });

  final _ReconnectPhase phase;
  final String workingTitle;
  final String workingBody;
  final String successTitle;
  final String failedTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSuccess = phase == _ReconnectPhase.success;
    final isFailed = phase == _ReconnectPhase.failed;
    final title = isSuccess
        ? successTitle
        : isFailed
            ? failedTitle
            : workingTitle;
    final body = (isSuccess || isFailed) ? null : workingBody;

    return AbsorbPointer(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: ColoredBox(
            color: theme.colorScheme.surface.withValues(alpha: 0.55),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Column(
                    key: ValueKey(phase),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isSuccess)
                        const AppIcon(
                          AppIcons.checkCircleFill,
                          size: 44,
                          color: AppBrand.success,
                        )
                      else if (isFailed)
                        const AppIcon(
                          AppIcons.warning,
                          size: 44,
                          color: AppBrand.destructive,
                        )
                      else
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      const SizedBox(height: 20),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (body != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          body,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomSiteAddRow extends StatelessWidget {
  const _CustomSiteAddRow({
    required this.controller,
    required this.hint,
    required this.onAdd,
  });

  final TextEditingController controller;
  final String hint;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppBrand.radiusCard),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                style: theme.textTheme.bodyMedium,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onAdd(),
                decoration: InputDecoration(
                  hintText: hint,
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            Material(
              color: theme.colorScheme.onSurface,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onAdd,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    Icons.add,
                    color: theme.colorScheme.surface,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SitesCard extends StatelessWidget {
  const _SitesCard({
    required this.sites,
    required this.onToggle,
    this.onDelete,
  });

  final List<SplitTunnelSite> sites;
  final Future<void> Function(SplitTunnelSite site, bool enabled) onToggle;
  final Future<void> Function(SplitTunnelSite site)? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (sites.isEmpty) {
      return const SizedBox.shrink();
    }
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBrand.radiusCard),
        side: BorderSide(color: theme.colorScheme.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < sites.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 56,
                color: theme.colorScheme.outline.withValues(alpha: 0.6),
              ),
            _SiteTile(
              site: sites[i],
              onToggle: onToggle,
              onDelete: onDelete,
            ),
          ],
        ],
      ),
    );
  }
}

class _SiteTile extends StatelessWidget {
  const _SiteTile({
    required this.site,
    required this.onToggle,
    this.onDelete,
  });

  final SplitTunnelSite site;
  final Future<void> Function(SplitTunnelSite site, bool enabled) onToggle;
  final Future<void> Function(SplitTunnelSite site)? onDelete;

  IconData get _leadingIcon {
    if (!site.isPreset) return AppIcons.siteCustom;
    return switch (site.domain) {
      'cloudflare.com' => AppIcons.siteCloudflare,
      'youtube.com' => AppIcons.siteYoutube,
      'tiktok.com' => AppIcons.siteTiktok,
      'instagram.com' => AppIcons.siteInstagram,
      'whatsapp.com' => AppIcons.siteWhatsapp,
      'telegram.org' => AppIcons.siteTelegram,
      'discord.com' => AppIcons.siteDiscord,
      'chatgpt.com' => AppIcons.siteChatgpt,
      'gemini.google.com' => AppIcons.siteGemini,
      _ => AppIcons.siteCustom,
    };
  }

  Widget _leading(BuildContext context, ThemeData theme) {
    final color = theme.colorScheme.onSurface;
    if (site.isPreset && site.domain == 'claude.ai') {
      return CircleAvatar(
        backgroundColor: AppBrand.inkWithOpacity(0.08),
        child: ColorFiltered(
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          child: Image.asset(
            AppIcons.siteClaudeAsset,
            width: 20,
            height: 20,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => AppIcon(
              AppIcons.siteCustom,
              size: 22,
              color: color,
            ),
          ),
        ),
      );
    }
    return CircleAvatar(
      backgroundColor: AppBrand.inkWithOpacity(0.08),
      child: AppIcon(
        _leadingIcon,
        size: 22,
        color: color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = site.label.isEmpty ? site.domain : site.label;
    final subtitle = site.subtitle.isNotEmpty
        ? site.subtitle
        : (site.label.isEmpty ? null : site.domain);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: _leading(context, theme),
      title: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: theme.textTheme.bodySmall),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onDelete != null)
            IconButton(
              tooltip: AppL10n.of(context).splitTunnelDelete,
              onPressed: () => onDelete!(site),
              icon: Icon(
                Icons.close,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          Switch(
            value: site.enabled,
            onChanged: (v) => onToggle(site, v),
          ),
        ],
      ),
    );
  }
}
