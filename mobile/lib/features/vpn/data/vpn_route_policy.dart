// Single source of truth for runtime route feature flags (Xray-core / ADR 005).
//
// Ads policy: curated auction hosts via TLS sniff when [kXrayAdsBlockEnabled]
// is true. Огонь `geosite:category-ads-all` stays experimental
// ([kXrayOgonAdsAllEnabled]). Mid-roll SSAI on `googlevideo.com` is not
// removable via VPN routing. Default both OFF during speed benches; tests may
// force ON via RoutePolicy.

/// Curated-list ads reject (no FakeDNS). OFF by default — sniffing collateral.
const bool kXrayAdsBlockEnabled = false;

/// Legacy alias for callers still using the sing-box-era name.
const bool kAdsBlockEnabled = kXrayAdsBlockEnabled;

/// Огонь FakeDNS + `geosite:category-ads-all`. Prod stays OFF.
const bool kXrayOgonAdsAllEnabled = false;

/// Exact/suffix hosts eligible for `ads-reject` when [kXrayAdsBlockEnabled] is true.
/// Auction/tracker only — never video CDN (`googlevideo.com`, `gvt1.com`, …).
const kXrayAdsBlockDomains = <String>[
  'doubleclick.net',
  'googleadservices.com',
  'googlesyndication.com',
  'adservice.google.com',
  'ads.youtube.com',
  'pagead2.googlesyndication.com',
];

/// geoip:ru → direct (nest home-speed). Domain geosite alone misses IP-literals.
const bool kGeoipRuEnabled = true;

/// Smart-mode RU geosite → direct («Что работает без VPN?» bundle).
const bool kSmartRuSplitEnabled = true;

/// Hev → SOCKS bridge A/B. Default gVisor `protocol:tun` + setTunFd.
const bool kUseHevTunBridge = false;

/// Domains that must use proxy **before** RU geosite directs.
/// Media CDN (`googlevideo`, `gvt*`) stays here — RF DPI / TSPU, not split-tunnel.
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

/// Extra hosts only needed when ads reject is on (player bootstrap).
const kAdsRejectBypassSuffixes = <String>[
  ...kSmartProxyForceSuffixes,
  'doubleclick.net',
  'googleadservices.com',
  'googlesyndication.com',
];
