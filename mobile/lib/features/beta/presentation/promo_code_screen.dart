import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../application/beta_providers.dart';
import '../data/beta_redeem_outcome.dart';

/// Promo code entry — after Flash Call, only when server advertises the gate.
class PromoCodeScreen extends ConsumerStatefulWidget {
  const PromoCodeScreen({super.key});

  @override
  ConsumerState<PromoCodeScreen> createState() => _PromoCodeScreenState();
}

class _PromoCodeScreenState extends ConsumerState<PromoCodeScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _messageFor(BetaRedeemOutcomeCode code, AppL10n l) => switch (code) {
        BetaRedeemOutcomeCode.invalid => l.promoOutcomeInvalid,
        BetaRedeemOutcomeCode.expired => l.promoOutcomeExpired,
        BetaRedeemOutcomeCode.exhausted => l.promoOutcomeExhausted,
        BetaRedeemOutcomeCode.revoked => l.promoOutcomeRevoked,
        BetaRedeemOutcomeCode.rateLimited => l.promoOutcomeRateLimited,
        BetaRedeemOutcomeCode.unknown => l.promoOutcomeUnknown,
        _ => l.promoOutcomeUnknown,
      };

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty) {
      setState(() => _error = AppL10n.of(context).promoCodeEmpty);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await ref.read(betaApiProvider).redeem(code);
      if (!mounted) return;
      if (result.outcome.isSuccess) {
        AppRouter.postAuthResolved = true;
        context.go('/onboarding');
        return;
      }
      setState(() {
        _error = _messageFor(result.outcome, AppL10n.of(context));
        _submitting = false;
      });
      _focus.requestFocus();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = AppL10n.of(context).promoOutcomeUnknown;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    color: AppBrand.secondary.withOpacity(0.15),
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
                  color: theme.colorScheme.onSurface.withOpacity(0.75),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _controller,
                focusNode: _focus,
                enabled: !_submitting,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l.promoCodeLabel,
                  hintText: l.promoCodeHint,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l.promoSubmit),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
