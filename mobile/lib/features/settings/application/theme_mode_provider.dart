import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/theme_mode_prefs.dart';

/// App-wide theme preference (persisted). Default: follow system.
final themeModeProvider =
    AsyncNotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() => ThemeModePrefs.read();

  Future<void> setMode(ThemeMode mode) async {
    state = AsyncData(mode);
    await ThemeModePrefs.write(mode);
  }
}
