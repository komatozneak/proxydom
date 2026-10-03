import Foundation
import NetworkExtension

/// Packet Tunnel Provider — Hysteria2 dataplane (ADR 018 / 019).
///
/// Honest Connected = tunnel settings applied **and** Hy2 egress started.
/// Without `Hy2bind.xcframework`, start fails closed (never fake Connected).
final class PacketTunnelProvider: NEPacketTunnelProvider {
  private var engine: Hy2TunnelEngine?
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
