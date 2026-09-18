import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config.dart';
import '../../../core/router.dart';
import '../../../core/widgets/teremok_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../../home/application/vpn_provider.dart';
import '../presentation/telegram_link_dialog.dart';
import 'account_profile_provider.dart';
import 'telegram_identity.dart';

/// iOS first-purchase path: bind Telegram on this JWT if VPN is up, else Account.
/// Never `/promo` (not a paywall). No pay CTA.
Future<void> openIosPremiumAccountPath(
  BuildContext context,
  WidgetRef ref,
) async {
  final vpnOk = telegramIdentityAllowed(ref.read(vpnProvider));
  if (vpnOk) {
    final result = await TelegramLinkDialog.show(context);
    if (!context.mounted) return;
    if (result == TelegramLinkDialogResult.restored) {
      AppRouter.postAuthResolved = true;
      context.go('/gate');
    }
    return;
  }
  if (context.mounted) {
    context.push('/settings/account');
  }
}

/// iOS Path A: open Telegram bot tariffs (`start=tariffs`).
///
/// Requires VPN (RF). If Telegram is not linked on this JWT, bind first, then
/// open tariffs. Bot also shows tariffs after a successful `link_` bind.
Future<void> openIosAdvancedFeaturesPath(
  BuildContext context,
  WidgetRef ref,
) async {
  final l = AppL10n.of(context);
  if (!telegramIdentityAllowed(ref.read(vpnProvider))) {
    showTeremokSnackBar(context, l.accountTelegramVpnRequired);
    return;
  }

  var linked =
      ref.read(accountProfileProvider).valueOrNull?.contactLinked ?? false;
  if (!linked) {
    final result = await TelegramLinkDialog.show(context);
    if (!context.mounted) return;
    if (result == null) return;
    if (result == TelegramLinkDialogResult.restored) {
      AppRouter.postAuthResolved = true;
      context.go('/gate');
    }
    linked = true;
    await ref.read(accountProfileProvider.notifier).refresh();
  }

  if (!context.mounted) return;
  final deepLink = telegramHttpsStartUri(
    botUsername: AppConfig.telegramBotUsername,
    startPayload: 'tariffs',
  ).toString();
  await launchTelegramDeepLink(deepLink);
}
