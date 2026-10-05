import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/diagnostics/ui_log.dart';
import '../../../core/toasts/proxy_dom_toast.dart';

import '../../../l10n/app_localizations.dart';
import '../../home/application/vpn_provider.dart';
import '../../home/application/vpn_status.dart';
import '../data/hy2_import_store.dart';

/// Camera opens only while this screen is up. The raw code is not logged.
class ShareQrScanScreen extends ConsumerStatefulWidget {
  const ShareQrScanScreen({super.key});

  @override
  ConsumerState<ShareQrScanScreen> createState() => _ShareQrScanScreenState();
}

class _ShareQrScanScreenState extends ConsumerState<ShareQrScanScreen> {
  final _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
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
    UiLog.action('scan', 'code', extra: {'chars': raw.length});
    try {
      await Hy2ImportStore.instance.saveInput(raw);
      if (!mounted) return;
      showProxyDomToast(
        AppL10n.of(context).freeServerAdded,
        tone: ToastTone.success,
      );
      final status = ref.read(vpnProvider);
      if (status is VpnConnected || status is VpnConnecting) {
        await ref.read(vpnProvider.notifier).disconnect(reason: 'import');
      }
      if (!mounted) return;
      context.go('/home');
    } on FormatException {
      UiLog.action('scan', 'code', result: 'bad');
      if (!mounted) return;
      setState(() {
        _handled = false;
        _error = AppL10n.of(context).freeLinkInvalid;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.freeQr)),
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
