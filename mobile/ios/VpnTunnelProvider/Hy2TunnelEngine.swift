import Darwin
import Foundation
import NetworkExtension

#if canImport(Hy2bind)
import Hy2bind
#endif

/// Hysteria2 engine inside the Packet Tunnel (ADR 019).
///
/// Honest Connected = `setTunnelNetworkSettings` + Hy2 `Start` + packet tun
/// + `packetFlow` pump. SOCKS-only is never Connected.
///
/// IPv6: claim `::/0` so Safari/YouTube cannot leak AAAA to LTE (RF TSPU).
/// Hy2 nodes are IPv4-only — do **not** InjectPacket IPv6 into gVisor; reply
/// ICMPv6 Destination Unreachable so Happy Eyeballs falls back to IPv4 in TUN.
final class Hy2TunnelEngine: NSObject {
  private weak var provider: NEPacketTunnelProvider?
  private var pumping = false
  private let mtu = 1280
  /// IPv6 packets claimed then dropped (not forwarded to Hy2).
  private var ipv6DropCount: UInt64 = 0
  private var lastIpv6DropLogged: UInt64 = 0

  func start(
    provider: NEPacketTunnelProvider,
    paramsJson: String,
    completion: @escaping (Error?) -> Void
  ) {
    self.provider = provider
    ipv6DropCount = 0
    lastIpv6DropLogged = 0
    #if canImport(Hy2bind)
    guard let cfg = Hy2StartConfig.parse(paramsJson) else {
      completion(Self.err(2, "invalid Hy2 paramsJson"))
      return
    }
    let settings = Self.networkSettings(
      remoteHost: cfg.remoteHost,
      mtu: mtu,
      excludedHosts: cfg.controlPlaneHosts
    )
    if !cfg.controlPlaneHosts.isEmpty {
      TeremokVpnShared.appendNativeLog(
        "PacketTunnel.exclude api=\(cfg.controlPlaneHosts.joined(separator: ","))"
      )
    }
    TeremokVpnShared.appendNativeLog("PacketTunnel.v6 claim=default")
    provider.setTunnelNetworkSettings(settings) { [weak self] error in
      guard let self else { return }
      if let error {
        completion(error)
        return
      }
      // gomobile iOS: Hy2bindStart, not Java Hy2bind.start().
      Hy2bindSetPacketWriter(self)
      let startErr = Hy2bindStart(cfg.goJSON) ?? ""
      if !startErr.isEmpty {
        completion(Self.err(4, startErr))
        return
      }
      let tunErr = Hy2bindStartPacketTun(self.mtu) ?? ""
      if !tunErr.isEmpty {
        Hy2bindStop()
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
    if ipv6DropCount > 0 {
      TeremokVpnShared.appendNativeLog("PacketTunnel.v6 drop=\(ipv6DropCount)")
    }
    #if canImport(Hy2bind)
    Hy2bindSetPacketWriter(nil)
    Hy2bindStop()
    #endif
    provider = nil
  }

  private func pumpInbound() {
    guard pumping, let flow = provider?.packetFlow else { return }
    flow.readPackets { [weak self] packets, _ in
      guard let self, self.pumping else { return }
      var icmpReplies: [Data] = []
      var icmpProtos: [NSNumber] = []
      #if canImport(Hy2bind)
      for packet in packets where !packet.isEmpty {
        if Self.isIPv6(packet) {
          self.noteIpv6Drop()
          if let icmp = Self.icmpv6DestinationUnreachable(for: packet) {
            icmpReplies.append(icmp)
            icmpProtos.append(NSNumber(value: AF_INET6))
          }
          continue
        }
        let injectErr = Hy2bindInjectPacket(packet) ?? ""
        if !injectErr.isEmpty {
          NSLog("[Teremok] injectPacket: %@", injectErr)
        }
      }
      #else
      for packet in packets where !packet.isEmpty {
        if Self.isIPv6(packet) {
          self.noteIpv6Drop()
          if let icmp = Self.icmpv6DestinationUnreachable(for: packet) {
            icmpReplies.append(icmp)
            icmpProtos.append(NSNumber(value: AF_INET6))
          }
        }
      }
      #endif
      if !icmpReplies.isEmpty {
        flow.writePackets(icmpReplies, withProtocols: icmpProtos)
      }
      self.pumpInbound()
    }
  }

  private func noteIpv6Drop() {
    ipv6DropCount += 1
    // First drop + every 64 thereafter (App Group ring stays readable).
    if ipv6DropCount == 1 || ipv6DropCount - lastIpv6DropLogged >= 64 {
      lastIpv6DropLogged = ipv6DropCount
      TeremokVpnShared.appendNativeLog("PacketTunnel.v6 drop=\(ipv6DropCount)")
    }
  }

  static func networkSettings(
    remoteHost: String,
    mtu: Int,
    excludedHosts: [String] = []
  ) -> NEPacketTunnelNetworkSettings {
    let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: remoteHost)
    let ipv4 = NEIPv4Settings(
      addresses: ["10.255.255.1"],
      subnetMasks: ["255.255.255.252"]
    )
    ipv4.includedRoutes = [NEIPv4Route.default()]
    // Parity with Android excludeRoute: API master must stay on LTE/Wi‑Fi.
    let v4Excludes = excludedHosts.compactMap { host -> NEIPv4Route? in
      let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
      guard Self.isIPv4(trimmed) else { return nil }
      return NEIPv4Route(destinationAddress: trimmed, subnetMask: "255.255.255.255")
    }
    if !v4Excludes.isEmpty {
      ipv4.excludedRoutes = v4Excludes
    }
    settings.ipv4Settings = ipv4

    // Claim ::/0 so dual-stack apps cannot leak AAAA to LTE. ULA TUN addr only;
    // IPv6 payloads are dropped in pumpInbound (Hy2 egress is IPv4-only).
    let ipv6 = NEIPv6Settings(
      addresses: ["fd00:9e3a::1"],
      networkPrefixLengths: [NSNumber(value: 64)]
    )
    ipv6.includedRoutes = [NEIPv6Route.default()]
    settings.ipv6Settings = ipv6

    settings.mtu = NSNumber(value: mtu)
    let dns = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
    settings.dnsSettings = dns
    return settings
  }

  private static func isIPv4(_ host: String) -> Bool {
    var addr = in_addr()
    return host.withCString { inet_pton(AF_INET, $0, &addr) == 1 }
  }

  private static func isIPv6(_ packet: Data) -> Bool {
    guard !packet.isEmpty else { return false }
    return (packet[packet.startIndex] >> 4) == 6
  }

  /// ICMPv6 Destination Unreachable (type 1, code 1 = administratively prohibited).
  /// Speeds Happy Eyeballs onto IPv4 through the same TUN.
  static func icmpv6DestinationUnreachable(for original: Data) -> Data? {
    // Need IPv6 header (40) + at least a few payload bytes for the quote.
    guard original.count >= 40 else { return nil }
    // Do not answer ICMP errors with more ICMP errors (next header 58).
    let nextHeader = original[original.startIndex + 6]
    if nextHeader == 58 { return nil }

    // ULA TUN address fd00:9e3a::1 (network order).
    let srcAddr: [UInt8] = [
      0xfd, 0x00, 0x9e, 0x3a, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
    ]
    // Original source becomes ICMP destination (bytes 8..23 of IPv6 header).
    let dstAddr = Array(original[(original.startIndex + 8)..<(original.startIndex + 24)])

    // Quote as much of the original as fits under common ICMPv6 size (~1232).
    let maxQuote = min(original.count, 1232)
    let quote = original[original.startIndex..<(original.startIndex + maxQuote)]

    // ICMPv6: type=1, code=1, checksum=0, unused=0, + quoted packet.
    var icmp = Data(capacity: 8 + quote.count)
    icmp.append(1) // Destination Unreachable
    icmp.append(1) // Administratively prohibited
    icmp.append(contentsOf: [0, 0]) // checksum placeholder
    icmp.append(contentsOf: [0, 0, 0, 0]) // unused
    icmp.append(quote)

    let checksum = icmpv6Checksum(
      src: srcAddr,
      dst: dstAddr,
      icmp: icmp
    )
    icmp[2] = UInt8((checksum >> 8) & 0xff)
    icmp[3] = UInt8(checksum & 0xff)

    let payloadLen = UInt16(icmp.count)
    var out = Data(capacity: 40 + icmp.count)
    // Version 6, traffic class 0, flow 0
    out.append(0x60)
    out.append(contentsOf: [0, 0, 0])
    out.append(UInt8((payloadLen >> 8) & 0xff))
    out.append(UInt8(payloadLen & 0xff))
    out.append(58) // next header ICMPv6
    out.append(64) // hop limit
    out.append(contentsOf: srcAddr)
    out.append(contentsOf: dstAddr)
    out.append(icmp)
    return out
  }

  /// RFC 4443 ICMPv6 checksum over IPv6 pseudo-header + ICMP body.
  private static func icmpv6Checksum(src: [UInt8], dst: [UInt8], icmp: Data) -> UInt16 {
    var sum: UInt32 = 0
    func addBytes(_ bytes: [UInt8]) {
      var i = 0
      while i + 1 < bytes.count {
        sum += UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1])
        i += 2
      }
      if i < bytes.count {
        sum += UInt32(bytes[i]) << 8
      }
    }
    addBytes(src)
    addBytes(dst)
    let len = UInt32(icmp.count)
    sum += (len >> 16) & 0xffff
    sum += len & 0xffff
    sum += 58 // next header
    let icmpBytes = [UInt8](icmp)
    addBytes(icmpBytes)
    while sum >> 16 != 0 {
      sum = (sum & 0xffff) + (sum >> 16)
    }
    return ~UInt16(sum & 0xffff)
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
// Class Hy2bindPacketWriter exists; Swift imports the ObjC protocol as *Protocol.
extension Hy2TunnelEngine: Hy2bindPacketWriterProtocol {
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
  var controlPlaneHosts: [String]

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
    var controlPlane: [String] = []
    if let raw = obj["controlPlaneHosts"] as? [String] {
      controlPlane = raw
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
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
    return Hy2StartConfig(
      remoteHost: host,
      goJSON: goJSON,
      controlPlaneHosts: controlPlane
    )
  }
}
