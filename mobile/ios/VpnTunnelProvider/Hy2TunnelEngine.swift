import Darwin
import Foundation
import Network
import NetworkExtension

#if canImport(Hy2bind)
import Hy2bind
#endif

/// Hysteria2 engine inside the Packet Tunnel (ADR 019 / ADR 025).
///
/// Honest Connected = `setTunnelNetworkSettings` + Hy2 `Start` + packet tun
/// + `packetFlow` pump. SOCKS-only is never Connected.
///
/// Path changes: `NWPathMonitor` → debounced `Hy2bindResetNetwork` (keep TUN).
/// A share hostname is resolved with getaddrinfo before tunnel settings.
/// That one A is the excluded /32 and the address Go dials. SNI stays the name.
/// Sites use exact-host OS excludedRoutes; Go hyDialer direct is disabled.
///
/// IPv6: claim `::/0` so Safari/YouTube cannot leak AAAA to LTE (RF TSPU).
/// Hy2 nodes are IPv4-only — do **not** InjectPacket IPv6 into gVisor; reply
/// ICMPv6 Destination Unreachable so Happy Eyeballs falls back to IPv4 in TUN.
final class Hy2TunnelEngine: NSObject {
  private weak var provider: NEPacketTunnelProvider?
  private var pumping = false
  private let lifecycleLock = NSLock()
  private var lifecycleToken: UInt64 = 0
  private let mtu = 1280
  /// IPv6 packets claimed then dropped (not forwarded to Hy2).
  private var ipv6DropCount: UInt64 = 0
  private var lastIpv6DropLogged: UInt64 = 0
  /// Packets the Hy2 core refused. Counted, not printed — see `noteInjectFailure`.
  private var injectFailureCount: UInt64 = 0
  private var lastInjectFailureLogged: UInt64 = 0

  private var pathMonitor: Network.NWPathMonitor?
  private let pathQueue = DispatchQueue(label: "su.proxydom.app.vpn.path")
  private let resetQueue = DispatchQueue(label: "su.proxydom.app.vpn.reset")
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
    lifecycleLock.lock()
    lifecycleToken &+= 1
    let startToken = lifecycleToken
    pumping = false
    lifecycleLock.unlock()
    healthLock.lock()
    ipv6DropCount = 0
    lastIpv6DropLogged = 0
    injectFailureCount = 0
    lastInjectFailureLogged = 0
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
    // getaddrinfo must finish before setTunnelNetworkSettings. After that,
    // DNS is 1.1.1.1 inside the tunnel and Go's ResolveUDPAddr would loop.
    // The same A is pinned into excludedRoutes and the Go server string.
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else { return }
      let pinned: Hy2StartConfig
      if TunnelRouteMerge.isIPv4Literal(cfg.remoteHost)
        || TunnelRouteMerge.isIPv6Literal(cfg.remoteHost)
      {
        pinned = cfg
      } else {
        switch Self.resolveEndpointIPv4(cfg.remoteHost) {
        case .ip(let ip):
          guard let next = cfg.pinned(toIPv4: ip) else {
            self.failStart(
              startToken: startToken,
              code: 3,
              message: "Hy2 endpoint pin failed",
              completion: completion
            )
            return
          }
          pinned = next
        case .empty:
          self.failStart(
            startToken: startToken,
            code: 3,
            message: "Hy2 endpoint DNS empty",
            completion: completion
          )
          return
        case .timedOut:
          self.failStart(
            startToken: startToken,
            code: 3,
            message: "Hy2 endpoint DNS timeout",
            completion: completion
          )
          return
        }
      }
      let baseIPv4 = TunnelRouteMerge.ipv4Excludes(
        endpointHost: pinned.remoteHost,
        controlPlaneHosts: pinned.controlPlaneHosts
      )
      let baseIPv6 = TunnelRouteMerge.ipv6Excludes(
        endpointHost: pinned.remoteHost,
        controlPlaneHosts: pinned.controlPlaneHosts
      )
      let plan = Self.resolveExactRoutes(
        customHosts: pinned.iosCustomResolutionHosts,
        catalogHosts: pinned.iosCatalogResolutionHosts,
        baseIPv4: baseIPv4,
        baseIPv6: baseIPv6
      )
      DispatchQueue.main.async {
        guard self.isCurrentStart(startToken) else {
          completion(Self.err(6, "Hy2 start cancelled"))
          return
        }
        self.applyTunnel(
          provider: provider,
          cfg: pinned,
          routePlan: plan,
          startToken: startToken,
          completion: completion
        )
      }
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

  #if canImport(Hy2bind)
  private func applyTunnel(
    provider: NEPacketTunnelProvider,
    cfg: Hy2StartConfig,
    routePlan: TunnelRoutePlan,
    startToken: UInt64,
    completion: @escaping (Error?) -> Void
  ) {
    let settings = Self.networkSettings(
      remoteHost: cfg.remoteHost,
      mtu: mtu,
      excludedIPv4: routePlan.v4,
      excludedIPv6: routePlan.v6
    )
    ProxyDomVpnShared.appendNativeLog(
      "PacketTunnel.exclude host=\(cfg.dialHost) pin=\(cfg.remoteHost) "
        + "requested=\(routePlan.requestedHosts) "
        + "completed=\(routePlan.completedHosts) resolved=\(routePlan.resolvedHosts) "
        + "v4=\(routePlan.v4.count) v6=\(routePlan.v6.count) "
        + "dropped_v4=\(routePlan.droppedIPv4) dropped_v6=\(routePlan.droppedIPv6) "
        + "capped=\(routePlan.capped) timeout=\(routePlan.timedOut)"
    )
    ProxyDomVpnShared.appendNativeLog("PacketTunnel.v6 claim=default")
    provider.setTunnelNetworkSettings(settings) { [weak self] error in
      guard let self else { return }
      if let error {
        completion(error)
        return
      }
      self.lifecycleLock.lock()
      guard startToken == self.lifecycleToken else {
        self.lifecycleLock.unlock()
        completion(Self.err(6, "Hy2 start cancelled"))
        return
      }
      Hy2bindSetPacketWriter(self)
      let startErr = Hy2bindStart(cfg.goJSON) ?? ""
      if !startErr.isEmpty {
        self.lifecycleLock.unlock()
        completion(Self.err(4, startErr))
        return
      }
      let tunErr = Hy2bindStartPacketTun(self.mtu) ?? ""
      if !tunErr.isEmpty {
        Hy2bindStop()
        self.lifecycleLock.unlock()
        completion(Self.err(5, tunErr))
        return
      }
      self.pumping = true
      self.startPathMonitor()
      self.pumpInbound()
      self.lifecycleLock.unlock()
      self.persistHealth(force: true)
      completion(nil)
    }
  }
  #endif

  func stop() {
    lifecycleLock.lock()
    lifecycleToken &+= 1
    pumping = false
    #if canImport(Hy2bind)
    Hy2bindSetPacketWriter(nil)
    Hy2bindStop()
    #endif
    lifecycleLock.unlock()
    stopPathMonitor()
    healthLock.lock()
    let droppedV6 = ipv6DropCount
    healthLock.unlock()
    if droppedV6 > 0 {
      ProxyDomVpnShared.appendNativeLog("PacketTunnel.v6 drop=\(droppedV6)")
    }
    persistHealth(force: true)
    provider = nil
  }

  private func isCurrentStart(_ token: UInt64) -> Bool {
    lifecycleLock.lock()
    defer { lifecycleLock.unlock() }
    return token == lifecycleToken
  }

  /// DNS failure stays on the main queue and does not apply tunnel settings.
  private func failStart(
    startToken: UInt64,
    code: Int,
    message: String,
    completion: @escaping (Error?) -> Void
  ) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      guard self.isCurrentStart(startToken) else {
        completion(Self.err(6, "Hy2 start cancelled"))
        return
      }
      completion(Self.err(code, message))
    }
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
      "generation": ProxyDomVpnShared.currentGeneration(),
      "session_active": ProxyDomVpnShared.isSessionActive(),
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
      "last_stop_reason": ProxyDomVpnShared.lastStopReason(),
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
    ProxyDomVpnShared.persistTunnelHealth(healthJSON())
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
        ProxyDomVpnShared.appendNativeLog("PacketTunnel.reset ok reason=\(reason)")
      } else if err == "reset_busy" {
        ProxyDomVpnShared.appendNativeLog("PacketTunnel.reset coalesced reason=\(reason)")
      } else {
        ProxyDomVpnShared.appendNativeLog("PacketTunnel.reset fail reason=\(reason) err=\(err)")
      }
      #else
      ProxyDomVpnShared.appendNativeLog("PacketTunnel.reset skip reason=\(reason)")
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
          self.noteInjectFailure(injectErr)
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

  /// Failures are counted, not printed. This used to be one `NSLog` per packet
  /// inside the read loop: a stuck engine meant one unified-log line per
  /// packet, forever, and `injectErr` is raw Go text that can echo the config
  /// the engine was given. The ring is bounded and redacted on export; the
  /// unified log is neither.
  private func noteInjectFailure(_ error: String) {
    healthLock.lock()
    injectFailureCount += 1
    let count = injectFailureCount
    let shouldLog = count == 1 || count - lastInjectFailureLogged >= 64
    if shouldLog {
      lastInjectFailureLogged = count
    }
    healthLock.unlock()
    if shouldLog {
      ProxyDomVpnShared.appendNativeLog("PacketTunnel.inject_failed count=\(count)")
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
      ProxyDomVpnShared.appendNativeLog("PacketTunnel.v6 drop=\(count)")
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

  private static let maxExcludedIPv4 = 64
  private static let maxExcludedIPv6 = 32
  private static let resolutionTimeout: TimeInterval = 2.5

  /// Resolve custom then catalog hosts concurrently; route selection remains
  /// deterministic because results are planned in that same priority order.
  static func resolveExactRoutes(
    customHosts: [String],
    catalogHosts: [String],
    baseIPv4: [String],
    baseIPv6: [String]
  ) -> TunnelRoutePlan {
    let hosts = TunnelRoutePlanner.orderedUnique(customHosts + catalogHosts)
    let collector = LockedHostResolutionResults()
    let group = DispatchGroup()

    for (index, raw) in hosts.enumerated() {
      let host = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      guard !host.isEmpty else { continue }
      group.enter()
      DispatchQueue.global(qos: .userInitiated).async {
        collector.submit(index: index, addresses: resolveName(host))
        group.leave()
      }
    }

    let wait = group.wait(timeout: .now() + resolutionTimeout)
    let snapshot = collector.finish()
    let orderedResults = hosts.indices.compactMap { snapshot.results[$0] }
    return TunnelRoutePlanner.build(
      baseIPv4: baseIPv4,
      baseIPv6: baseIPv6,
      orderedHostResults: orderedResults,
      requestedHosts: hosts.count,
      completedHosts: snapshot.completed,
      timedOut: wait == .timedOut,
      maxIPv4: maxExcludedIPv4,
      maxIPv6: maxExcludedIPv6
    )
  }

  private enum EndpointDNS {
    case ip(String)
    case empty
    case timedOut
  }

  /// One A record for the Hy2 peer, on the physical resolver. AAAA is ignored:
  /// the node socket is IPv4, and a later Go lookup must not pick a second A.
  private static func resolveEndpointIPv4(_ host: String) -> EndpointDNS {
    let box = EndpointAddressBox()
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
      box.publish(resolveName(host).v4.first)
      group.leave()
    }
    let wait = group.wait(timeout: .now() + resolutionTimeout)
    if wait == .timedOut {
      return .timedOut
    }
    guard let ip = box.take(), !ip.isEmpty else {
      return .empty
    }
    return .ip(ip)
  }

  private static func resolveName(_ name: String) -> HostRouteAddresses {
    if TunnelRouteMerge.isIPv4Literal(name) {
      return HostRouteAddresses(v4: [name], v6: [])
    }
    if TunnelRouteMerge.isIPv6Literal(name) {
      return HostRouteAddresses(v4: [], v6: [name])
    }
    var hints = addrinfo(
      ai_flags: AI_ADDRCONFIG,
      ai_family: AF_UNSPEC,
      ai_socktype: SOCK_STREAM,
      ai_protocol: 0,
      ai_addrlen: 0,
      ai_canonname: nil,
      ai_addr: nil,
      ai_next: nil
    )
    var result: UnsafeMutablePointer<addrinfo>?
    let rc = getaddrinfo(name, nil, &hints, &result)
    guard rc == 0, let first = result else {
      return HostRouteAddresses(v4: [], v6: [])
    }
    defer { freeaddrinfo(first) }

    var v4: [String] = []
    var v6: [String] = []
    var cursor: UnsafeMutablePointer<addrinfo>? = first
    while let info = cursor {
      if info.pointee.ai_family == AF_INET, let address = info.pointee.ai_addr {
        var sin = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
          $0.pointee
        }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &sin.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN))
        let value = String(cString: buffer)
        if !value.isEmpty { v4.append(value) }
      } else if info.pointee.ai_family == AF_INET6,
                let address = info.pointee.ai_addr
      {
        var sin6 = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
          $0.pointee
        }
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        inet_ntop(AF_INET6, &sin6.sin6_addr, &buffer, socklen_t(INET6_ADDRSTRLEN))
        let value = String(cString: buffer)
        if !value.isEmpty { v6.append(value) }
      }
      cursor = info.pointee.ai_next
    }
    return HostRouteAddresses(
      v4: TunnelRoutePlanner.orderedUnique(v4),
      v6: TunnelRoutePlanner.orderedUnique(v6)
    )
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
      domain: "su.proxydom.app.vpn",
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

/// One published A. The writer stores it before `group.leave`.
private final class EndpointAddressBox {
  private let lock = NSLock()
  private var storage: String?

  func publish(_ ip: String?) {
    lock.lock()
    storage = ip
    lock.unlock()
  }

  func take() -> String? {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }
}

/// Maps Flutter `paramsJson` (same keys as Android) to hy2bind Start JSON.
struct Hy2StartConfig {
  /// Address used for `excludedRoutes` and `tunnelRemoteAddress`. An IP after pin.
  var remoteHost: String
  /// Host from the share line, before pin. Logged; not a secret.
  var dialHost: String
  var goJSON: String
  var controlPlaneHosts: [String]
  var iosCustomResolutionHosts: [String]
  var iosCatalogResolutionHosts: [String]
  var serverPort: Int
  var auth: String
  var explicitSNI: String
  var socksListen: String

  /// Rewrite Go's dial address to one A. SNI stays the name so the cert matches.
  func pinned(toIPv4 ip: String) -> Hy2StartConfig? {
    let trimmedSNI = explicitSNI.trimmingCharacters(in: .whitespacesAndNewlines)
    let sni = trimmedSNI.isEmpty ? dialHost : trimmedSNI
    let go: [String: Any] = [
      "server": "\(ip):\(serverPort)",
      "auth": auth,
      "sni": sni,
      "socks_listen": socksListen,
    ]
    guard
      let goData = try? JSONSerialization.data(withJSONObject: go),
      let goJSON = String(data: goData, encoding: .utf8)
    else {
      return nil
    }
    var copy = self
    copy.remoteHost = ip
    copy.goJSON = goJSON
    return copy
  }

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
    let customHosts = normalizedHosts(obj["iosCustomResolutionHosts"])
    let catalogHosts = normalizedHosts(obj["iosCatalogResolutionHosts"])
    var controlPlane: [String] = []
    if let raw = obj["controlPlaneHosts"] as? [String] {
      controlPlane = raw
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }
    let parts = server.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    let host = parts.first.map(String.init) ?? server
    let port = parts.count == 2 ? Int(parts[1]) ?? 443 : 443
    // ADR 025: iOS never feeds direct_domain_suffixes to Go. Direct paths are
    // only exact destination IPs in NetworkExtension excludedRoutes.
    let go: [String: Any] = [
      "server": server,
      "auth": auth,
      "sni": sni,
      "socks_listen": socks,
    ]
    guard
      let goData = try? JSONSerialization.data(withJSONObject: go),
      let goJSON = String(data: goData, encoding: .utf8)
    else {
      return nil
    }
    return Hy2StartConfig(
      remoteHost: host,
      dialHost: host,
      goJSON: goJSON,
      controlPlaneHosts: controlPlane,
      iosCustomResolutionHosts: customHosts,
      iosCatalogResolutionHosts: catalogHosts,
      serverPort: port,
      auth: auth,
      explicitSNI: sni,
      socksListen: socks
    )
  }

  private static func normalizedHosts(_ raw: Any?) -> [String] {
    guard let values = raw as? [String] else { return [] }
    return TunnelRoutePlanner.orderedUnique(
      values
        .map {
          $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        .filter { !$0.isEmpty }
    )
  }
}
