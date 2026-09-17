import Darwin
import Foundation
import Network
import NetworkExtension

#if canImport(Hy2bind)
import Hy2bind
#endif

/// Hysteria2 engine inside the Packet Tunnel (ADR 019).
///
/// Honest Connected = `setTunnelNetworkSettings` + Hy2 `Start` + packet tun
/// + `packetFlow` pump. SOCKS-only is never Connected.
///
/// Path changes: `NWPathMonitor` → debounced `Hy2bindResetNetwork` (keep TUN).
/// Hy2 endpoint IP is always in excludedRoutes /32 (WireGuard-style).
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

  private var pathMonitor: Network.NWPathMonitor?
  private let pathQueue = DispatchQueue(label: "online.teremokconnect.vpn.path")
  private let resetQueue = DispatchQueue(label: "online.teremokconnect.vpn.reset")
  private var lastPath: TunnelPathSnapshot?
  private var resetWorkItem: DispatchWorkItem?
  private let resetDebounceMs: Int = 400

  private var ingressPackets: UInt64 = 0
  private var ingressBytes: UInt64 = 0
  private var egressPackets: UInt64 = 0
  private var egressBytes: UInt64 = 0
  private var lastIngressAt: Date?
  private var lastEgressAt: Date?
  private var lastHealthPersistAt: Date = .distantPast
  private let healthLock = NSLock()

  func start(
    provider: NEPacketTunnelProvider,
    paramsJson: String,
    completion: @escaping (Error?) -> Void
  ) {
    self.provider = provider
    healthLock.lock()
    ipv6DropCount = 0
    lastIpv6DropLogged = 0
    ingressPackets = 0
    ingressBytes = 0
    egressPackets = 0
    egressBytes = 0
    lastIngressAt = nil
    lastEgressAt = nil
    lastPath = nil
    healthLock.unlock()
    #if canImport(Hy2bind)
    guard let cfg = Hy2StartConfig.parse(paramsJson) else {
      completion(Self.err(2, "invalid Hy2 paramsJson"))
      return
    }
    // Catalog uses IP endpoints; hostname without sync route refresh is fail-fast.
    if !TunnelRouteMerge.isIPv4Literal(cfg.remoteHost)
      && !TunnelRouteMerge.isIPv6Literal(cfg.remoteHost)
    {
      completion(Self.err(3, "Hy2 endpoint must be IP literal for excludedRoutes"))
      return
    }
    let excludesV4 = TunnelRouteMerge.ipv4Excludes(
      endpointHost: cfg.remoteHost,
      controlPlaneHosts: cfg.controlPlaneHosts
    )
    let excludesV6 = TunnelRouteMerge.ipv6Excludes(
      endpointHost: cfg.remoteHost,
      controlPlaneHosts: cfg.controlPlaneHosts
    )
    let settings = Self.networkSettings(
      remoteHost: cfg.remoteHost,
      mtu: mtu,
      excludedIPv4: excludesV4,
      excludedIPv6: excludesV6
    )
    if !excludesV4.isEmpty || !excludesV6.isEmpty {
      TeremokVpnShared.appendNativeLog(
        "PacketTunnel.exclude endpoint_api v4=\(excludesV4.count) v6=\(excludesV6.count)"
      )
    }
    TeremokVpnShared.appendNativeLog("PacketTunnel.v6 claim=default")
    provider.setTunnelNetworkSettings(settings) { [weak self] error in
      guard let self else { return }
      if let error {
        completion(error)
        return
      }
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
      self.startPathMonitor()
      self.pumpInbound()
      self.persistHealth(force: true)
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
    stopPathMonitor()
    healthLock.lock()
    let droppedV6 = ipv6DropCount
    healthLock.unlock()
    if droppedV6 > 0 {
      TeremokVpnShared.appendNativeLog("PacketTunnel.v6 drop=\(droppedV6)")
    }
    persistHealth(force: true)
    #if canImport(Hy2bind)
    Hy2bindSetPacketWriter(nil)
    Hy2bindStop()
    #endif
    provider = nil
  }

  func healthDictionary() -> [String: Any] {
    #if canImport(Hy2bind)
    let hyRaw = Hy2bindHealthJSON() ?? ""
    #else
    let hyRaw = ""
    #endif
    var hyObj: [String: Any] = [:]
    if let data = hyRaw.data(using: .utf8),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    {
      hyObj = obj
    }
    healthLock.lock()
    let path = lastPath
    let ingressPacketsSnapshot = ingressPackets
    let ingressBytesSnapshot = ingressBytes
    let egressPacketsSnapshot = egressPackets
    let egressBytesSnapshot = egressBytes
    let lastIngressSnapshot = lastIngressAt
    let lastEgressSnapshot = lastEgressAt
    let ipv6DropSnapshot = ipv6DropCount
    healthLock.unlock()

    let ingressAgeMs: Int
    if let lastIngressSnapshot {
      ingressAgeMs = Int(Date().timeIntervalSince(lastIngressSnapshot) * 1000)
    } else {
      ingressAgeMs = -1
    }
    let egressAgeMs: Int
    if let lastEgressSnapshot {
      egressAgeMs = Int(Date().timeIntervalSince(lastEgressSnapshot) * 1000)
    } else {
      egressAgeMs = -1
    }
    let pathSatisfied: Any = path.map { $0.satisfied as Any } ?? NSNull()
    let pathWifi: Any = path.map { $0.usesWifi as Any } ?? NSNull()
    let pathCellular: Any = path.map { $0.usesCellular as Any } ?? NSNull()
    return [
      "generation": TeremokVpnShared.currentGeneration(),
      "session_active": TeremokVpnShared.isSessionActive(),
      "path_satisfied": pathSatisfied,
      "path_wifi": pathWifi,
      "path_cellular": pathCellular,
      "ingress_packets": ingressPacketsSnapshot,
      "ingress_bytes": ingressBytesSnapshot,
      "egress_packets": egressPacketsSnapshot,
      "egress_bytes": egressBytesSnapshot,
      "ingress_age_ms": ingressAgeMs,
      "egress_age_ms": egressAgeMs,
      "ipv6_drop": ipv6DropSnapshot,
      "last_stop_reason": TeremokVpnShared.lastStopReason(),
      "hy2": hyObj,
    ]
  }

  func healthJSON() -> String {
    let obj = healthDictionary()
    guard
      let data = try? JSONSerialization.data(withJSONObject: obj),
      let s = String(data: data, encoding: .utf8)
    else {
      return "{}"
    }
    return s
  }

  private func persistHealth(force: Bool) {
    let now = Date()
    healthLock.lock()
    if !force, now.timeIntervalSince(lastHealthPersistAt) < 2 {
      healthLock.unlock()
      return
    }
    lastHealthPersistAt = now
    healthLock.unlock()
    TeremokVpnShared.persistTunnelHealth(healthJSON())
  }

  private func startPathMonitor() {
    stopPathMonitor()
    let monitor = Network.NWPathMonitor()
    pathMonitor = monitor
    monitor.pathUpdateHandler = { [weak self] path in
      self?.onPathUpdate(path)
    }
    monitor.start(queue: pathQueue)
  }

  private func stopPathMonitor() {
    resetWorkItem?.cancel()
    resetWorkItem = nil
    pathMonitor?.cancel()
    pathMonitor = nil
    healthLock.lock()
    lastPath = nil
    healthLock.unlock()
  }

  private func onPathUpdate(_ path: Network.NWPath) {
    let next = TunnelPathSnapshot.from(path)
    healthLock.lock()
    let (decision, stored) = TunnelPathReducer.decide(previous: lastPath, next: next)
    lastPath = stored
    healthLock.unlock()
    persistHealth(force: false)
    guard case let .reset(reason) = decision else { return }
    scheduleReset(reason: reason)
  }

  private func scheduleReset(reason: String) {
    resetWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in
      self?.performReset(reason: reason)
    }
    resetWorkItem = work
    pathQueue.asyncAfter(
      deadline: .now() + .milliseconds(resetDebounceMs),
      execute: work
    )
  }

  private func performReset(reason: String) {
    guard pumping else { return }
    resetQueue.async { [weak self] in
      guard let self, self.pumping, let provider = self.provider else { return }
      provider.reasserting = true
      defer { provider.reasserting = false }
      #if canImport(Hy2bind)
      let err = Hy2bindResetNetwork(reason) ?? ""
      if err.isEmpty {
        TeremokVpnShared.appendNativeLog("PacketTunnel.reset ok reason=\(reason)")
      } else if err == "reset_busy" {
        TeremokVpnShared.appendNativeLog("PacketTunnel.reset coalesced reason=\(reason)")
      } else {
        TeremokVpnShared.appendNativeLog("PacketTunnel.reset fail reason=\(reason) err=\(err)")
      }
      #else
      TeremokVpnShared.appendNativeLog("PacketTunnel.reset skip reason=\(reason)")
      #endif
      self.persistHealth(force: true)
    }
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
        self.healthLock.lock()
        self.ingressPackets += 1
        self.ingressBytes += UInt64(packet.count)
        self.lastIngressAt = Date()
        self.healthLock.unlock()
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
      self.persistHealth(force: false)
      self.pumpInbound()
    }
  }

  private func noteIpv6Drop() {
    healthLock.lock()
    ipv6DropCount += 1
    let shouldLog =
      ipv6DropCount == 1 || ipv6DropCount - lastIpv6DropLogged >= 64
    let count = ipv6DropCount
    if shouldLog {
      lastIpv6DropLogged = count
    }
    healthLock.unlock()
    if shouldLog {
      TeremokVpnShared.appendNativeLog("PacketTunnel.v6 drop=\(count)")
    }
  }

  static func networkSettings(
    remoteHost: String,
    mtu: Int,
    excludedIPv4: [String] = [],
    excludedIPv6: [String] = []
  ) -> NEPacketTunnelNetworkSettings {
    let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: remoteHost)
    let ipv4 = NEIPv4Settings(
      addresses: ["10.255.255.1"],
      subnetMasks: ["255.255.255.252"]
    )
    ipv4.includedRoutes = [NEIPv4Route.default()]
    let v4Excludes = excludedIPv4.compactMap { host -> NEIPv4Route? in
      let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
      guard TunnelRouteMerge.isIPv4Literal(trimmed) else { return nil }
      return NEIPv4Route(destinationAddress: trimmed, subnetMask: "255.255.255.255")
    }
    if !v4Excludes.isEmpty {
      ipv4.excludedRoutes = v4Excludes
    }
    settings.ipv4Settings = ipv4

    let ipv6 = NEIPv6Settings(
      addresses: ["fd00:9e3a::1"],
      networkPrefixLengths: [NSNumber(value: 64)]
    )
    ipv6.includedRoutes = [NEIPv6Route.default()]
    let v6Excludes = excludedIPv6.compactMap { host -> NEIPv6Route? in
      let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
      guard TunnelRouteMerge.isIPv6Literal(trimmed) else { return nil }
      return NEIPv6Route(destinationAddress: trimmed, networkPrefixLength: 128)
    }
    if !v6Excludes.isEmpty {
      ipv6.excludedRoutes = v6Excludes
    }
    settings.ipv6Settings = ipv6

    settings.mtu = NSNumber(value: mtu)
    let dns = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
    settings.dnsSettings = dns
    return settings
  }

  private static func isIPv6(_ packet: Data) -> Bool {
    guard !packet.isEmpty else { return false }
    return (packet[packet.startIndex] >> 4) == 6
  }

  static func icmpv6DestinationUnreachable(for original: Data) -> Data? {
    guard original.count >= 40 else { return nil }
    let nextHeader = original[original.startIndex + 6]
    if nextHeader == 58 { return nil }

    let srcAddr: [UInt8] = [
      0xfd, 0x00, 0x9e, 0x3a, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
    ]
    let dstAddr = Array(original[(original.startIndex + 8)..<(original.startIndex + 24)])

    let maxQuote = min(original.count, 1232)
    let quote = original[original.startIndex..<(original.startIndex + maxQuote)]

    var icmp = Data(capacity: 8 + quote.count)
    icmp.append(1)
    icmp.append(1)
    icmp.append(contentsOf: [0, 0])
    icmp.append(contentsOf: [0, 0, 0, 0])
    icmp.append(quote)

    let checksum = icmpv6Checksum(src: srcAddr, dst: dstAddr, icmp: icmp)
    icmp[2] = UInt8((checksum >> 8) & 0xff)
    icmp[3] = UInt8(checksum & 0xff)

    let payloadLen = UInt16(icmp.count)
    var out = Data(capacity: 40 + icmp.count)
    out.append(0x60)
    out.append(contentsOf: [0, 0, 0])
    out.append(UInt8((payloadLen >> 8) & 0xff))
    out.append(UInt8(payloadLen & 0xff))
    out.append(58)
    out.append(64)
    out.append(contentsOf: srcAddr)
    out.append(contentsOf: dstAddr)
    out.append(icmp)
    return out
  }

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
    sum += 58
    addBytes([UInt8](icmp))
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
extension Hy2TunnelEngine: Hy2bindPacketWriterProtocol {
  func writePacket(_ packet: Data?) throws {
    guard let packet, !packet.isEmpty, let provider else { return }
    healthLock.lock()
    egressPackets += 1
    egressBytes += UInt64(packet.count)
    lastEgressAt = Date()
    healthLock.unlock()
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
