import 'package:flutter/material.dart';

/// Uniform Teremok toast duration — 2.2s (product standard, not M3 default 4s).
const Duration kTeremokSnackBarDuration = Duration(milliseconds: 2200);

/// Show a short floating SnackBar with the standard Teremok duration.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showTeremokSnackBar(
  BuildContext context,
  String message,
) {
  return ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: kTeremokSnackBarDuration,
    ),
  );
}
