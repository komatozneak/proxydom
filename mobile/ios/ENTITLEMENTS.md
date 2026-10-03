# iOS entitlements (ADR 019)

| Target | Bundle ID | Entitlements file |
| --- | --- | --- |
| Runner | `su.proxydom.app` | `Runner.entitlements` |
| VpnTunnelProvider | `su.proxydom.app.VpnTunnelProvider` | `VpnTunnelProvider/VpnTunnelProvider.entitlements` |
| RunnerTests | `su.proxydom.app.RunnerTests` | — |

**App Group (both):** `group.su.proxydom.app`

**Network Extension:** `packet-tunnel-provider` on both (Runner manages the tunnel; extension runs it).

**Not Personal VPN** (IKEv2) — wrong protocol for Hy2.

Wire `CODE_SIGN_ENTITLEMENTS = Runner.entitlements` in Runner Debug/Release/Profile (already in pbxproj). Packet Tunnel target `VpnTunnelProvider` is in the same Xcode project (entitlements `VpnTunnelProvider/VpnTunnelProvider.entitlements`).

Portal: Identifiers → App ID `su.proxydom.app` → enable App Groups + Network Extensions; App ID for the extension bundle `su.proxydom.app.VpnTunnelProvider`. App Group `group.su.proxydom.app` must be attached to **both** App IDs. Team `LG3N5WA9TD`, App Store seller — ТОО «УМИКУМ» (`UMICUM LLP`).

Прежние идентификаторы заброшенного проекта не используем. Порядок создания и проверка — `docs/ops/apple-org-umicum-runbook.md` §4.
