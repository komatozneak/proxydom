import Foundation
import NetworkExtension

/// Packet Tunnel Provider.
///
/// Two engines share one provider: Hysteria2 (`Hy2TunnelEngine`) and the
/// v2ray-core family (`ShareTunnelEngine`), chosen by the `vpnCore` field the
/// Dart side already writes into the start document. Both report Connected only
/// after their dataplane is up, so a core that started and carried nothing is
/// never shown as working.
final class PacketTunnelProvider: NEPacketTunnelProvider {
  private var engine: Hy2TunnelEngine?
  private var shareEngine: ShareTunnelEngine?
  /// Captured at startTunnel — late stop must not clobber a newer session.
  private var sessionGeneration: Int = 0

  override func startTunnel(
    options: [String: NSObject]?,
    completionHandler: @escaping (Error?) -> Void
  ) {
    sessionGeneration = ProxyDomVpnShared.currentGeneration()
    ProxyDomVpnShared.appendNativeLog(
      "PacketTunnel.startTunnel gen=\(sessionGeneration)"
    )
    ProxyDomVpnShared.setStatus("connecting", generation: sessionGeneration)
    ProxyDomVpnShared.setLastError(nil, generation: sessionGeneration)

    guard let paramsJson = ProxyDomVpnShared.defaults?.string(forKey: ProxyDomVpnShared.paramsKey),
          !paramsJson.isEmpty
    else {
      finishStart(
        errorCode: 2,
        message: "missing Hy2 params in App Group",
        completionHandler: completionHandler
      )
      return
    }

    let hy2 = Hy2TunnelEngine()
    engine = hy2

    if PacketTunnelProvider.isShareSession(paramsJson) {
      // The v2ray family rides the same framework but needs the userspace
      // packet tun: iOS has no TUN fd, so the fd-based start cannot run here.
      let share = ShareTunnelEngine()
      shareEngine = share
      engine = nil
      share.start(
        provider: self,
        paramsJson: paramsJson
      ) { [weak self] error in
        guard let self else { return }
        guard self.shareEngine === share else {
          ProxyDomVpnShared.appendNativeLog(
            "PacketTunnel.startCompletion stale gen=\(self.sessionGeneration)"
          )
          completionHandler(
            error ?? NSError(
              domain: "su.proxydom.app.vpn",
              code: 6,
              userInfo: [NSLocalizedDescriptionKey: "share start cancelled"]
            )
          )
          return
        }
        if let error {
          let nsError = error as NSError
          self.finishStart(
            errorCode: nsError.code,
            message: error.localizedDescription,
            completionHandler: completionHandler
          )
          return
        }
        ProxyDomVpnShared.appendNativeLog(
          "PacketTunnel.connected kind=share gen=\(self.sessionGeneration)"
        )
        ProxyDomVpnShared.setStatus("connected", generation: self.sessionGeneration)
        ProxyDomVpnShared.setLastError(nil, generation: self.sessionGeneration)
        completionHandler(nil)
      }
      return
    }

    hy2.start(
      provider: self,
      paramsJson: paramsJson
    ) { [weak self] error in
      guard let self else { return }
      guard self.engine === hy2 else {
        // stopTunnel or a newer start owns the provider now.
        ProxyDomVpnShared.appendNativeLog(
          "PacketTunnel.startCompletion stale gen=\(self.sessionGeneration)"
        )
        completionHandler(
          error ?? NSError(
            domain: "su.proxydom.app.vpn",
            code: 6,
            userInfo: [NSLocalizedDescriptionKey: "Hy2 start cancelled"]
          )
        )
        return
      }
      if let error {
        let nsError = error as NSError
        self.finishStart(
          errorCode: nsError.code,
          message: error.localizedDescription,
          completionHandler: completionHandler
        )
        return
      }
      ProxyDomVpnShared.appendNativeLog(
        "PacketTunnel.connected gen=\(self.sessionGeneration)"
      )
      ProxyDomVpnShared.setStatus("connected", generation: self.sessionGeneration)
      ProxyDomVpnShared.setLastError(nil, generation: self.sessionGeneration)
      completionHandler(nil)
    }
  }

  override func stopTunnel(
    with reason: NEProviderStopReason,
    completionHandler: @escaping () -> Void
  ) {
    if TunnelStopIntent.clearsSessionActive(reason) {
      ProxyDomVpnShared.setSessionActive(false)
    }
    let reasonTag = "nevpn_\(reason.rawValue)"
    ProxyDomVpnShared.setLastStopReason(reasonTag)
    ProxyDomVpnShared.appendNativeLog(
      "PacketTunnel.stopTunnel reason=\(reason.rawValue) gen=\(sessionGeneration)"
    )
    NSLog(
      "[ProxyDom] PacketTunnelProvider.stopTunnel reason=%d gen=%d",
      reason.rawValue,
      sessionGeneration
    )
    engine?.stop()
    engine = nil
    shareEngine?.stop()
    shareEngine = nil
    ProxyDomVpnShared.setStatus("idle", generation: sessionGeneration)
    ProxyDomVpnShared.setLastError(nil, generation: sessionGeneration)
    completionHandler()
  }

  override func handleAppMessage(
    _ messageData: Data,
    completionHandler: ((Data?) -> Void)?
  ) {
    guard let completionHandler else { return }
    let cmd = String(data: messageData, encoding: .utf8) ?? ""
    if cmd == "health" || cmd.hasPrefix("health") {
      if let live = engine?.healthJSON() {
        completionHandler(live.data(using: .utf8))
        return
      }
      let persisted = ProxyDomVpnShared.lastTunnelHealth()
      completionHandler(persisted.data(using: .utf8))
      return
    }
    completionHandler(nil)
  }

  /// Whether the start document asks for the v2ray-core family.
  ///
  /// `vpnCore` is the field Dart has always written; `vlessConfig` is the
  /// document itself. Requiring both keeps a Hysteria2 start from being handed
  /// to an engine that would only find an empty config.
  private static func isShareSession(_ paramsJson: String) -> Bool {
    guard
      let data = paramsJson.data(using: .utf8),
      let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let core = root["vpnCore"] as? String,
      core == "vless",
      let document = root["vlessConfig"] as? String
    else {
      return false
    }
    return !document.isEmpty
  }

  private func finishStart(
    errorCode: Int,
    message: String,
    completionHandler: @escaping (Error?) -> Void
  ) {
    ProxyDomVpnShared.appendNativeLog(
      "PacketTunnel.startFailed code=\(errorCode) msg=\(message)"
    )
    NSLog("[ProxyDom] PacketTunnelProvider start failed: %@", message)
    engine?.stop()
    engine = nil
    shareEngine?.stop()
    shareEngine = nil
    ProxyDomVpnShared.setStatus("idle", generation: sessionGeneration)
    ProxyDomVpnShared.setLastError(message, generation: sessionGeneration)
    completionHandler(
      NSError(
        domain: "su.proxydom.app.vpn",
        code: errorCode,
        userInfo: [NSLocalizedDescriptionKey: message]
      )
    )
  }
}
