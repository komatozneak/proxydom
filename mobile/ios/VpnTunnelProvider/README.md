# VpnTunnelProvider (Packet Tunnel)

Network Extension target is in `Runner.xcodeproj` (`VpnTunnelProvider`).

## Once (Apple Developer portal)

1. App ID `online.teremokconnect.app` — Network Extensions + App Groups.
2. App ID `online.teremokconnect.app.VpnTunnelProvider` — same.
3. App Group `group.online.teremokconnect.app` on **both**.
4. App Store provisioning profiles for **both** IDs (CI / TestFlight).

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

Do **not** revive libbox. Do **not** steal utun fd via KVC.
