# VpnTunnelProvider (Packet Tunnel)

Network Extension target is in `Runner.xcodeproj` (`VpnTunnelProvider`).

## Once (Apple Developer portal)

1. App ID `su.proxydom.app` — Network Extensions (Packet Tunnel) + App Groups.
2. App ID `su.proxydom.app.VpnTunnelProvider` — same.
3. App Group `group.su.proxydom.app` on **both**.
4. App Store provisioning profiles for **both** IDs — CI creates them via
   `app-store-connect fetch-signing-files --strict-match-identifier`, вручную не нужны.

Team `LG3N5WA9TD`; App Store seller — ТОО «УМИКУМ» (`UMICUM LLP`). Скриншот-порядок
и проверка: `docs/ops/apple-org-umicum-runbook.md` §4.

## Hy2bind.xcframework (required to link)

Not in git. On Mac or GitHub Actions:

```bash
cd mobile/android/hysteria-bind
bash build-ios.sh
```

Writes `mobile/ios/Frameworks/Hy2bind.xcframework`. The **app** embeds it
(`Runner.app/Frameworks`); the extension **links** it and loads via
`@executable_path/../../Frameworks`. Do not nest Hy2bind inside the appex
(App Store: "disallowed nested bundles").

Until the xcframework exists, Xcode/CI cannot finish the VpnTunnelProvider link.

## Honest Connected

`setTunnelNetworkSettings` (default IPv4 route, DNS 1.1.1.1/8.8.8.8, `tunnelRemoteAddress` = Hy2 node IP) **and** `Hy2bind.Start` **and** `StartPacketTun` **and** `packetFlow` pump. Not SOCKS-only.

**Sites split (ADR 025):** Flutter sends exact custom then catalog host groups.
They are resolved at tunnel start to prioritized IPv4 `/32` and IPv6 `/128`
**`excludedRoutes`** (after reserved Hy2 endpoint + API master excludes).
**Never** put `direct_domain_suffixes` into `Hy2bindStart` on iOS. Reconnect
applies list changes. Do **not** set `includeAllNetworks` here (XOR with hard
kill switch).

Do **not** revive libbox. Do **not** steal utun fd via KVC.
