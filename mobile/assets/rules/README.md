# Mobile route assets (Xray)

| File | Purpose |
|------|---------|
| `youtube-google.cidr` | Google/YouTube IP ranges → force-proxy in Xray routing |

Legacy sing-box `.srs` rule-sets were removed (ADR 005). Domain/IP geosite data
ships as Android assets `geosite.dat` / `geoip.dat` under
`android/app/src/main/assets/` for libXray.
