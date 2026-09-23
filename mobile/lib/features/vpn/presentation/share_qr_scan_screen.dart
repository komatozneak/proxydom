import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/hy2_import_store.dart';

/// Camera opens only while this screen is up. The raw code is not logged.
class ShareQrScanScreen extends StatefulWidget {
  const ShareQrScanScreen({super.key});

  @override
  State<ShareQrScanScreen> createState() => _ShareQrScanScreenState();
}

class _ShareQrScanScreenState extends State<ShareQrScanScreen> {
  final _scanner = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  var _handled = false;
  String? _error;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    final raw = capture.barcodes
        .map((code) => code.rawValue?.trim() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (raw.isEmpty) return;
    _handled = true;
    try {
      await Hy2ImportStore.instance.saveInput(raw);
      if (mounted) context.go('/locations');
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _handled = false;
        _error = Localizations.localeOf(context).languageCode == 'ru'
            ? 'В коде нет ссылки'
            : 'No link in this code';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ru = Localizations.localeOf(context).languageCode == 'ru';
    return Scaffold(
      appBar: AppBar(title: Text(ru ? 'QR' : 'QR')),
      body: Stack(
        children: [
          MobileScanner(controller: _scanner, onDetect: _onDetect),
          if (_error != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            ),
        ],
      ),
    );
  }
}
