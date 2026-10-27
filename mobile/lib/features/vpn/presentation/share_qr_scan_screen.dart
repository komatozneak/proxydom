import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/diagnostics/ui_log.dart';
import '../../../core/theme.dart';
import '../../../core/toasts/proxy_dom_toast.dart';
import '../../../core/widgets/app_icon.dart';

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
  var _torch = false;
  String? _error;

  Future<void> _toggleTorch() async {
    try {
      await _scanner.toggleTorch();
      if (mounted) setState(() => _torch = !_torch);
    } catch (_) {
      // A device without a torch simply keeps the button inert.
    }
  }

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
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _scanner, onDetect: _onDetect),
          // A viewfinder, not a bare camera: without a frame the screen gives
          // no clue what to point at.
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white70, width: 2),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null) ...[
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                ],
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.qrHint,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      IconButton(
                        onPressed: _toggleTorch,
                        tooltip: l.qrTorch,
                        icon: AppIcon(
                          AppIcons.flashlight,
                          color: _torch ? AppBrand.mascotGold : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
