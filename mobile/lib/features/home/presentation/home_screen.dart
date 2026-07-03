import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app.dart';
import '../../../../l10n/app_localizations.dart';
import '../../auth/application/auth_provider.dart';
import '../../auth/application/auth_state.dart';
import '../application/vpn_provider.dart';
import '../application/vpn_status.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              icon: const Icon(Icons.logout),
              tooltip: l.logoutTooltip,
              onPressed: () {
                ref.read(authProvider.notifier).unauthenticated();
              },
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
                    label: l.homeRegion,
                    onPressed: vpnStatus is VpnConnected
                        ? null
                        : () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Region select — Step 12'),
                              ),
                            );
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
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.status});

  final VpnStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppL10n.of(context);

    late final Color color;
    late final String label;
    late final Widget child;
    String? errorMessage;

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
        color = theme.colorScheme.primary;
        label = l.homeConnected;
        child = Icon(Icons.shield, size: 96, color: color);
        // suppress unused warning for destructured locals
        assert(s.isNotEmpty && p.isNotEmpty);
      case VpnError():
        final msg = (status as VpnError).message;
        color = theme.colorScheme.error;
        label = l.homeError;
        child = Icon(Icons.error_outline, size: 96, color: color);
        errorMessage = msg;
    }

    return Column(
      children: [
        Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.1),
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
        ],
        if (status is VpnError) ...[
          const SizedBox(height: 4),
          Text(
            errorMessage ?? '',
            style: theme.textTheme.bodySmall?.copyWith(color: color),
            textAlign: TextAlign.center,
          ),
        ],
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