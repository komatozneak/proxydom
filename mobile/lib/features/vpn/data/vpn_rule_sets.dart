import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Flutter asset → on-disk paths for sing-box `rule_set` type=local.
///
/// 2026-07-14: GitHub blocked in RF — remote `.srs` with `download_detour:direct`
/// dies at connect. Ship rule-sets inside the APK and never fetch at runtime.
const kRuleSetAssets = <String, String>{
  'geosite-category-ru': 'assets/rules/geosite-category-ru.srs',
  'geosite-tld-ru': 'assets/rules/geosite-tld-ru.srs',
  'geoip-ru': 'assets/rules/geoip-ru.srs',
  'geosite-category-ads-all': 'assets/rules/geosite-category-ads-all.srs',
};

/// Tags shipped for smart-mode RU split (domain + legacy geoip asset).
const kRuRuleSetTags = <String>{
  'geosite-category-ru',
  'geosite-tld-ru',
  'geoip-ru',
};

/// Domain-only RU tags wired into route (geoip-ru dropped — CDN IP false positives).
const kRuDomainRuleSetTags = <String>{
  'geosite-category-ru',
  'geosite-tld-ru',
};

/// Tag for embedded ads reject list.
const kAdsRuleSetTag = 'geosite-category-ads-all';

/// Copy APK assets into `files/sing-box/rules/` (libbox working tree).
///
/// Returns absolute paths keyed by rule-set tag.
Future<Map<String, String>> prepareLocalRuleSetPaths() async {
  // Aligns with SingBoxBridge: Context.filesDir/sing-box/rules
  final base = await getApplicationSupportDirectory();
  final rulesDir = Directory(p.join(base.path, 'sing-box', 'rules'));
  await rulesDir.create(recursive: true);

  final out = <String, String>{};
  for (final entry in kRuleSetAssets.entries) {
    final dest = File(p.join(rulesDir.path, '${entry.key}.srs'));
    final data = await rootBundle.load(entry.value);
    await dest.writeAsBytes(
      data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      ),
      flush: true,
    );
    out[entry.key] = dest.path;
  }
  return out;
}
