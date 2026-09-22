import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config.dart';
import '../../../core/router.dart';
import '../../../core/widgets/teremok_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../../home/application/vpn_provider.dart';
import '../../session/application/session_provider.dart';
import '../presentation/telegram_link_dialog.dart';
import 'account_profile_provider.dart';
import 'telegram_identity.dart';

/// iOS Path A: VPN + Telegram cashier (`start=tariffs`), never in-app pay.
///
/// No tunnel → snackbar. Already bound → open tariffs. Unbound → bind
/// dialog (backend sends tariffs after a fresh link).
Future<void> openIosPremiumAccountPath(
  BuildContext context,
  WidgetRef ref,
) =>
    openIosTelegramBotTariffsPath(context, ref);

/// Soft `/start` (profile) — not `start=tariffs`.
Future<void> openIosAdvancedFeaturesPath(
  BuildContext context,
  WidgetRef ref,
) =>
    openIosTelegramBotStartPath(context, ref);

Future<void> openIosTelegramBotTariffsPath(
  BuildContext context,
  WidgetRef ref,
) =>
    openIosTelegramBotStartPath(context, ref, startPayload: 'tariffs');

Future<void> openIosTelegramBotStartPath(
  BuildContext context,
  WidgetRef ref, {
  String? startPayload,
}) async {
  final l = AppL10n.of(context);
  if (!telegramIdentityAllowed(ref.read(vpnProvider))) {
    showTeremokSnackBar(context, l.accountTelegramVpnRequired);
    return;
  }

  if (_telegramAlreadyBound(ref)) {
    await launchTelegramDeepLink(
      telegramHttpsStartUri(
        botUsername: AppConfig.telegramBotUsername,
        startPayload: startPayload,
      ).toString(),
    );
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
  if (session != null &&
      (session.contactLinked || session.telegramUsername != null)) {
    return true;
  }
  return ref.read(accountProfileProvider).valueOrNull?.contactLinked ?? false;
}
