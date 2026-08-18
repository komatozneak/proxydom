import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/support_contact.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../application/auth_provider.dart';

/// Shown when AUTH_ANONYMOUS bootstrap fails (network / server / VPN lockdown).
class BootstrapFailedScreen extends ConsumerWidget {
  const BootstrapFailedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final loading = ref.watch(authProvider).isLoading;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppIcon(AppIcons.warning, size: 48),
              const SizedBox(height: 16),
              Text(
                l.bootstrapFailed,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: loading
                    ? null
                    : () => ref.read(authProvider.notifier).retryBootstrap(),
                child: loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l.homeRetry),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => context.go('/restore'),
                child: Text(l.settingsRecoverAccess),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => SupportContact.open(screen: 'Ошибка входа'),
                child: Text(l.settingsSupport),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
