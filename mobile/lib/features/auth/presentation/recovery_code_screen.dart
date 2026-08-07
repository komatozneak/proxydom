import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router.dart';
import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../beta/data/jwt_subject.dart';
import '../../onboarding/data/onboarding_prefs.dart';
import '../application/auth_provider.dart';
import '../application/auth_state.dart';

/// Mandatory backup-code screen after first unlock (pay or promo).
///
/// User must confirm they saved the code before continuing.
class RecoveryCodeScreen extends ConsumerStatefulWidget {
  const RecoveryCodeScreen({super.key, this.code});

  final String? code;

  @override
  ConsumerState<RecoveryCodeScreen> createState() => _RecoveryCodeScreenState();
}

class _RecoveryCodeScreenState extends ConsumerState<RecoveryCodeScreen> {
  bool _confirmed = false;
  bool _busy = false;

  String get _code =>
      widget.code?.trim().isNotEmpty == true
          ? widget.code!.trim()
          : (AppRouter.pendingRecoveryCode ?? '');

  Future<void> _copy() async {
    final code = _code;
    if (code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppL10n.of(context).recoveryCodeCopied)),
    );
  }

  Future<void> _continue() async {
    if (!_confirmed || _code.isEmpty) return;
    setState(() => _busy = true);
    AppRouter.pendingRecoveryCode = null;
    final auth = ref.read(authProvider).valueOrNull;
    final userId = auth is AuthStateAuthenticated
        ? (jwtSubject(auth.accessToken) ?? 'unknown')
        : 'unknown';
    final done = await OnboardingPrefs.isCompleted(userId: userId);
    AppRouter.postAuthResolved = true;
    if (!mounted) return;
    context.go(done ? '/home' : '/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final code = _code;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.recoveryCodeTitle),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.recoveryCodeHeadline,
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  l.recoveryCodeBody,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.75),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppBrand.secondary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    code.isEmpty ? '—' : code,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: code.isEmpty ? null : _copy,
                  child: Text(l.recoveryCodeCopy),
                ),
                const Spacer(),
                CheckboxListTile(
                  value: _confirmed,
                  onChanged: (v) => setState(() => _confirmed = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.recoveryCodeConfirm),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed:
                      (_confirmed && !_busy && code.isNotEmpty) ? _continue : null,
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l.recoveryCodeContinue),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
