import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/data/auth_api.dart';
import '../../session/application/session_provider.dart';
import '../application/account_profile_provider.dart';
import '../data/account_profile.dart';

/// Interactive dialog for linking Telegram to the user's account.
class TelegramLinkDialog extends ConsumerStatefulWidget {
  const TelegramLinkDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const TelegramLinkDialog(),
    );
  }

  @override
  ConsumerState<TelegramLinkDialog> createState() => _TelegramLinkDialogState();
}

/// Prefer the native Telegram app so `start=` is not dropped by the browser.
Uri telegramStartUri({required String botUsername, required String startPayload}) {
  final bot = botUsername.replaceAll('@', '').trim();
  return Uri(
    scheme: 'tg',
    host: 'resolve',
    queryParameters: {'domain': bot, 'start': startPayload},
  );
}

Uri telegramHttpsStartUri({
  required String botUsername,
  required String startPayload,
}) {
  final bot = botUsername.replaceAll('@', '').trim();
  return Uri.https('t.me', bot, {'start': startPayload});
}

({String bot, String start})? parseTelegramDeepLink(String deepLink) {
  final uri = Uri.tryParse(deepLink.trim());
  if (uri == null) return null;
  final start = uri.queryParameters['start']?.trim() ?? '';
  if (start.isEmpty) return null;
  if (uri.scheme == 'tg') {
    final bot = (uri.queryParameters['domain'] ?? '').trim();
    if (bot.isEmpty) return null;
    return (bot: bot, start: start);
  }
  if (uri.host == 't.me' || uri.host == 'telegram.me') {
    final bot = uri.path.replaceAll('/', '').trim();
    if (bot.isEmpty) return null;
    return (bot: bot, start: start);
  }
  return null;
}

class _TelegramLinkDialogState extends ConsumerState<TelegramLinkDialog>
    with WidgetsBindingObserver {
  bool _starting = true;
  bool _linked = false;
  String? _deepLink;
  String? _linkedUsername;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startLink());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_linked && _deepLink != null) {
      _checkStatus();
    }
  }

  Future<void> _startLink() async {
    final existing = ref.read(accountProfileProvider).valueOrNull;
    if (existing != null && existing.telegramUsername != null) {
      setState(() {
        _starting = false;
        _linked = true;
        _linkedUsername = existing.telegramUsername;
        _error = null;
      });
      return;
    }

    setState(() {
      _starting = true;
      _error = null;
    });

    try {
      final link = await AuthApi().startTelegramLink();
      if (!mounted) return;
      setState(() {
        _starting = false;
        _deepLink = link;
      });
      await _openTelegram();
      _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = AppL10n.of(context).accountTelegramStartFailed;
      });
    }
  }

  Future<void> _openTelegram() async {
    if (_deepLink == null) return;
    try {
      final parsed = parseTelegramDeepLink(_deepLink!);
      final uris = <Uri>[];
      if (parsed != null) {
        uris.add(
          telegramStartUri(botUsername: parsed.bot, startPayload: parsed.start),
        );
        uris.add(
          telegramHttpsStartUri(
            botUsername: parsed.bot,
            startPayload: parsed.start,
          ),
        );
      } else {
        uris.add(Uri.parse(_deepLink!));
      }
      for (final uri in uris) {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      }
    } catch (_) {}
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkStatus());
    // Also fire immediately so we don't wait 2s for the first poll.
    unawaited(_checkStatus());
  }

  Future<void> _checkStatus() async {
    if (!mounted) return;
    try {
      // Session snapshot is the SoT; it already carries telegram_username.
      await ref.read(sessionProvider.notifier).refresh();
      final session = ref.read(sessionProvider).valueOrNull;
      if (!mounted) return;
      if (session != null && session.telegramUsername != null) {
        _pollTimer?.cancel();
        final profile = AccountProfile(
          accountId: session.accountId,
          hasAccess: session.hasAccess,
          devicesCount: session.devices.length,
          deviceLimit: session.deviceLimit,
          contactLinked: true,
          hasRecoveryCode: false,
          telegramUsername: session.telegramUsername,
        );
        setState(() {
          _linked = true;
          _linkedUsername = session.telegramUsername;
        });
        unawaited(_refreshAfterLink(profile));
      }
    } catch (_) {}
  }

  Future<void> _refreshAfterLink(AccountProfile profile) async {
    try {
      await ref.read(sessionProvider.notifier).refresh();
    } catch (_) {}
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    ref.read(accountProfileProvider.notifier).state = AsyncData(profile);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final handle = _linkedUsername != null ? '@$_linkedUsername' : 'Telegram';

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBrand.radiusCard),
      ),
      title: Row(
        children: [
          const AppIcon(AppIcons.siteTelegram, size: 24),
          const SizedBox(width: 10),
          Text(l.accountHubLinkTelegram),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_starting) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(),
                ),
              ),
            ] else if (_error != null) ...[
              Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _startLink,
                child: Text(l.homeRetry),
              ),
            ] else if (_linked) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: AppIcon(
                    AppIcons.checkCircleFill,
                    size: 48,
                    color: AppBrand.success,
                  ),
                ),
              ),
              Text(
                '$handle успешно привязан!',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Теперь вы можете управлять подпиской и восстанавливать доступ через Telegram.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Готово'),
              ),
            ] else ...[
              Text(
                l.accountTelegramLead,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        l.accountTelegramWaiting,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _openTelegram,
                icon: const AppIcon(AppIcons.siteTelegram, size: 20),
                label: Text(l.accountTelegramOpenBot),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_linked)
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.cancel),
          ),
      ],
    );
  }
}
