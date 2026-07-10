import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_provider.dart';
import '../../auth/application/auth_state.dart';
import '../../auth/application/logout_handler.dart';
import '../../vpn/data/vpn_node.dart';
import '../../vpn/data/vpn_nodes_repository.dart';
import '../../vpn/presentation/region_picker.dart';
import '../application/vpn_provider.dart';
import '../application/vpn_status.dart';
import '../data/external_ip_service.dart';
import '../../../../app.dart';
import '../../../../l10n/app_localizations.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  bool _logoutInProgress = false;
  String _regionSubtitle = '…';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshRegionLabel();
      ref.read(vpnProvider.notifier).syncFromNative();
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
      ref.read(vpnProvider.notifier).syncFromNative();
    }
  }

  Future<void> _refreshRegionLabel() async {
    final l = AppL10n.of(context);
    final nodesRepo = ref.read(vpnNodesRepositoryProvider);
    try {
      final selectedId = await nodesRepo.getSelectedNodeId();
      final nodes = await nodesRepo.listNodes();
      if (!mounted) return;
      if (nodes.isEmpty) {
        setState(() => _regionSubtitle = l.homeRegion);
        return;
      }
      final VpnNode selected = nodes.where((n) => n.id == selectedId).firstOrNull ??
          nodes.where((n) => n.isDefault).firstOrNull ??
          nodes.first;
      final label = selected.label.isNotEmpty ? selected.label : selected.host;
      setState(() => _regionSubtitle = label);
    } catch (_) {
      if (mounted) {
        setState(() => _regionSubtitle = l.homeRegion);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final authState =
        ref.watch(authProvider).valueOrNull ?? const AuthStateUnknown();
    final isAuthed = authState is AuthStateAuthenticated;
    final vpnStatus = ref.watch(vpnProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(l.homeTitle),
        actions: [
          TextButton(
            onPressed: () {
              final next = AppLocale.current.languageCode == 'ru'
                  ? const Locale('en')
                  : const Locale('ru');
              AppLocale.set(next);
              (context as Element).findAncestorWidgetOfExactType<MaterialApp>();
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  ),
                ),
              );
              Navigator.of(context).pop();
            },
            child: Text(
              AppLocale.current.languageCode.toUpperCase(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
          if (isAuthed)
            IconButton(
              icon: _logoutInProgress
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout),
              tooltip: l.logoutTooltip,
              onPressed: _logoutInProgress ? null : _onLogoutPressed,
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatusIndicator(status: vpnStatus),
              _ConnectButton(status: vpnStatus),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _IconAction(
                    icon: Icons.dns,
                    label: _regionSubtitle,
                    onPressed: () async {
                      await showRegionPicker(context, ref);
                      if (mounted) await _refreshRegionLabel();
                    },
                  ),
                  _IconAction(
                    icon: Icons.tune,
                    label: l.homeSettings,
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Settings — out of MVP'),
                        ),
                      );
                    },
                  ),
                  _IconAction(
                    icon: Icons.info_outline,
                    label: l.homeAbout,
                    onPressed: () {
                      showAboutDialog(
                        context: context,
                        applicationName: 'Teremok Connect',
                        applicationVersion: '0.1.0',
                        applicationLegalese: '© 2026',
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onLogoutPressed() async {
    final l = AppL10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.logoutConfirmTitle),
        content: Text(l.logoutConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.logoutTooltip),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _logoutInProgress = true);

    final result = await ref.read(logoutHandlerProvider).logout();

    if (!mounted) return;
    setState(() => _logoutInProgress = false);

    if (result is LogoutPartialFailure && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l.logoutWarning}: ${result.message}'),
          duration: const Duration(seconds: 5),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
    // GoRouter сам перенаправит на /login через refreshListenable.
  }
}

class _StatusIndicator extends ConsumerWidget {
  const _StatusIndicator({required this.status});

  final VpnStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l = AppL10n.of(context);
    final vpnConfig = ref.watch(vpnProvider.notifier).config;

    late final Color color;
    late final String label;
    late final Widget child;
    String? errorMessage;
    String? serverInfo;

    switch (status) {
      case VpnDisconnected():
        color = theme.colorScheme.outline;
        label = l.homeDisconnected;
        child = const Icon(Icons.power_settings_new, size: 96);
      case VpnConnecting():
        final p = (status as VpnConnecting).progress;
        color = theme.colorScheme.tertiary;
        label = l.homeConnecting;
        child = SizedBox(
          width: 96,
          height: 96,
          child: CircularProgressIndicator(
            value: p,
            strokeWidth: 6,
            color: color,
          ),
        );
      case VpnConnected():
        final s = (status as VpnConnected).serverName;
        final p = (status as VpnConnected).protocol;
        final host = vpnConfig?.singBoxConfig.primaryOutbound?.server;
        final port = vpnConfig?.singBoxConfig.primaryOutbound?.serverPort;
        color = theme.colorScheme.primary;
        label = l.homeConnected;
        child = Icon(Icons.shield, size: 96, color: color);
        // suppress unused warning for destructured locals
        assert(s.isNotEmpty && p.isNotEmpty);
        if (host != null && port != null) {
          serverInfo = '$host:$port';
        }
      case VpnError():
        final msg = (status as VpnError).message;
        color = theme.colorScheme.error;
        label = l.homeError;
        child = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 8),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Auto-retry in 5s...',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        );
        errorMessage = msg;
    }

    return Column(
      children: [
        Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.1),
            border: Border.all(color: color, width: 3),
          ),
          child: Center(child: child),
        ),
        const SizedBox(height: 16),
        Text(
          label,
          style: theme.textTheme.headlineSmall?.copyWith(color: color),
        ),
        if (status is VpnConnected) ...[
          const SizedBox(height: 4),
          Text(
            '${(status as VpnConnected).serverName} · '
            '${(status as VpnConnected).protocol}',
            style: theme.textTheme.bodyMedium,
          ),
          if (serverInfo != null) ...[
            const SizedBox(height: 2),
            Text(
              'VPS: $serverInfo',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
          const SizedBox(height: 8),
          _ConnectedDetails(connected: status as VpnConnected),
        ],
        if (status is VpnError) ...[
          const SizedBox(height: 4),
          Text(
            errorMessage ?? '',
            style: theme.textTheme.bodySmall?.copyWith(color: color),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              try {
                await ref.read(vpnProvider.notifier).fetchConfig();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l.homeFetchConfig)),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l.homeConfigError(e.toString()))),
                  );
                }
              }
            },
            icon: const Icon(Icons.cloud_download),
            label: Text(l.homeFetchConfig),
          ),
        ],
      ],
    );
  }
}

/// Uptime + external IP while VPN is connected (E2E visibility).
class _ConnectedDetails extends StatefulWidget {
  const _ConnectedDetails({required this.connected});

  final VpnConnected connected;

  @override
  State<_ConnectedDetails> createState() => _ConnectedDetailsState();
}

class _ConnectedDetailsState extends State<_ConnectedDetails> {
  Timer? _uptimeTimer;
  String? _externalIp;
  bool _ipLoading = true;

  @override
  void initState() {
    super.initState();
    _uptimeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _loadExternalIp();
  }

  @override
  void didUpdateWidget(covariant _ConnectedDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connected.connectedSince != widget.connected.connectedSince) {
      _loadExternalIp();
    }
  }

  Future<void> _loadExternalIp() async {
    setState(() {
      _ipLoading = true;
      _externalIp = null;
    });
    final ip = await fetchExternalIp();
    if (!mounted) return;
    setState(() {
      _externalIp = ip;
      _ipLoading = false;
    });
  }

  @override
  void dispose() {
    _uptimeTimer?.cancel();
    super.dispose();
  }

  String _formatUptime(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:$m:$s';
    }
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uptime = DateTime.now().difference(widget.connected.connectedSince);

    return Column(
      children: [
        Text(
          'Uptime: ${_formatUptime(uptime)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 4),
        if (_ipLoading)
          Text(
            'IP: …',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          )
        else if (_externalIp != null)
          Text(
            'IP: $_externalIp',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          )
        else
          Text(
            'IP: unavailable',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
      ],
    );
  }
}

class _ConnectButton extends ConsumerWidget {
  const _ConnectButton({required this.status});

  final VpnStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppL10n.of(context);

    late final String label;
    late final IconData icon;
    late final Color background;
    late final VoidCallback? onPressed;

    switch (status) {
      case VpnDisconnected():
        label = l.homeConnect;
        icon = Icons.play_arrow;
        background = Theme.of(context).colorScheme.primary;
        onPressed = () => ref.read(vpnProvider.notifier).connect();
      case VpnConnecting():
        label = l.homeConnecting;
        icon = Icons.hourglass_empty;
        background = Theme.of(context).colorScheme.tertiary;
        onPressed = null;
      case VpnConnected():
        label = l.homeDisconnect;
        icon = Icons.stop;
        background = Theme.of(context).colorScheme.error;
        onPressed = () => ref.read(vpnProvider.notifier).disconnect();
      case VpnError():
        label = l.homeConnect;
        icon = Icons.refresh;
        background = Theme.of(context).colorScheme.error;
        onPressed = () => ref.read(vpnProvider.notifier).connect();
    }

    return SizedBox(
      width: double.infinity,
      height: 64,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 28),
        label: Text(label, style: Theme.of(context).textTheme.titleMedium),
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}