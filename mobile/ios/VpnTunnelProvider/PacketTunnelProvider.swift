import Foundation
import NetworkExtension

/// Packet Tunnel Provider — Hysteria2 dataplane (ADR 018 / 019).
///
/// Honest Connected = tunnel settings applied **and** Hy2 egress started.
/// Without `Hy2bind.xcframework`, start fails closed (never fake Connected).
final class PacketTunnelProvider: NEPacketTunnelProvider {
  private var engine: Hy2TunnelEngine?

  override func startTunnel(
    options: [String: NSObject]?,
    completionHandler: @escaping (Error?) -> Void
  ) {
    TeremokVpnShared.setStatus("connecting")
    TeremokVpnShared.setLastError(nil)

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
      TeremokVpnShared.setStatus("connected")
      TeremokVpnShared.setLastError(nil)
      completionHandler(nil)
    }
  }

  override func stopTunnel(
    with reason: NEProviderStopReason,
    completionHandler: @escaping () -> Void
  ) {
    NSLog("[Teremok] PacketTunnelProvider.stopTunnel reason=%d", reason.rawValue)
    engine?.stop()
    engine = nil
    TeremokVpnShared.setStatus("idle")
    TeremokVpnShared.setLastError(nil)
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
    TeremokVpnShared.setStatus("idle")
    TeremokVpnShared.setLastError(message)
    completionHandler(
      NSError(
        domain: "online.teremokconnect.app.vpn",
        code: errorCode,
        userInfo: [NSLocalizedDescriptionKey: message]
      )
    )
  }
}
