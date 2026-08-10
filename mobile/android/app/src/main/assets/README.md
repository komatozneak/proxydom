# Android Xray assets (ADR 005)

| File | Purpose |
|------|---------|
| `geosite.dat` | Domain categories (`geosite:category-ru`, `tld-ru`, …) — smart mode |
| `geoip.dat` | IP lists — nest MVP does **not** emit `geoip:ru` (full-proxy) |

Copied at runtime into app files dir by `XrayBridge` (`datDir` for libXray).

**Routing (2026-08-09 home-speed):** FakeDNS **OFF**. Packet path is VpnService
TUN → `LibXray.setTunFd` / `protocol:tun` (gVisor). Google/YouTube force-proxy
via `assets/rules/youtube-google.cidr` + domain suffixes; nest `geoip:ru →
direct`; `quic-reject` UDP/443.

**Ads:** curated OFF during speed bench (`kXrayAdsBlockEnabled = false`).
Re-enable curated after YT play ≤10s. `kXrayOgonAdsAllEnabled` stays **false**.
Mid-roll SSAI on `googlevideo.com` is not removable via VPN.

**Pin:** client uses libXray **26.6.27** — keep geosite/geoip compatible with
that core (loyalsoldier / v2fly dat). Refresh with marker bump in
`XrayBridge.copyAssetIfNeeded`.

Source note (2026-08-08): loyalsoldier dat (`category-ru`, `tld-ru` verified).
