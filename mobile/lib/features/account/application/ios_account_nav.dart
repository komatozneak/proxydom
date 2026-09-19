import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router.dart';
import '../../../core/widgets/teremok_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../../home/application/vpn_provider.dart';
import '../../session/application/session_provider.dart';
import '../presentation/telegram_link_dialog.dart';
import 'account_profile_provider.dart';
import 'telegram_identity.dart';

/// iOS Path A: VPN + Telegram bot `/start` (profile), never in-app pay.
///
/// No tunnel → snackbar. Already bound → open the bot. Unbound → bind
/// dialog (reconnect + bot after a fresh link).
Future<void> openIosPremiumAccountPath(
  BuildContext context,
  WidgetRef ref,
) =>
    openIosTelegramBotStartPath(context, ref);

/// Same soft `/start` as Home/Account — not `start=tariffs`.
Future<void> openIosAdvancedFeaturesPath(
  BuildContext context,
  WidgetRef ref,
) =>
    openIosTelegramBotStartPath(context, ref);

Future<void> openIosTelegramBotStartPath(
  BuildContext context,
  WidgetRef ref,
) async {
  final l = AppL10n.of(context);
  if (!telegramIdentityAllowed(ref.read(vpnProvider))) {
    showTeremokSnackBar(context, l.accountTelegramVpnRequired);
    return;
  }

  if (_telegramAlreadyBound(ref)) {
    await launchTelegramBotStart();
    return;
  }

  final result = await TelegramLinkDialog.show(context);
  if (!context.mounted) return;
  if (result == TelegramLinkDialogResult.restored) {
    AppRouter.postAuthResolved = true;
    context.go('/gate');
    return;
  }
  if (result == TelegramLinkDialogResult.linked) {
    await ref.read(accountProfileProvider.notifier).refresh();
  }
}

bool _telegramAlreadyBound(WidgetRef ref) {
  final session = ref.read(sessionProvider).valueOrNull;
  if (session?.telegramUsername != null) return true;
  return ref.read(accountProfileProvider).valueOrNull?.contactLinked ?? false;
}
