import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/teremok_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../../beta/data/jwt_subject.dart';
import '../../onboarding/data/onboarding_prefs.dart';
import '../application/auth_provider.dart';
import '../application/auth_state.dart';
import '../data/recovery_code_storage.dart';

/// Mandatory backup-code screen after first unlock (pay or promo).
///
/// User must confirm they saved the code before continuing.
/// [viewOnly] is Settings → Account: show/copy without wiping the archive.
class RecoveryCodeScreen extends ConsumerStatefulWidget {
  const RecoveryCodeScreen({super.key, this.code, this.viewOnly = false});

  final String? code;
  final bool viewOnly;

  @override
  ConsumerState<RecoveryCodeScreen> createState() => _RecoveryCodeScreenState();
}

class _RecoveryCodeScreenState extends ConsumerState<RecoveryCodeScreen> {
  bool _confirmed = false;
  bool _busy = false;
  String? _archived;

  String get _code {
    final passed = widget.code?.trim() ?? '';
    if (passed.isNotEmpty) return passed;
    if (widget.viewOnly) return (_archived ?? '').trim();
    return (AppRouter.pendingRecoveryCode ?? '').trim();
  }

  @override
  void initState() {
    super.initState();
    if (widget.viewOnly) {
      unawaited(_loadArchived());
    }
  }

  Future<void> _loadArchived() async {
    final code = await RecoveryCodeStorage.instance.readArchived();
    if (!mounted) return;
    setState(() => _archived = code);
  }

  Future<void> _copy() async {
    final code = _code;
    if (code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    showTeremokSnackBar(context, AppL10n.of(context).recoveryCodeCopied);
  }

  Future<void> _continue() async {
    if (!_confirmed || _code.isEmpty) return;
    setState(() => _busy = true);
    AppRouter.pendingRecoveryCode = null;
    await RecoveryCodeStorage.instance.markShown();
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
    final missing = widget.viewOnly && code.isEmpty;

    return PopScope(
      canPop: widget.viewOnly,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.recoveryCodeTitle),
          automaticallyImplyLeading: widget.viewOnly,
          leading: widget.viewOnly
              ? IconButton(
                  icon: const AppIcon(AppIcons.back, size: 22),
                  onPressed: () => context.pop(),
                )
              : null,
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
                  missing ? l.accountHubRecoveryMissing : l.recoveryCodeBody,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (!missing)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 20,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: AppBrand.secondary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SelectableText(
                      code,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                if (!missing) ...[
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: _copy,
                    child: Text(l.recoveryCodeCopy),
                  ),
                ],
                const Spacer(),
                if (!widget.viewOnly) ...[
                  CheckboxListTile(
                    value: _confirmed,
                    onChanged: (v) => setState(() => _confirmed = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    title: Text(l.recoveryCodeConfirm),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: (_confirmed && !_busy && code.isNotEmpty)
                        ? _continue
                        : null,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l.recoveryCodeContinue),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
