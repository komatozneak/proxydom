import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ios_store_gates.dart';

/// Phone: camera scan. Windows has no camera and does not show a QR.
Future<void> openFreeClientCapture(BuildContext context) async {
  if (windowsDesktop) return;
  context.push('/scan');
}
