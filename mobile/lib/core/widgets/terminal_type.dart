import 'package:flutter/material.dart';

/// The app's instrument voice, in one place.
///
/// The home head runs on it, the import screen numbers its steps on it, and the
/// servers tab wears it on its headings, its facts and its protocol tag. It was
/// a private method inside the home widget, so every other screen that needed
/// the same voice either copied it or fell back to the app font — and a screen
/// that sets its numbers in a different face than the screen next to it reads as
/// a different app.
///
/// A real monospace, bundled: JetBrains Mono has native Cyrillic, which the
/// platform's `monospace` does not promise and which showed up as tofu on a
/// machine with no mono installed. Everything else is Onest.
TextStyle terminalText(
  BuildContext context, {
  required double size,
  required Color color,
  double weight = 600,
  double spacing = 1.1,
}) {
  return TextStyle(
    fontFamily: 'JetBrainsMono',
    fontFamilyFallback: const ['Onest', 'Inter'],
    fontSize: size,
    fontWeight: weight >= 700 ? FontWeight.w700 : FontWeight.w400,
    color: color,
    letterSpacing: spacing,
    height: 1.2,
  );
}
