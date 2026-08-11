import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../application/beta_providers.dart';
import '../data/beta_redeem_outcome.dart';

/// Shared promo code field + submit — single redeem logic for Account / gate / locked.
class PromoRedeemForm extends ConsumerStatefulWidget {
  const PromoRedeemForm({
    super.key,
    required this.onSuccess,
    this.enabled = true,
    this.useTonalButton = false,
    this.buttonStyle,
    this.textFieldContentPadding,
  });

  final Future<void> Function() onSuccess;
  final bool enabled;
  final bool useTonalButton;
  final ButtonStyle? buttonStyle;
  final EdgeInsetsGeometry? textFieldContentPadding;

  @override
  ConsumerState<PromoRedeemForm> createState() => _PromoRedeemFormState();
}

class _PromoRedeemFormState extends ConsumerState<PromoRedeemForm> {
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
    if (!widget.enabled || _submitting) return;
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
      if (result.outcome.isSuccess && result.hasAccess) {
        await widget.onSuccess();
        return;
      }
      setState(() {
        _error = result.outcome.isSuccess && !result.hasAccess
            ? AppL10n.of(context).promoOutcomeUnknown
            : _messageFor(result.outcome, AppL10n.of(context));
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
    final busy = _submitting || !widget.enabled;
    final defaultStyle = FilledButton.styleFrom(
      backgroundColor: widget.useTonalButton ? null : AppBrand.secondary,
    );
    final button = widget.useTonalButton
        ? FilledButton.tonal(
            style: widget.buttonStyle ?? defaultStyle,
            onPressed: busy ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l.promoSubmit),
          )
        : FilledButton(
            style: widget.buttonStyle ?? defaultStyle,
            onPressed: busy ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l.promoSubmit),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focus,
          enabled: !busy,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: l.promoCodeLabel,
            hintText: l.promoCodeHint,
            border: const OutlineInputBorder(),
            contentPadding: widget.textFieldContentPadding,
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
        button,
      ],
    );
  }
}
