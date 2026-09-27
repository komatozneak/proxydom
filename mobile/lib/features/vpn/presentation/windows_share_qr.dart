import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/ios_store_gates.dart';
import '../../../core/widgets/teremok_snackbar.dart';
import '../../../l10n/app_localizations.dart';
import '../data/hy2_import_store.dart';

/// Phone: camera scan. Windows: a QR of the saved lines, no camera (ADR 029).
Future<void> openFreeClientCapture(BuildContext context) async {
  if (!windowsDesktop) {
    context.push('/scan');
    return;
  }
  final catalogs = await Hy2ImportStore.instance.catalogs();
  final text = catalogs.expand((catalog) => catalog.lines).join('\n');
  if (!context.mounted) return;
  final l = AppL10n.of(context);
  if (text.isEmpty) {
    showTeremokSnackBar(context, l.freeNoProfile);
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(l.freeQr),
        content: SizedBox(
          width: 240,
          child: QrImageView(data: text, size: 240),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Share.share(text);
            },
            child: Text(l.freePaste),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(MaterialLocalizations.of(dialogContext).closeButtonLabel),
          ),
        ],
      );
    },
  );
}
