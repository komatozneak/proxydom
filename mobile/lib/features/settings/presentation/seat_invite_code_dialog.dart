import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/data/seat_code_format.dart';

/// Owner dialog: formatted invite code + QR + copy (ADR 011).
class SeatInviteCodeDialog extends StatelessWidget {
  const SeatInviteCodeDialog({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    final display = formatSeatCodeDisplay(code);
    final link = seatJoinDeepLink(code).toString();
    return AlertDialog(
      title: Text(l.settingsSeatCodeTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(
              display,
              style: theme.textTheme.headlineSmall?.copyWith(
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l.settingsSeatCodeTtl,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ColoredBox(
              color: AppBrand.surfaceElevatedLight,
              child: QrImageView(
                data: link,
                size: 180,
                backgroundColor: AppBrand.surfaceElevatedLight,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: AppBrand.inkLight,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: AppBrand.inkLight,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l.settingsSeatScanHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: display));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.settingsSeatCodeCopied)),
            );
          },
          child: Text(l.recoveryCodeCopy),
        ),
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          child: Text(l.cancel),
        ),
      ],
    );
  }
}
