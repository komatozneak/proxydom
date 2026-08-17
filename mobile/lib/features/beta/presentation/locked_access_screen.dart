import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config.dart';
import '../../../core/router.dart';
import '../../../core/support_contact.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../billing/data/billing_api.dart';
import '../../home/application/vpn_provider.dart';
import '../../settings/application/devices_list_provider.dart';
import '../../settings/application/subscription_status_provider.dart';

const kLockedPayCardKey = ValueKey<String>('locked_pay_card');
const kLockedFooterKey = ValueKey<String>('locked_footer');
const kLockedPayCtaKey = ValueKey<String>('locked_pay_cta');

class _PayPlan {
  const _PayPlan({
    required this.id,
    required this.months,
    required this.priceRub,
    required this.label,
  });

  final String id;
  final int months;
  final int priceRub;
  final String label;

  int get perMonthRub => (priceRub / months).round();

  int get savePercent {
    if (months <= 1) return 0;
    final full = AppConfig.plan1mPriceRub * months;
    if (full <= 0) return 0;
    return (((full - priceRub) / full) * 100).round();
  }
}

List<_PayPlan> _plans(AppL10n l) => [
      _PayPlan(
        id: '1m',
        months: 1,
        priceRub: AppConfig.plan1mPriceRub,
        label: l.lockedPlan1m,
      ),
      _PayPlan(
        id: '3m',
        months: 3,
        priceRub: AppConfig.plan3mPriceRub,
        label: l.lockedPlan3m,
      ),
      _PayPlan(
        id: '6m',
        months: 6,
        priceRub: AppConfig.plan6mPriceRub,
        label: l.lockedPlan6m,
      ),
      _PayPlan(
        id: '12m',
        months: 12,
        priceRub: AppConfig.plan12mPriceRub,
        label: l.lockedPlan12m,
      ),
    ];

/// Activation paywall: Platega plans (promo lives on Subscription).
class LockedAccessScreen extends ConsumerStatefulWidget {
  const LockedAccessScreen({super.key});

  @override
  ConsumerState<LockedAccessScreen> createState() => _LockedAccessScreenState();
}

class _LockedAccessScreenState extends ConsumerState<LockedAccessScreen> {
  bool _payBusy = false;
  String? _error;
  String _selectedPlan = '1m';

  Future<void> _goAfterUnlock() async {
    await ref
        .read(vpnNodesRepositoryProvider)
        .refreshAfterEntitlementChange();
    await ref.read(subscriptionStatusProvider.notifier).refresh();
    if (!mounted) return;
    AppRouter.postAuthResolved = true;
    context.go('/locations');
  }

  Future<void> _pay(String plan) async {
    setState(() {
      _payBusy = true;
      _error = null;
    });
    try {
      final created = await BillingApi().createPlategaPayment(plan: plan);
      final uri = Uri.tryParse(created.redirectUrl);
      if (uri == null) {
        throw StateError('bad redirect');
      }
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _error = AppL10n.of(context).lockedPayFailed;
          _payBusy = false;
        });
        return;
      }
      setState(() => _payBusy = false);
      if (!mounted) return;
      _showPayReturnDialog();
    } on DioException catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppL10n.of(context).lockedPayFailed;
        _payBusy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppL10n.of(context).lockedPayFailed;
        _payBusy = false;
      });
    }
  }

  void _showPayReturnDialog() {
    final l = AppL10n.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.lockedPayReturnTitle),
        content: Text(l.lockedPayReturnBody),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _goAfterUnlock();
            },
            child: Text(l.lockedPayReturnCheck),
          ),
        ],
      ),
    );
  }

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final busy = _payBusy;
    final devices = ref.watch(devicesListProvider).valueOrNull;
    final memberCannotPay = devices != null &&
        devices.devices.any((d) => d.isCurrent && !d.isOwner);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.72);
    final plans = _plans(l);
    final selected = plans.firstWhere(
      (p) => p.id == _selectedPlan,
      orElse: () => plans.first,
    );
    final buttonStyle = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    );

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(l.lockedTitle),
        centerTitle: true,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
                child: Column(
                  children: [
                    Material(
                      key: kLockedPayCardKey,
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(24),
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              l.lockedHeadline,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppBrand.primary,
                                height: 1.2,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              l.lockedBody,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: muted,
                                height: 1.45,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 28),
                            if (memberCannotPay)
                              Text(
                                l.settingsPayOwnerOnly,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: muted,
                                  height: 1.45,
                                ),
                                textAlign: TextAlign.center,
                              )
                            else ...[
                              for (final plan in plans) ...[
                                _PlanTile(
                                  plan: plan,
                                  selected: plan.id == selected.id,
                                  enabled: !busy,
                                  saveLabel: plan.savePercent > 0
                                      ? l.lockedSavePercent(plan.savePercent)
                                      : null,
                                  perMonthLabel:
                                      l.lockedPerMonth(plan.perMonthRub),
                                  onTap: () =>
                                      setState(() => _selectedPlan = plan.id),
                                ),
                                const SizedBox(height: 10),
                              ],
                              const SizedBox(height: 6),
                              FilledButton(
                                key: kLockedPayCtaKey,
                                style: buttonStyle,
                                onPressed:
                                    busy ? null : () => _pay(selected.id),
                                child:
                                    Text(l.lockedPayAmount(selected.priceRub)),
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 20),
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    KeyedSubtree(
                      key: kLockedFooterKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () => _open(AppConfig.privacyPolicyUrl),
                                child: Text(l.settingsPrivacyPlaceholder),
                              ),
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () => _open(AppConfig.termsOfServiceUrl),
                                child: Text(l.settingsTerms),
                              ),
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () => _open(AppConfig.pricingUrl),
                                child: Text(l.settingsPricing),
                              ),
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () =>
                                        _open(AppConfig.accountDeletionUrl),
                                child: Text(l.settingsDeleteAccount),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l.lockedVerifyCode('PLAT'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 20),
                          InkWell(
                            onTap: busy
                                ? null
                                : () =>
                                    SupportContact.open(screen: 'Активация'),
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    l.settingsSupport,
                                    style:
                                        theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: busy ? 0.38 : 1),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  AppIcon(
                                    AppIcons.siteTelegram,
                                    size: 28,
                                    color:
                                        theme.colorScheme.onSurface.withValues(
                                      alpha: busy ? 0.38 : 0.85,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.plan,
    required this.selected,
    required this.enabled,
    required this.perMonthLabel,
    required this.onTap,
    this.saveLabel,
  });

  final _PayPlan plan;
  final bool selected;
  final bool enabled;
  final String perMonthLabel;
  final String? saveLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = selected
        ? Border.all(color: AppBrand.primary, width: 1.5)
        : Border.all(color: theme.colorScheme.outlineVariant);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppBrand.radiusCard),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppBrand.radiusCard),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppBrand.radiusCard),
            border: border,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              AppIcon(
                selected ? AppIcons.checkCircle : AppIcons.circle,
                size: 22,
                color: selected
                    ? AppBrand.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      perMonthLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (saveLabel != null) ...[
                Container(
                  margin: const EdgeInsets.only(right: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppBrand.inkWithOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    saveLabel!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              Text(
                '${plan.priceRub} ₽',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
