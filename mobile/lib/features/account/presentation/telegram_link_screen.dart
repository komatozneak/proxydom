import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/app_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../application/account_profile_provider.dart';

/// Telegram bind: start → open bot deep link → poll /me until linked.
class TelegramLinkScreen extends ConsumerStatefulWidget {
  const TelegramLinkScreen({super.key});

  @override
  ConsumerState<TelegramLinkScreen> createState() => _TelegramLinkScreenState();
}

class _TelegramLinkScreenState extends ConsumerState<TelegramLinkScreen> {
  String? _error;
  bool _starting = false;
  bool _waiting = false;
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final l = AppL10n.of(context);
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final result = await ref.read(accountApiProvider).startTelegramLink();
      if (!mounted) return;
      if (result.deepLink.isEmpty) {
        setState(() {
          _starting = false;
          _error = l.accountTelegramStartFailed;
        });
        return;
      }
      final uri = Uri.tryParse(result.deepLink);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      setState(() {
        _starting = false;
        _waiting = true;
      });
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _checkLinked());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = l.accountTelegramStartFailed;
      });
    }
  }

  Future<void> _checkLinked() async {
    try {
      final profile = await ref.read(accountApiProvider).fetchMe();
      if (!mounted) return;
      if (profile.contactLinked) {
        _poll?.cancel();
        await ref.read(accountProfileProvider.notifier).refresh();
        if (!mounted) return;
        context.pop();
      }
    } catch (_) {
      // keep polling
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.accountHubLinkTelegram),
        leading: IconButton(
          icon: const AppIcon(AppIcons.back, size: 22),
          onPressed: () => context.pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.accountTelegramLead,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _starting || _waiting ? null : _start,
              child: _starting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _waiting
                          ? l.accountTelegramWaiting
                          : l.accountTelegramOpenBot,
                    ),
            ),
            if (_waiting) ...[
              const SizedBox(height: 16),
              Text(
                l.accountTelegramWaitingHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
