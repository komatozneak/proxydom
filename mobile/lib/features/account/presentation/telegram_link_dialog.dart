import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/device_info_helper.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_provider.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/data/restore_device_choice.dart';
import '../../auth/presentation/restore_device_slot_dialog.dart';
import '../../session/application/identity_reconnect.dart';
import '../../session/application/session_provider.dart';

/// Interactive dialog for linking Telegram to the user's account.
class TelegramLinkDialog extends ConsumerStatefulWidget {
  const TelegramLinkDialog({super.key});

  static Future<TelegramLinkDialogResult?> show(BuildContext context) {
    return showDialog<TelegramLinkDialogResult>(
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

Future<void> launchTelegramDeepLink(String deepLink) async {
  final parsed = parseTelegramDeepLink(deepLink);
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
    uris.add(Uri.parse(deepLink));
  }
  for (final uri in uris) {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
  }
}

/// Result of the Telegram identity dialog.
enum TelegramLinkDialogResult { linked, restored }

class _TelegramLinkDialogState extends ConsumerState<TelegramLinkDialog>
    with WidgetsBindingObserver {
  bool _starting = true;
  bool _linked = false;
  bool _restored = false;
  String? _deepLink;
  String? _token;
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
    final existing = ref.read(sessionProvider).valueOrNull;
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
      final model = await DeviceInfoHelper.getDeviceModelName();
      final started = await AuthApi().startTelegramLink(deviceName: model);
      if (!mounted) return;
      setState(() {
        _starting = false;
        _deepLink = started['deep_link'];
        _token = started['token'];
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
      await launchTelegramDeepLink(_deepLink!);
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
      if (_token != null) {
        final poll = await AuthApi().pollTelegramLink(_token!);
        final status = poll['status'];
        if (status == 'needs_device_slot') {
          _pollTimer?.cancel();
          final devices = RestoreDeviceChoice.listFrom(poll['devices']);
          if (!mounted) return;
          final chosen = await RestoreDeviceSlotDialog.show(
            context,
            devices: devices,
          );
          if (!mounted) return;
          if (chosen == null) {
            setState(() {
              _error = AppL10n.of(context).restoreDeviceLimitPickFailed;
            });
            return;
          }
          final replaced = await AuthApi().replaceTelegramLink(
            token: _token!,
            deviceId: chosen.id,
          );
          if (replaced['status'] != 'confirmed') {
            if (!mounted) return;
            setState(() {
              _error = AppL10n.of(context).restoreFailed;
            });
            return;
          }
          final ok = await ref.read(authProvider.notifier).recoverWithTelegram(
                token: _token!,
                data: replaced,
              );
          if (!mounted) return;
          if (ok) {
            unawaited(reconnectVpnAfterIdentityChange(ref));
            setState(() {
              _linked = true;
              _restored = true;
            });
          } else {
            setState(() {
              _error = AppL10n.of(context).restoreFailed;
            });
          }
          return;
        }
        if (status == 'confirmed') {
          _pollTimer?.cancel();
          final ok = await ref.read(authProvider.notifier).recoverWithTelegram(
                token: _token!,
                data: poll,
              );
          if (!mounted) return;
          if (ok) {
            unawaited(reconnectVpnAfterIdentityChange(ref));
            setState(() {
              _linked = true;
              _restored = true;
            });
          }
          return;
        }
        if (status == 'linked') {
          _pollTimer?.cancel();
          await ref.read(sessionProvider.notifier).refresh();
          if (!mounted) return;
          final session = ref.read(sessionProvider).valueOrNull;
          setState(() {
            _linked = true;
            _linkedUsername = session?.telegramUsername;
          });
          return;
        }
        if (status == 'failed' || status == 'expired') {
          _pollTimer?.cancel();
          if (!mounted) return;
          setState(() {
            _error = AppL10n.of(context).accountTelegramStartFailed;
          });
          return;
        }
      }
      await ref.read(sessionProvider.notifier).refresh();
      final session = ref.read(sessionProvider).valueOrNull;
      if (!mounted) return;
      if (session != null && session.telegramUsername != null) {
        _pollTimer?.cancel();
        setState(() {
          _linked = true;
          _linkedUsername = session.telegramUsername;
        });
      }
    } catch (_) {}
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
                onPressed: () => Navigator.of(context).pop(
                  _restored
                      ? TelegramLinkDialogResult.restored
                      : TelegramLinkDialogResult.linked,
                ),
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
