import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../beta/presentation/promo_redeem_form.dart';
import '../../home/application/vpn_provider.dart';
import '../../referral/presentation/referral_share_card.dart';

/// Promo redeem from Account hub — pop back after success (shell SoT).
class AccountPromoScreen extends ConsumerWidget {
  const AccountPromoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.accountHubPromo),
        leading: IconButton(
          icon: const AppIcon(AppIcons.back, size: 22),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.promoHeadline,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                l.promoBody,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 24),
              const ReferralShareCard(),
              PromoRedeemForm(
                onSuccess: () async {
                  await ref
                      .read(vpnNodesRepositoryProvider)
                      .refreshAfterEntitlementChange();
                  if (context.mounted) context.pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
