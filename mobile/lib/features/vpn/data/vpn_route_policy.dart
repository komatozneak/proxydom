// Normalization for the direct-domain list a user builds in «Маршрутизация».
//
// No list of blocked sites ships with the app. The default policy is the one
// the product promises: LAN and the user's own suffixes stay direct, everything
// else goes through the selected node. A subscription may add force-proxy
// rules at sync time; those are applied by the engine, not hardcoded here.

/// Trim, lowercase and de-duplicate user-entered suffixes.
List<String> normalizeRouteSuffixes(Iterable<String> raw) {
  final out = <String>{};
  for (final item in raw) {
    final s = item.trim().toLowerCase();
    if (s.isEmpty) continue;
    out.add(s);
  }
  return out.toList()..sort();
}
