# iOS entitlements (ADR 019)

| Target | Bundle ID | Entitlements file |
| --- | --- | --- |
| Runner | `online.teremokconnect.app` | `Runner.entitlements` |
| VpnTunnelProvider | `online.teremokconnect.app.VpnTunnelProvider` | `VpnTunnelProvider/VpnTunnelProvider.entitlements` |

**App Group (both):** `group.online.teremokconnect.app`

**Network Extension:** `packet-tunnel-provider` on both (Runner manages the tunnel; extension runs it).

**Not Personal VPN** (IKEv2) — wrong protocol for Hy2.

Wire `CODE_SIGN_ENTITLEMENTS = Runner.entitlements` in Runner Debug/Release/Profile (already in pbxproj). Packet Tunnel target `VpnTunnelProvider` is in the same Xcode project (entitlements `VpnTunnelProvider/VpnTunnelProvider.entitlements`).

Portal: Identifiers → текущий App ID `online.teremokconnect.app` → enable App Groups + Network Extensions; App ID for the extension bundle `online.teremokconnect.app.VpnTunnelProvider`. Карточка App Store — **Прокси Дом**; её идентификаторы owner задаёт отдельно.
