import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/router.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../application/auth_provider.dart';
import '../application/auth_state.dart';
import '../data/auth_api.dart';

/// Self-serve recover after reinstall (ADR 008 / Telegram link).
class RestoreAccessScreen extends ConsumerStatefulWidget {
  const RestoreAccessScreen({super.key});

  @override
  ConsumerState<RestoreAccessScreen> createState() => _RestoreAccessScreenState();
}

class _RestoreAccessScreenState extends ConsumerState<RestoreAccessScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  bool _tgBusy = false;
  String? _error;
  Timer? _pollTimer;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _goBack() {
    _pollTimer?.cancel();
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

  Future<void> _submitTelegram() async {
    setState(() {
      _tgBusy = true;
      _error = null;
    });
    try {
      final res = await AuthApi().startTelegramRecover();
      final deepLink = res['deep_link']!;
      final token = res['token']!;

      final uri = Uri.parse(deepLink);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }

      // Start polling status
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
        try {
          final poll = await AuthApi().pollTelegramRecover(token);
          final status = poll['status'];
          if (status == 'confirmed') {
            timer.cancel();
            final ok = await ref.read(authProvider.notifier).recoverWithTelegram(
                  token: token,
                  data: poll,
                );
            if (!mounted) return;
            if (ok) {
              AppRouter.postAuthResolved = true;
              context.go('/gate');
            } else {
              setState(() {
                _tgBusy = false;
                _error = AppL10n.of(context).restoreFailed;
              });
            }
          } else if (status == 'failed' || status == 'expired') {
            timer.cancel();
            if (!mounted) return;
            setState(() {
              _tgBusy = false;
              _error = poll['error'] ?? AppL10n.of(context).restoreFailed;
            });
          }
        } catch (_) {}
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tgBusy = false;
        _error = AppL10n.of(context).restoreFailed;
      });
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
              OutlinedButton(
                onPressed: (_busy || _tgBusy) ? null : _submitTelegram,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: _tgBusy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const AppIcon(AppIcons.info, size: 20),
                          const SizedBox(width: 8),
                          Text(l.accountHubLinkTelegram),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: (_busy || _tgBusy) ? null : _submit,
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
