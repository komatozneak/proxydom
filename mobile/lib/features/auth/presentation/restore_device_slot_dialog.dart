import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../data/restore_device_choice.dart';

/// Mullvad-style picker: which occupied slot to revoke so this phone can join.
class RestoreDeviceSlotDialog extends StatelessWidget {
  const RestoreDeviceSlotDialog({super.key, required this.devices});

  final List<RestoreDeviceChoice> devices;

  static Future<RestoreDeviceChoice?> show(
    BuildContext context, {
    required List<RestoreDeviceChoice> devices,
  }) {
    return showDialog<RestoreDeviceChoice>(
      context: context,
      barrierDismissible: true,
      builder: (context) => RestoreDeviceSlotDialog(devices: devices),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppBrand.radiusCard),
      ),
      title: Text(l.restoreDeviceLimitTitle),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.restoreDeviceLimitBody, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: devices.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final device = devices[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(device.name),
                    subtitle: device.isOwner
                        ? Text(l.restoreDeviceLimitOwner)
                        : null,
                    onTap: () => Navigator.of(context).pop(device),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
      ],
    );
  }
}
