import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../application/account_profile_provider.dart';

/// Email bind: start OTP → verify → refresh hub.
class EmailLinkScreen extends ConsumerStatefulWidget {
  const EmailLinkScreen({super.key});

  @override
  ConsumerState<EmailLinkScreen> createState() => _EmailLinkScreenState();
}

class _EmailLinkScreenState extends ConsumerState<EmailLinkScreen> {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  String? _token;
  String? _debugCode;
  String? _error;
  bool _sending = false;
  bool _verifying = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final l = AppL10n.of(context);
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = l.accountEmailInvalid);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result = await ref.read(accountApiProvider).startEmailLink(email);
      if (!mounted) return;
      setState(() {
        _sending = false;
        _token = result.token;
        _debugCode = result.debugCode;
        if (result.debugCode != null && _codeCtrl.text.isEmpty) {
          _codeCtrl.text = result.debugCode!;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = l.accountEmailSendFailed;
      });
    }
  }

  Future<void> _verify() async {
    final l = AppL10n.of(context);
    final token = _token;
    final code = _codeCtrl.text.trim();
    if (token == null || token.isEmpty || code.isEmpty) {
      setState(() => _error = l.accountEmailCodeRequired);
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await ref.read(accountApiProvider).verifyEmailLink(token: token, code: code);
      await ref.read(accountProfileProvider.notifier).refresh();
      if (!mounted) return;
      context.pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = l.accountEmailVerifyFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final awaitingCode = _token != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.accountHubLinkEmail),
        leading: IconButton(
          icon: const AppIcon(AppIcons.back, size: 22),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            l.accountEmailLead,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _emailCtrl,
            enabled: !awaitingCode,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(
              labelText: l.accountEmailLabel,
              border: const OutlineInputBorder(),
            ),
          ),
          if (!awaitingCode) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _sending ? null : _send,
              child: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l.accountEmailSendCode),
            ),
          ] else ...[
            const SizedBox(height: 16),
            TextField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l.accountEmailCodeLabel,
                border: const OutlineInputBorder(),
                helperText: _debugCode != null ? l.accountEmailDebugHint : null,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _verifying ? null : _verify,
              child: _verifying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l.accountEmailVerify),
            ),
            TextButton(
              onPressed: _sending
                  ? null
                  : () {
                      setState(() {
                        _token = null;
                        _debugCode = null;
                        _codeCtrl.clear();
                      });
                    },
              child: Text(l.accountEmailChangeAddress),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
