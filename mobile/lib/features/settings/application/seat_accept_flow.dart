import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/teremok_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/auth_provider.dart';
import '../../auth/data/seat_outcome.dart';
import '../../session/application/identity_reconnect.dart';
import '../presentation/seat_code_entry_dialog.dart';
import 'devices_list_provider.dart';

/// Dialog + consent + accept + snackbar. Used from Devices (and deep link).
Future<void> runSeatAcceptFlow({
  required BuildContext context,
  required WidgetRef ref,
  String? initialCode,
}) async {
  final l = AppL10n.of(context);
  final code = initialCode?.trim().isNotEmpty == true
      ? initialCode!.trim()
      : await showDialog<String>(
          context: context,
          useRootNavigator: true,
          builder: (_) => SeatCodeEntryDialog(initialCode: initialCode),
        );
  if (!context.mounted || code == null || code.isEmpty) return;

  final consented = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => AlertDialog(
      title: Text(l.seatAcceptConsentTitle),
      content: Text(l.seatAcceptConsentBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false),
          child: Text(l.devicesCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
          child: Text(l.seatAcceptConsentConfirm),
        ),
      ],
    ),
  );
  if (!context.mounted || consented != true) return;

  final outcome = await ref.read(authProvider.notifier).acceptSeatCode(code);
  if (!context.mounted) return;
  if (outcome == SeatAcceptOutcome.ok) {
    await teardownVpnAfterIdentityChange(ref);
    await ref.read(devicesListProvider.notifier).refresh();
    if (!context.mounted) return;
  }
  final message = switch (outcome) {
    SeatAcceptOutcome.ok => l.settingsAcceptSeatOk,
    SeatAcceptOutcome.notFound => l.settingsSeatCodeNotFound,
    SeatAcceptOutcome.limit => l.settingsSeatDeviceLimit,
    SeatAcceptOutcome.ownCode => l.settingsSeatOwnCode,
    SeatAcceptOutcome.premiumRequired => l.settingsSeatPremiumRequired,
    SeatAcceptOutcome.failed => l.settingsSeatAcceptFailed,
  };
  showTeremokSnackBar(context, message);
}
