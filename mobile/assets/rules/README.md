# Mobile route assets

| File | Purpose |
|------|---------|
| `youtube-google.cidr` | Google/YouTube IP ranges, one CIDR per line |

Prefix list of public Google ranges, refreshed by
`mobile/scripts/fetch-goog-cidrs.ps1`. Declared in `pubspec.yaml` and parsed by
`mobile/lib/features/vpn/data/youtube_google_cidrs.dart`.

## No live consumer

The parser's only caller was the Xray routing builder in
`mobile/lib/features/vpn/data/engine_config_builder.dart`, which the engine swap
left without a caller.

The live split-tunnel path is `SplitTunnelPrefs` plus `vpn_route_policy.dart`,
driven from `vpn_controller.dart`. It works in domain suffixes and disallowed
packages, not in IP ranges — so this list is not applied to the tunnel today.

Legacy sing-box `.srs` rule-sets were removed earlier, with the same engine swap.
