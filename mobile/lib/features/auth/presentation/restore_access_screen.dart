import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router.dart';
import '../../../core/device_info_helper.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../l10n/app_localizations.dart';
import '../../account/application/telegram_identity.dart';
import '../../account/presentation/telegram_link_dialog.dart';
import '../../home/application/vpn_provider.dart';
import '../../session/application/identity_reconnect.dart';
import '../../session/application/session_provider.dart';
import '../application/auth_provider.dart';
import '../application/auth_state.dart';
import '../data/auth_api.dart';
import '../data/restore_device_choice.dart';
import 'restore_device_slot_dialog.dart';

/// Self-serve recover after reinstall (ADR 008 / Telegram link).
class RestoreAccessScreen extends ConsumerStatefulWidget {
  const RestoreAccessScreen({super.key});

  @override
  ConsumerState<RestoreAccessScreen> createState() =>
      _RestoreAccessScreenState();
}

class _RestoreAccessScreenState extends ConsumerState<RestoreAccessScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  bool _tgBusy = false;
  bool _pollInFlight = false;
  int _pollFailures = 0;
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
    if (!telegramIdentityAllowed(ref.read(vpnProvider))) {
      setState(() => _error = AppL10n.of(context).restoreTelegramVpnRequired);
      return;
    }
    setState(() {
      _tgBusy = true;
      _pollFailures = 0;
      _error = null;
    });
    try {
      final auth = ref.read(authProvider).valueOrNull;
      final authed = auth is AuthStateAuthenticated;
      final model = await DeviceInfoHelper.getDeviceModelName();
      final res = authed
          ? await AuthApi().startTelegramLink(deviceName: model)
          : await AuthApi().startTelegramRecover(deviceName: model);
      final deepLink = res['deep_link']!;
      final token = res['token']!;

      await launchTelegramDeepLink(deepLink);

      _pollTimer?.cancel();
      late Future<void> Function(Timer) pollOnce;
      pollOnce = (timer) async {
        if (_pollInFlight) return;
        _pollInFlight = true;
        try {
          final poll = authed
              ? await AuthApi().pollTelegramLink(token)
              : await AuthApi().pollTelegramRecover(token);
          _pollFailures = 0;
          final outcome = TelegramPollOutcome.fromJson(poll);
          if (outcome.status == TelegramPollStatus.needsDeviceSlot) {
            timer.cancel();
            if (!mounted) return;
            final devices = RestoreDeviceChoice.listFrom(poll['devices']);
            final chosen = await RestoreDeviceSlotDialog.show(
              context,
              devices: devices,
            );
            if (!mounted) return;
            if (chosen == null) {
              setState(() {
                _tgBusy = false;
                _error = AppL10n.of(context).restoreDeviceLimitPickFailed;
              });
              return;
            }
            final replaced = authed
                ? await AuthApi().replaceTelegramLink(
                    token: token,
                    deviceId: chosen.id,
                  )
                : await AuthApi().replaceTelegramRecover(
                    token: token,
                    deviceId: chosen.id,
                  );
            final replacement = TelegramPollOutcome.fromJson(replaced);
            if (!replacement.isAccountRestore) {
              setState(() {
                _tgBusy = false;
                _error = telegramPollErrorCopy(
                  AppL10n.of(context),
                  replacement.error,
                );
              });
              return;
            }
            final ok =
                await ref.read(authProvider.notifier).recoverWithTelegram(
                      token: token,
                      data: replaced,
                    );
            if (!mounted) return;
            if (ok) {
              unawaited(reconnectVpnAfterIdentityChange(ref));
              AppRouter.postAuthResolved = true;
              context.go('/gate');
            } else {
              setState(() {
                _tgBusy = false;
                _error = AppL10n.of(context).restoreFailed;
              });
            }
            return;
          }
          if (outcome.isAccountRestore) {
            timer.cancel();
            final ok =
                await ref.read(authProvider.notifier).recoverWithTelegram(
                      token: token,
                      data: poll,
                    );
            if (!mounted) return;
            if (ok) {
              unawaited(reconnectVpnAfterIdentityChange(ref));
              AppRouter.postAuthResolved = true;
              context.go('/gate');
            } else {
              setState(() {
                _tgBusy = false;
                _error = AppL10n.of(context).restoreFailed;
              });
            }
          } else if (outcome.status == TelegramPollStatus.linked) {
            timer.cancel();
            await ref.read(sessionProvider.notifier).refresh();
            if (!mounted) return;
            AppRouter.postAuthResolved = true;
            context.go('/gate');
          } else if (outcome.status == TelegramPollStatus.confirmed) {
            timer.cancel();
            if (!mounted) return;
            setState(() {
              _tgBusy = false;
              _error = AppL10n.of(context).restoreFailed;
            });
          } else if (outcome.status == TelegramPollStatus.failed ||
              outcome.status == TelegramPollStatus.expired) {
            timer.cancel();
            if (!mounted) return;
            setState(() {
              _tgBusy = false;
              _error = telegramPollErrorCopy(
                AppL10n.of(context),
                outcome.error,
              );
            });
          }
        } catch (_) {
          _pollFailures++;
          if (!timer.isActive || _pollFailures >= 3) {
            timer.cancel();
            if (!mounted) return;
            setState(() {
              _tgBusy = false;
              _error = AppL10n.of(context).restoreFailed;
            });
          }
        } finally {
          _pollInFlight = false;
        }
      };
      _pollTimer = Timer.periodic(
        const Duration(seconds: 2),
        (timer) => unawaited(pollOnce(timer)),
      );
      unawaited(pollOnce(_pollTimer!));
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
    try {
      final ok = await ref.read(authProvider.notifier).recoverWithCode(code);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _busy = false;
          _error = AppL10n.of(context).restoreInvalid;
        });
        return;
      }
      unawaited(reconnectVpnAfterIdentityChange(ref));
      AppRouter.postAuthResolved = true;
      context.go('/gate');
    } on NeedsDeviceSlotException catch (e) {
      if (!mounted) return;
      final chosen = await RestoreDeviceSlotDialog.show(
        context,
        devices: e.devices,
      );
      if (!mounted) return;
      if (chosen == null) {
        setState(() {
          _busy = false;
          _error = AppL10n.of(context).restoreDeviceLimitPickFailed;
        });
        return;
      }
      final ok = await ref.read(authProvider.notifier).recoverWithCode(
            code,
            replaceDeviceId: chosen.id,
          );
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _busy = false;
          _error = AppL10n.of(context).restoreFailed;
        });
        return;
      }
      unawaited(reconnectVpnAfterIdentityChange(ref));
      AppRouter.postAuthResolved = true;
      context.go('/gate');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final vpnOk = telegramIdentityAllowed(ref.watch(vpnProvider));
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
                onPressed: (_busy || _tgBusy)
                    ? null
                    : (vpnOk ? _submitTelegram : null),
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
                          const AppIcon(AppIcons.siteTelegram, size: 20),
                          const SizedBox(width: 8),
                          Text(l.restoreTelegramCta),
                        ],
                      ),
              ),
              if (!vpnOk) ...[
                const SizedBox(height: 8),
                Text(
                  l.restoreTelegramVpnRequired,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
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
