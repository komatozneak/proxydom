/// Single source of truth for runtime route feature flags.
///
/// Pixel 2026-08: ads geosite reject blackholes browsing while urlTest is
/// healthy; geoip-ru misclassifies Google/YouTube CDN → direct → RF DPI death.
/// Keep both OFF in production; tests may override via [RoutePolicy].
const bool kAdsBlockEnabled = false;

/// geoip-ru asset may ship in APK but must not enter route rules while OFF.
const bool kGeoipRuEnabled = false;

/// Smart-mode RU geosite → direct. Re-enabled after H-RU rejected (no-ru
/// full-proxy still left YT video spinning — RU was not the video blocker).
const bool kSmartRuSplitEnabled = true;

/// Domains that must use proxy in smart mode **before** RU geosite directs.
/// Includes media/CDN hosts so UI+previews work but Onesie/video can still
/// hang if any edge slips to direct under RF DPI.
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
  'google.com',
];

/// Extra hosts only needed when ads reject is on (player bootstrap).
const kAdsRejectBypassSuffixes = <String>[
  ...kSmartProxyForceSuffixes,
  'doubleclick.net',
  'googleadservices.com',
  'googlesyndication.com',
];
