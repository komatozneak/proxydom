import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/application/subscription_status_provider.dart';

/// Огонь-style «Премиум» tab — no-ads / YouTube locations upsell.
class PremiumTabScreen extends ConsumerWidget {
  const PremiumTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final status = ref.watch(subscriptionStatusProvider).valueOrNull;
    final isPremium = status != null && (status.isPro || status.isAlpha);

    return Scaffold(
      appBar: AppBar(title: Text(l.navPremium)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            l.premiumHeadline,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l.premiumBody,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          _FeatureRow(icon: Icons.play_circle_outline, text: l.premiumFeatureYt),
          _FeatureRow(icon: Icons.speed, text: l.premiumFeatureSpeed),
          _FeatureRow(icon: Icons.all_inclusive, text: l.premiumUnlimitedTraffic),
          const SizedBox(height: 32),
          if (isPremium)
            FilledButton.tonal(
              onPressed: () => context.go('/locations'),
              child: Text(l.premiumOpenLocations),
            )
          else
            FilledButton(
              onPressed: () => context.go('/subscription'),
              child: Text(l.premiumCta),
            ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: AppBrand.livingHouse),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
