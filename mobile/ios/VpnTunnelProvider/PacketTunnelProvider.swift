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
    sessionGeneration = TeremokVpnShared.currentGeneration()
    TeremokVpnShared.setStatus("connecting", generation: sessionGeneration)
    TeremokVpnShared.setLastError(nil, generation: sessionGeneration)

    guard let paramsJson = TeremokVpnShared.defaults?.string(forKey: TeremokVpnShared.paramsKey),
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
      if let error {
        self.finishStart(
          errorCode: (error as NSError).code,
          message: error.localizedDescription,
          completionHandler: completionHandler
        )
        return
      }
      TeremokVpnShared.setStatus("connected", generation: self.sessionGeneration)
      TeremokVpnShared.setLastError(nil, generation: self.sessionGeneration)
      completionHandler(nil)
    }
  }

  override func stopTunnel(
    with reason: NEProviderStopReason,
    completionHandler: @escaping () -> Void
  ) {
    NSLog(
      "[Teremok] PacketTunnelProvider.stopTunnel reason=%d gen=%d",
      reason.rawValue,
      sessionGeneration
    )
    engine?.stop()
    engine = nil
    // Only clear if this session still owns App Group (not a newer start).
    TeremokVpnShared.setStatus("idle", generation: sessionGeneration)
    TeremokVpnShared.setLastError(nil, generation: sessionGeneration)
    completionHandler()
  }

  private func finishStart(
    errorCode: Int,
    message: String,
    completionHandler: @escaping (Error?) -> Void
  ) {
    NSLog("[Teremok] PacketTunnelProvider start failed: %@", message)
    engine?.stop()
    engine = nil
    TeremokVpnShared.setStatus("idle", generation: sessionGeneration)
    TeremokVpnShared.setLastError(message, generation: sessionGeneration)
    completionHandler(
      NSError(
        domain: "online.teremokconnect.app.vpn",
        code: errorCode,
        userInfo: [NSLocalizedDescriptionKey: message]
      )
    )
  }
}
