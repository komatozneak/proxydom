import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/router.dart';
import '../../../core/support_contact.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../billing/data/billing_api.dart';
import 'promo_redeem_form.dart';

/// Activation paywall: welcome + Platega plans + promo (no intermediate CTA).
class LockedAccessScreen extends ConsumerStatefulWidget {
  const LockedAccessScreen({super.key});

  @override
  ConsumerState<LockedAccessScreen> createState() => _LockedAccessScreenState();
}

class _LockedAccessScreenState extends ConsumerState<LockedAccessScreen> {
  bool _payBusy = false;
  String? _error;

  void _goAfterUnlock() {
    AppRouter.postAuthResolved = true;
    context.go('/onboarding');
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
              context.go('/gate');
            },
            child: Text(l.lockedPayReturnCheck),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final busy = _payBusy;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.72);
    final buttonStyle = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    );
    final outlinedStyle = OutlinedButton.styleFrom(
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Material(
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
                        const SizedBox(height: 32),
                        FilledButton(
                          style: buttonStyle,
                          onPressed: busy ? null : () => _pay('1m'),
                          child: Text(l.lockedPay1m),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton(
                          style: outlinedStyle,
                          onPressed: busy ? null : () => _pay('3m'),
                          child: Text(l.lockedPay3m),
                        ),
                        const SizedBox(height: 28),
                        if (_error != null) ...[
                          Text(
                            _error!,
                            style: TextStyle(
                              color: theme.colorScheme.error,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: Divider(
                                color: theme.colorScheme.outline
                                    .withValues(alpha: 0.55),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              child: Text(
                                l.lockedOrPromo,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: muted,
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
                        const SizedBox(height: 22),
                        PromoRedeemForm(
                          enabled: !busy,
                          useTonalButton: true,
                          buttonStyle: buttonStyle,
                          textFieldContentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 18,
                          ),
                          onSuccess: () async {
                            if (mounted) _goAfterUnlock();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Center(
                child: InkWell(
                  onTap: busy
                      ? null
                      : () => SupportContact.open(screen: 'Активация'),
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
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: busy ? 0.38 : 1),
                          ),
                        ),
                        const SizedBox(height: 10),
                        AppIcon(
                          AppIcons.siteTelegram,
                          size: 28,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: busy ? 0.38 : 0.85),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
