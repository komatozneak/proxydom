// Single source of truth for the Hy2 site-split force-proxy list.
//
// YouTube and Google must not fall through to the RU-direct final: the TSPU
// resets those routes, so they are forced onto the tunnel rather than split out.
// The same list is mirrored in `mobile/android/hysteria-bind/hy2bind_split.go`.

/// Domains that must use the tunnel.
///
/// Media CDN (`googlevideo`, `gvt*`) is here because RF DPI and the TSPU break
/// it, not because of split-tunnel policy.
const kSmartProxyForceSuffixes = <String>[
  'youtube.com',
  'youtu.be',
  'youtube-nocookie.com',
  'youtubekids.com',
  'googlevideo.com',
  'ytimg.com',
  'ggpht.com',
  'googleapis.com',
  'gstatic.com',
  'googleusercontent.com',
  'gvt1.com',
  'gvt2.com',
  'gvt3.com',
  'video.google.com',
  'play.google.com',
  'widevine.com',
  'withyoutube.com',
  'google.com',
];

bool isSmartForceProxyHost(String host) {
  final h = host.trim().toLowerCase();
  if (h.isEmpty) return false;
  for (final raw in kSmartProxyForceSuffixes) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) continue;
    if (h == s || h.endsWith('.$s')) return true;
  }
  return false;
}

/// Hy2 site-split input: drop YouTube/Google force-proxy suffixes.
List<String> stripForceProxySuffixes(Iterable<String> raw) {
  final out = <String>{};
  for (final item in raw) {
    final s = item.trim().toLowerCase();
    if (s.isEmpty || isSmartForceProxyHost(s)) continue;
    out.add(s);
  }
  return out.toList()..sort();
}
