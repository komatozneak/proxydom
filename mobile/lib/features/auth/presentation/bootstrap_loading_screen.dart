import 'package:flutter/material.dart';

import '../../../core/widgets/app_icon.dart';

/// First-frame UI while anonymous register / token restore is in flight.
///
/// Cold start must not block [runApp] on the network; this screen replaces
/// the static launcher icon until auth resolves.
class BootstrapLoadingScreen extends StatelessWidget {
  const BootstrapLoadingScreen({super.key});

  static const progressKey = Key('bootstrap-loading');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppIcon(AppIcons.house, size: 48),
            const SizedBox(height: 24),
            CircularProgressIndicator(
              key: progressKey,
              color: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}
