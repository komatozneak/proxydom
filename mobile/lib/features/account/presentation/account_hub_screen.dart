import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/app_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/application/subscription_status_provider.dart';
import '../../settings/data/access_status_copy.dart';
import '../../settings/data/subscription_status.dart';
import '../application/account_profile_provider.dart';
import '../data/account_profile.dart';
import 'telegram_link_dialog.dart';

/// Settings → Account hub (device ID identity; recovery code + promo).
class AccountHubScreen extends ConsumerWidget {
  const AccountHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final profileAsync = ref.watch(accountProfileProvider);
    final subAsync = ref.watch(subscriptionStatusProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(l.accountHubTitle),
        leading: IconButton(
          icon: const AppIcon(AppIcons.back, size: 22),
          onPressed: () => context.pop(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(accountProfileProvider.notifier).refresh();
          await ref.read(subscriptionStatusProvider.notifier).refresh();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            profileAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => _ErrorCard(
                message: l.accountHubLoadError,
                onRetry: () =>
                    ref.read(accountProfileProvider.notifier).refresh(),
              ),
              data: (profile) {
                final accessTitle = _accessTitle(context, l, subAsync);
                final accessSubtitle = _accessSubtitle(context, l, subAsync);
                return _HubBody(
                  profile: profile,
                  accessTitle: accessTitle,
                  accessSubtitle: accessSubtitle,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatAccessDate(BuildContext context, DateTime dt) {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat('d MMMM y', locale).format(dt);
  }

  String _accessTitle(
    BuildContext context,
    AppL10n l,
    AsyncValue<SubscriptionStatus> async,
  ) {
    return async.when(
      data: (s) {
        switch (accessCopyKind(s)) {
          case AccessCopyKind.paidOrTrial:
            return l.settingsSubscriptionActive;
          case AccessCopyKind.cancelled:
            return l.settingsSubscriptionActiveUntil(
              _formatAccessDate(context, s.expiresAt!),
            );
          case AccessCopyKind.closedBeta:
            return l.settingsAccessBetaTitle;
          case AccessCopyKind.free:
            return l.settingsAccessFreeTitle;
          case AccessCopyKind.none:
            return l.settingsAccessNoneTitle;
          case AccessCopyKind.generic:
            return l.settingsSubscription;
        }
      },
      loading: () => l.settingsSubscription,
      error: (_, __) => l.settingsSubscription,
    );
  }

  String _accessSubtitle(
    BuildContext context,
    AppL10n l,
    AsyncValue<SubscriptionStatus> async,
  ) {
    return async.when(
      data: (s) {
        switch (accessCopyKind(s)) {
          case AccessCopyKind.paidOrTrial:
            if (s.expiresAt != null) {
              return l.settingsAccessActiveUntil(
                _formatAccessDate(context, s.expiresAt!),
              );
            }
            return l.settingsAccessBetaSubtitle;
          case AccessCopyKind.cancelled:
            return l.settingsAccessCancelledSubtitle;
          case AccessCopyKind.closedBeta:
            if (s.expiresAt != null) {
              return l.settingsAccessActiveUntil(
                _formatAccessDate(context, s.expiresAt!),
              );
            }
            return l.settingsAccessBetaSubtitle;
          case AccessCopyKind.free:
            return l.settingsAccessFreeSubtitle;
          case AccessCopyKind.none:
            return l.settingsAccessNoneSubtitle;
          case AccessCopyKind.generic:
            if (s.status == 'expired' && s.expiresAt != null) {
              return l.settingsAccessActiveUntil(
                _formatAccessDate(context, s.expiresAt!),
              );
            }
            return l.settingsAccessNoneSubtitle;
        }
      },
      loading: () => '…',
      error: (_, __) => l.settingsSubscriptionLoadError,
    );
  }
}

class _HubBody extends StatelessWidget {
  const _HubBody({
    required this.profile,
    required this.accessTitle,
    required this.accessSubtitle,
  });

  final AccountProfile profile;
  final String accessTitle;
  final String accessSubtitle;

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.accountHubGuestLead,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          children: [
            _NavTile(
              icon: AppIcons.shield,
              title: l.accountHubRecovery,
              subtitle: l.accountHubRecoveryHint,
              onTap: () => context.push('/settings/account/recovery'),
            ),
            const Divider(height: 1),
            _NavTile(
              icon: AppIcons.crown,
              title: l.accountHubPromo,
              subtitle: l.accountHubPromoHint,
              onTap: () => context.push('/settings/account/promo'),
            ),
            const Divider(height: 1),
            _NavTile(
              icon: AppIcons.devices,
              title: l.settingsDevices,
              subtitle: '${profile.devicesCount} / ${profile.deviceLimit}',
              onTap: () => context.push('/settings/devices'),
            ),
            const Divider(height: 1),
            _NavTile(
              icon: AppIcons.siteTelegram,
              title: l.accountHubLinkTelegram,
              subtitle: profile.telegramUsername != null
                  ? '@${profile.telegramUsername}'
                  : l.accountHubLinkTelegramHint,
              onTap: () async {
                await TelegramLinkDialog.show(context);
              },
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          l.accountHubAccessSection,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _SectionCard(
          children: [
            ListTile(
              title: Text(accessTitle),
              subtitle: Text(accessSubtitle),
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(16),
      child: Column(children: children),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: AppIcon(icon, size: 22),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const AppIcon(AppIcons.chevronRight, size: 18),
      onTap: onTap,
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    return Column(
      children: [
        Text(message),
        const SizedBox(height: 12),
        TextButton(onPressed: onRetry, child: Text(l.homeRetry)),
      ],
    );
  }
}
