import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../home/application/vpn_provider.dart';
import '../../settings/application/subscription_status_provider.dart';
import 'promo_redeem_form.dart';

/// Promo code entry for the closed-beta access gate.
class PromoCodeScreen extends ConsumerWidget {
  const PromoCodeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.promoTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppBrand.secondary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const AppIcon(
                    AppIcons.shield,
                    size: 44,
                    color: AppBrand.secondary,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                l.promoHeadline,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                l.promoBody,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              PromoRedeemForm(
                onSuccess: () async {
                  await ref
                      .read(vpnNodesRepositoryProvider)
                      .refreshAfterEntitlementChange();
                  await ref.read(subscriptionStatusProvider.notifier).refresh();
                  if (context.mounted) {
                    await AppRouter.goAfterEntitlement(context, '/onboarding');
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
