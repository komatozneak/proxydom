import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// Seat-code entry dialog that owns its [TextEditingController] lifecycle.
///
/// Disposing the controller from the parent after [showDialog] returns races
/// IME/focus teardown and throws "used after being disposed".
class SeatCodeEntryDialog extends StatefulWidget {
  const SeatCodeEntryDialog({super.key});

  @override
  State<SeatCodeEntryDialog> createState() => _SeatCodeEntryDialogState();
}

class _SeatCodeEntryDialogState extends State<SeatCodeEntryDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context, rootNavigator: true).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    return AlertDialog(
      title: Text(l.settingsAcceptSeat),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: l.settingsSeatCodeTitle,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l.settingsAcceptSeat),
        ),
      ],
    );
  }
}
