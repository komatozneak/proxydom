import Foundation
import NetworkExtension

#if canImport(Hy2bind)
import Hy2bind
#endif

/// Hysteria2 engine inside the Packet Tunnel (ADR 019).
///
/// Honest Connected = `setTunnelNetworkSettings` + Hy2 `Start` + packet tun
/// + `packetFlow` pump. SOCKS-only is never Connected.
final class Hy2TunnelEngine: NSObject {
  private weak var provider: NEPacketTunnelProvider?
  private var pumping = false
  private let mtu = 1280

  func start(
    provider: NEPacketTunnelProvider,
    paramsJson: String,
    completion: @escaping (Error?) -> Void
  ) {
    self.provider = provider
    #if canImport(Hy2bind)
    guard let cfg = Hy2StartConfig.parse(paramsJson) else {
      completion(Self.err(2, "invalid Hy2 paramsJson"))
      return
    }
    let settings = Self.networkSettings(
      remoteHost: cfg.remoteHost,
      mtu: mtu
    )
    provider.setTunnelNetworkSettings(settings) { [weak self] error in
      guard let self else { return }
      if let error {
        completion(error)
        return
      }
      Hy2bind.setPacketWriter(self)
      let startErr = Hy2bind.start(cfg.goJSON)
      if !startErr.isEmpty {
        completion(Self.err(4, startErr))
        return
      }
      let tunErr = Hy2bind.startPacketTun(self.mtu)
      if !tunErr.isEmpty {
        Hy2bind.stop()
        completion(Self.err(5, tunErr))
        return
      }
      self.pumping = true
      self.pumpInbound()
      completion(nil)
    }
    #else
    _ = paramsJson
    completion(
      Self.err(
        1,
        "Hy2bind.xcframework not linked — CI/Mac: bash mobile/android/hysteria-bind/build-ios.sh"
      )
    )
    #endif
  }

  func stop() {
    pumping = false
    #if canImport(Hy2bind)
    Hy2bind.setPacketWriter(nil)
    Hy2bind.stop()
    #endif
    provider = nil
  }

  private func pumpInbound() {
    guard pumping, let flow = provider?.packetFlow else { return }
    flow.readPackets { [weak self] packets, _ in
      guard let self, self.pumping else { return }
      #if canImport(Hy2bind)
      for packet in packets where !packet.isEmpty {
        let injectErr = Hy2bind.injectPacket(packet)
        if !injectErr.isEmpty {
          NSLog("[Teremok] injectPacket: %@", injectErr)
        }
      }
      #endif
      self.pumpInbound()
    }
  }

  static func networkSettings(remoteHost: String, mtu: Int) -> NEPacketTunnelNetworkSettings {
    let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: remoteHost)
    let ipv4 = NEIPv4Settings(
      addresses: ["10.255.255.1"],
      subnetMasks: ["255.255.255.252"]
    )
    ipv4.includedRoutes = [NEIPv4Route.default()]
    settings.ipv4Settings = ipv4
    settings.mtu = NSNumber(value: mtu)
    let dns = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
    settings.dnsSettings = dns
    return settings
  }

  private static func err(_ code: Int, _ message: String) -> NSError {
    NSError(
      domain: "online.teremokconnect.app.vpn",
      code: code,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}

#if canImport(Hy2bind)
extension Hy2TunnelEngine: Hy2bindPacketWriter {
  func writePacket(_ packet: Data?) throws {
    guard let packet, !packet.isEmpty, let provider else { return }
    let proto: NSNumber
    if (packet[packet.startIndex] >> 4) == 6 {
      proto = NSNumber(value: AF_INET6)
    } else {
      proto = NSNumber(value: AF_INET)
    }
    provider.packetFlow.writePackets([packet], withProtocols: [proto])
  }
}
#endif

/// Maps Flutter `paramsJson` (same keys as Android) to hy2bind Start JSON.
struct Hy2StartConfig {
  var remoteHost: String
  var goJSON: String

  static func parse(_ paramsJson: String) -> Hy2StartConfig? {
    guard
      let data = paramsJson.data(using: .utf8),
      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }
    let server = (obj["hysteriaServer"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let auth = (obj["hysteriaAuth"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if server.isEmpty || auth.isEmpty { return nil }
    let sni = (obj["hysteriaSni"] as? String) ?? ""
    let socks = (obj["hysteriaSocksListen"] as? String).flatMap {
      $0.isEmpty ? nil : $0
    } ?? "127.0.0.1:10808"
    var suffixes: [String] = []
    if let raw = obj["directDomainSuffixes"] as? [String] {
      suffixes = raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .filter { !$0.isEmpty }
    }
    let host = server.split(separator: ":", maxSplits: 1).first.map(String.init) ?? server
    var go: [String: Any] = [
      "server": server,
      "auth": auth,
      "sni": sni,
      "socks_listen": socks,
    ]
    if !suffixes.isEmpty {
      go["direct_domain_suffixes"] = suffixes
    }
    guard
      let goData = try? JSONSerialization.data(withJSONObject: go),
      let goJSON = String(data: goData, encoding: .utf8)
    else {
      return nil
    }
    return Hy2StartConfig(remoteHost: host, goJSON: goJSON)
  }
}
