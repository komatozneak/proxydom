import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/teremok_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_provider.dart';
import '../../auth/data/seat_outcome.dart';
import '../presentation/seat_invite_code_dialog.dart';

/// Mint a seat code and show QR / copy dialog (owner, from Devices).
Future<void> runSeatInviteFlow({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  final l = AppL10n.of(context);
  try {
    final outcome = await ref.read(authProvider.notifier).makeSeatCode();
    if (!context.mounted) return;
    if (outcome is SeatMakePremiumRequired) {
      showTeremokSnackBar(context, l.settingsSeatPremiumRequired);
      return;
    }
    if (outcome is! SeatMakeOk) {
      showTeremokSnackBar(context, l.settingsSeatInviteFailed);
      return;
    }
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => SeatInviteCodeDialog(code: outcome.code),
    );
  } catch (e, st) {
    debugPrint('runSeatInviteFlow.error: $e\n$st');
    if (!context.mounted) return;
    showTeremokSnackBar(context, l.settingsSeatInviteFailed);
  }
}
