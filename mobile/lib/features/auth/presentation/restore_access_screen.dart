import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../application/auth_provider.dart';
import '../application/auth_state.dart';

/// Self-serve recover after reinstall (ADR 008).
class RestoreAccessScreen extends ConsumerStatefulWidget {
  const RestoreAccessScreen({super.key});

  @override
  ConsumerState<RestoreAccessScreen> createState() => _RestoreAccessScreenState();
}

class _RestoreAccessScreenState extends ConsumerState<RestoreAccessScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    final auth = ref.read(authProvider).valueOrNull;
    if (auth is AuthStateBootstrapFailed) {
      context.go('/bootstrap-failed');
    } else if (auth is AuthStateAuthenticated) {
      context.go('/settings');
    } else {
      context.go('/home');
    }
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty) {
      setState(() => _error = AppL10n.of(context).restoreCodeEmpty);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await ref.read(authProvider.notifier).recoverWithCode(code);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = AppL10n.of(context).restoreInvalid;
      });
      return;
    }
    AppRouter.postAuthResolved = true;
    context.go('/gate');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.restoreTitle),
        leading: IconButton(
          tooltip: l.navBack,
          icon: AppIcon(
            AppIcons.backBold,
            size: 28,
            color: theme.colorScheme.onSurface,
          ),
          onPressed: _busy ? null : _goBack,
        ),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.restoreHeadlineCode, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              Text(
                l.restoreBodyCode,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                enabled: !_busy,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: l.restoreCodeLabel,
                  hintText: l.restoreCodeHint,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-]')),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const Spacer(),
              FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppBrand.secondary,
                  minimumSize: const Size.fromHeight(48),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l.restoreSubmit),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
