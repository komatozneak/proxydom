import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ios_store_gates.dart';
import '../../../core/utils/format_utils.dart';
import '../../../l10n/app_localizations.dart';
import '../../account/application/ios_account_nav.dart';
import '../../beta/presentation/promo_redeem_form.dart';
import '../../home/application/vpn_provider.dart';
import '../../home/presentation/widgets/free_quota_bar.dart';
import '../../settings/application/subscription_status_provider.dart';
import '../../settings/data/access_status_copy.dart';
import '../../settings/data/subscription_status.dart';

const kSubscriptionPayKey = ValueKey<String>('subscription_pay');
const kSubscriptionPromoKey = ValueKey<String>('subscription_promo');
const kSubscriptionAdvancedKey = ValueKey<String>('subscription_advanced');

/// Огонь-style «Подписка» — status + pay on top, promo at the bottom.
class SubscriptionTabScreen extends ConsumerWidget {
  const SubscriptionTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final async = ref.watch(subscriptionStatusProvider);
    final buttonStyle = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    );

    return Scaffold(
      appBar: AppBar(title: Text(l.navSubscription)),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  async.when(
                    data: (status) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Card(
                          child: ListTile(
                            title: Text(_titleFor(l, status)),
                            subtitle: Text(_subtitleFor(l, status)),
                          ),
                        ),
                        if (status.showsMeteredQuotaBar) ...[
                          const SizedBox(height: 12),
                          FreeQuotaBar(
                            remainingFraction: status.quotaRemainingFraction,
                            title: l.homeTrafficRemainder,
                            amountLabel: l.homeTrafficAmount(
                              formatGib(
                                (status.quotaBytesRemaining ?? 0) /
                                    (1024 * 1024 * 1024),
                                russian:
                                    Localizations.localeOf(context)
                                            .languageCode ==
                                        'ru',
                              ),
                              formatGib(
                                (status.quotaBytesLimit ?? 0) /
                                    (1024 * 1024 * 1024),
                                russian:
                                    Localizations.localeOf(context)
                                            .languageCode ==
                                        'ru',
                              ),
                            ),
                            exhaustedLabel: l.homeTrafficExhausted,
                            onTap: status.quotaExhausted
                                ? () => context.push('/locked')
                                : null,
                          ),
                        ],
                      ],
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (_, __) => Text(l.settingsAccessNoneSubtitle),
                  ),
                  const SizedBox(height: 20),
                  if (hideInAppPlategaCheckout) ...[
                    Text(
                      l.iosBillingUnavailableBody,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      key: kSubscriptionAdvancedKey,
                      style: buttonStyle,
                      onPressed: () =>
                          openIosAdvancedFeaturesPath(context, ref),
                      child: Text(l.iosAdvancedFeaturesCta),
                    ),
                  ] else
                    FilledButton(
                      key: kSubscriptionPayKey,
                      style: buttonStyle,
                      onPressed: () => context.push('/locked'),
                      child: Text(l.subscriptionPay),
                    ),
                ],
              ),
            ),
          ),
          if (!hideInAppPlategaCheckout)
            SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: KeyedSubtree(
                  key: kSubscriptionPromoKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Divider(
                              color: theme.colorScheme.outline
                                  .withValues(alpha: 0.55),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Text(
                              l.lockedOrPromo,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.72),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Divider(
                              color: theme.colorScheme.outline
                                  .withValues(alpha: 0.55),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      PromoRedeemForm(
                        useTonalButton: true,
                        buttonStyle: buttonStyle,
                        textFieldContentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 18,
                        ),
                        onSuccess: () async {
                          await ref
                              .read(vpnNodesRepositoryProvider)
                              .refreshAfterEntitlementChange();
                          await ref
                              .read(subscriptionStatusProvider.notifier)
                              .refresh();
                          if (context.mounted) context.go('/locations');
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _titleFor(AppL10n l, SubscriptionStatus s) {
    switch (accessCopyKind(s)) {
      case AccessCopyKind.paidOrTrial:
        return l.settingsAccessEarlyTitle;
      case AccessCopyKind.closedBeta:
        return l.settingsAccessBetaTitle;
      case AccessCopyKind.cancelled:
        return l.settingsAccessCancelledSubtitle;
      case AccessCopyKind.free:
        return l.settingsAccessFreeTitle;
      case AccessCopyKind.none:
        return l.settingsAccessNoneTitle;
      case AccessCopyKind.generic:
        return s.plan ?? l.settingsAccessNoneTitle;
    }
  }

  static String _subtitleFor(AppL10n l, SubscriptionStatus s) {
    if (s.expiresAt != null) {
      final d = s.expiresAt!.toLocal();
      final date =
          '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
      return l.settingsAccessActiveUntil(date);
    }
    if (s.quotaUnlimited) {
      return l.premiumUnlimitedTraffic;
    }
    switch (accessCopyKind(s)) {
      case AccessCopyKind.closedBeta:
        return l.settingsAccessBetaSubtitle;
      case AccessCopyKind.free:
        return l.settingsAccessFreeSubtitle;
      case AccessCopyKind.none:
        return l.settingsAccessNoneSubtitle;
      default:
        return l.settingsAccessEarlySubtitle;
    }
  }
}
