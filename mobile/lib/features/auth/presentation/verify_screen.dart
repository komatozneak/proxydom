import 'package:flutter/material.dart';
import 'package:teremok_connect/l10n/app_localizations.dart';

class VerifyScreen extends StatelessWidget {
  const VerifyScreen({super.key, required this.phone});

  final String phone;

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.verifyTitle)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.dialpad, size: 64),
            const SizedBox(height: 16),
            Text(
              '${l.verifySentTo}\n$phone',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            const Text('(Пин-пад — в шаге 7)'),
          ],
        ),
      ),
    );
  }
}