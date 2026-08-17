import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// Rename dialog that owns its [TextEditingController] lifecycle.
///
/// Disposing the controller from the parent after [showDialog] returns races
/// IME/focus teardown (`_dependents.isEmpty` in [Element.unmount]).
class RenameDeviceDialog extends StatefulWidget {
  const RenameDeviceDialog({super.key, required this.initial});

  final String initial;

  @override
  State<RenameDeviceDialog> createState() => _RenameDeviceDialogState();
}

class _RenameDeviceDialogState extends State<RenameDeviceDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _pop([String? value]) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context, rootNavigator: true).pop(value);
  }

  void _submit() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) return;
    _pop(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    return AlertDialog(
      title: Text(l.devicesRenameTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 128,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: l.devicesRenameHint,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: _pop,
          child: Text(l.devicesCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l.devicesRenameSave),
        ),
      ],
    );
  }
}
