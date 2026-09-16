import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router.dart';
import '../../home/application/vpn_provider.dart';
import '../presentation/telegram_link_dialog.dart';
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
