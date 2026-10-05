import 'package:flutter/material.dart';

/// Uniform Proxy Dom toast duration — 2.2s (product standard, not M3 default 4s).
const Duration kProxyDomSnackBarDuration = Duration(milliseconds: 2200);

/// Show a short floating SnackBar with the standard Proxy Dom duration.
///
/// [bottomInset] keeps the toast off the controls underneath it. Every page
/// that owns a key bar pins it to the bottom edge, and a toast at the bottom of
/// the same Scaffold lands square on those keys: for as long as the answer is up,
/// the key that asked the question cannot be pressed again — and the second
/// press of a two-second window goes nowhere, which reads as a dead button.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showProxyDomSnackBar(
  BuildContext context,
  String message, {
  double bottomInset = 0,
}) {
  return ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: kProxyDomSnackBarDuration,
      // Floating is what makes [margin] count; a fixed toast is laid out over
      // the bottom of the body whatever this says.
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.fromLTRB(16, 0, 16, bottomInset),
    ),
  );
}