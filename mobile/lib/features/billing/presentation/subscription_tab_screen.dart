import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/application/subscription_status_provider.dart';
import '../../settings/data/access_status_copy.dart';
import '../../settings/data/subscription_status.dart';

/// Огонь-style «Подписка» tab — plans / promo / status.
class SubscriptionTabScreen extends ConsumerWidget {
  const SubscriptionTabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final async = ref.watch(subscriptionStatusProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.navSubscription)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          async.when(
            data: (status) => Card(
              child: ListTile(
                title: Text(_titleFor(l, status)),
                subtitle: Text(_subtitleFor(l, status)),
              ),
            ),
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => Text(l.settingsAccessNoneSubtitle),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.push('/locked'),
            child: Text(l.lockedPay1m),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => context.push('/settings/account/promo'),
            child: Text(l.lockedOrPromo),
          ),
          const SizedBox(height: 24),
          Text(
            l.subscriptionTabHint,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
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
      return l.settingsAccessFreeSubtitle;
    }
    if (accessCopyKind(s) == AccessCopyKind.free &&
        s.quotaBytesRemaining != null &&
        s.quotaBytesLimit != null) {
      final remGiB = s.quotaBytesRemaining! / (1024 * 1024 * 1024);
      final limGiB = s.quotaBytesLimit! / (1024 * 1024 * 1024);
      return '${l.settingsAccessFreeTitle}: '
          '${remGiB.toStringAsFixed(2)} / ${limGiB.toStringAsFixed(2)} GiB';
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
