import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/widgets/app_icon.dart';

/// One launcher app from native [listLauncherApps].
class LauncherAppInfo {
  const LauncherAppInfo({
    required this.packageName,
    required this.label,
    this.iconPng,
  });

  final String packageName;
  final String label;

  /// PNG bytes from PackageManager (null when [includeIcons] was false).
  final Uint8List? iconPng;

  factory LauncherAppInfo.fromMap(Map<dynamic, dynamic> map) {
    Uint8List? icon;
    final raw = map['iconPng'];
    if (raw is Uint8List) {
      icon = raw;
    } else if (raw is List<int>) {
      icon = Uint8List.fromList(raw);
    } else if (raw is List) {
      icon = Uint8List.fromList(raw.cast<int>());
    }
    return LauncherAppInfo(
      packageName: '${map['packageName'] ?? ''}',
      label: '${map['label'] ?? ''}',
      iconPng: icon,
    );
  }
}

/// Pure counter for Home «Что работает без VPN?» row.
({int enabled, int total}) noVpnAppsCounter({
  required Iterable<String> launcherPackages,
  required Set<String> disallowedPackages,
}) {
  final pkgs = launcherPackages
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toSet();
  final enabled = disallowedPackages.where(pkgs.contains).length;
  return (enabled: enabled, total: pkgs.length);
}

/// Known package ids for Sites «Основные» — only VK uses launcher logo.
const kOsnovnyeIconPackages = <String, List<String>>{
  'vk': ['com.vkontakte.android', 'com.vk.android'],
};

Uint8List? iconForOsnovnyeCategory(
  String categoryId,
  Map<String, Uint8List> iconsByPackage,
) {
  final pkgs = kOsnovnyeIconPackages[categoryId];
  if (pkgs == null) return null;
  for (final p in pkgs) {
    final icon = iconsByPackage[p];
    if (icon != null && icon.isNotEmpty) return icon;
  }
  return null;
}

/// Phosphor glyph for «Основные» rows. Null for [vk] (launcher PNG / badge).
IconData? osnovnyeCategoryIcon(String categoryId) {
  return switch (categoryId) {
    'ru' => AppIcons.osnovnyeRu,
    'gov' => AppIcons.osnovnyeGov,
    'tiktok' => AppIcons.osnovnyeTiktok,
    'yandex' => AppIcons.osnovnyeYandex,
    'ozon' => AppIcons.osnovnyeOzon,
    'wb' => AppIcons.osnovnyeWb,
    _ => null,
  };
}

/// Android MethodChannel helper for split-tunnel Apps tab.
class InstalledAppsChannel {
  InstalledAppsChannel._();

  static const _channel = MethodChannel('teremok/vpn');

  static Future<List<LauncherAppInfo>> listLauncherApps({
    bool includeIcons = true,
  }) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'listLauncherApps',
        {'includeIcons': includeIcons},
      );
      if (raw == null) return const [];
      return raw
          .whereType<Map>()
          .map((e) => LauncherAppInfo.fromMap(e))
          .where((a) => a.packageName.isNotEmpty)
          .toList();
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }
}
