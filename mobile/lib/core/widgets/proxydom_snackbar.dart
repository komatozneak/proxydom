import 'package:flutter/material.dart';

/// Uniform Proxy Dom toast duration — 2.2s (product standard, not M3 default 4s).
const Duration kProxyDomSnackBarDuration = Duration(milliseconds: 2200);

/// Show a short floating SnackBar with the standard Proxy Dom duration.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showProxyDomSnackBar(
  BuildContext context,
  String message,
) {
  return ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: kProxyDomSnackBarDuration,
    ),
  );
}
