import Darwin
import Foundation
import NetworkExtension

#if canImport(Hy2bind)
import Hy2bind
#endif

/// The v2ray-core engine inside the Packet Tunnel.
///
/// The same Go package that carries Hysteria2 on iOS also carries VLESS, VMess,
/// Trojan, Shadowsocks and SOCKS5 — it is one gomobile framework. What it lacked
/// was a dataplane: iOS never gives a TUN file descriptor, so the Android
/// `StartShareTun(fd)` path cannot run here. hy2bind grew
/// `StartSharePacketTun` + `InjectPacket`, the userspace pair the Hysteria2
/// engine already used, and this is the provider half.
///
/// Honest Connected = tunnel settings applied + share core started + packet tun
/// attached + the flow pumped. A core that started but carried nothing is not
/// Connected, and that distinction is the whole point of the counter below.
final class ShareTunnelEngine: NSObject {
  private weak var provider: NEPacketTunnelProvider?
  private var pumping = false
  private let lifecycleLock = NSLock()
  private var lifecycleToken: UInt64 = 0
  private let mtu = 1280

  private var ingressPackets: UInt64 = 0
  private var egressPackets: UInt64 = 0
  private var injectFailureCount: UInt64 = 0

  func start(
    provider: NEPacketTunnelProvider,
    paramsJson: String,
    completion: @escaping (Error?) -> Void
  ) {
    self.provider = provider
    lifecycleLock.lock()
    lifecycleToken &+= 1
    let token = lifecycleToken
    lifecycleLock.unlock()

    guard let params = ShareStartConfig(paramsJson: paramsJson) else {
      completion(Self.err(2, "share params unreadable"))
      return
    }

    #if canImport(Hy2bind)
    let settings = Self.networkSettings(remoteHost: params.remoteHost, mtu: mtu)
    provider.setTunnelNetworkSettings(settings) { [weak self] error in
      guard let self else { return }
      if let error {
        completion(error)
        return
      }
      self.lifecycleLock.lock()
      guard token == self.lifecycleToken else {
        self.lifecycleLock.unlock()
        completion(Self.err(6, "share start cancelled"))
        return
      }
      Hy2bindSetPacketWriter(self)
      let startErr = Hy2bindStartShare(params.document) ?? ""
      if !startErr.isEmpty {
        self.lifecycleLock.unlock()
        completion(Self.err(4, startErr))
        return
      }
      let tunErr = Hy2bindStartSharePacketTun(self.mtu) ?? ""
      if !tunErr.isEmpty {
        Hy2bindStop()
        self.lifecycleLock.unlock()
        completion(Self.err(5, tunErr))
        return
      }
      self.pumping = true
      self.lifecycleLock.unlock()
      self.pumpInbound()
      completion(nil)
    }
    #else
    completion(Self.err(3, "Hy2bind framework is not linked"))
    #endif
  }

  func stop() {
    lifecycleLock.lock()
    lifecycleToken &+= 1
    pumping = false
    #if canImport(Hy2bind)
    Hy2bindSetPacketWriter(nil)
    Hy2bindStop()
    #endif
    lifecycleLock.unlock()
    provider = nil
  }

  /// One read loop for the whole session: `readPackets` re-arms itself, and a
  /// loop that stopped would leave the tunnel up with nothing flowing.
  private func pumpInbound() {
    guard pumping, let flow = provider?.packetFlow else { return }
    flow.readPackets { [weak self] packets, _ in
      guard let self, self.pumping else { return }
      var replies: [Data] = []
      var replyProtocols: [NSNumber] = []
      #if canImport(Hy2bind)
      for packet in packets where !packet.isEmpty {
        if Self.isIPv6(packet) {
          // The share document here is IPv4 dialling; claiming ::/0 keeps
          // Safari from leaking AAAA straight past the tunnel. Answering with
          // ICMPv6 unreachable makes Happy Eyeballs fall back at once instead
          // of waiting out its timer.
          if let icmp = Self.icmpv6DestinationUnreachable(for: packet) {
            replies.append(icmp)
            replyProtocols.append(NSNumber(value: AF_INET6))
          }
          continue
        }
        self.ingressPackets += 1
        let injectErr = Hy2bindInjectPacket(packet) ?? ""
        if !injectErr.isEmpty {
          self.injectFailureCount += 1
        }
      }
      #else
      for packet in packets where !packet.isEmpty && Self.isIPv6(packet) {
        if let icmp = Self.icmpv6DestinationUnreachable(for: packet) {
          replies.append(icmp)
          replyProtocols.append(NSNumber(value: AF_INET6))
        }
      }
      #endif
      if !replies.isEmpty {
        flow.writePackets(replies, withProtocols: replyProtocols)
      }
      self.pumpInbound()
    }
  }

  private static func networkSettings(
    remoteHost: String,
    mtu: Int
  ) -> NEPacketTunnelNetworkSettings {
    let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: remoteHost)
    let ipv4 = NEIPv4Settings(
      addresses: ["10.255.255.1"],
      subnetMasks: ["255.255.255.252"]
    )
    ipv4.includedRoutes = [NEIPv4Route.default()]
    settings.ipv4Settings = ipv4

    let ipv6 = NEIPv6Settings(
      addresses: ["fd00:9e3a::1"],
      networkPrefixLengths: [NSNumber(value: 64)]
    )
    ipv6.includedRoutes = [NEIPv6Route.default()]
    settings.ipv6Settings = ipv6

    settings.mtu = NSNumber(value: mtu)
    settings.dnsSettings = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
    return settings
  }

  private static func isIPv6(_ packet: Data) -> Bool {
    guard let first = packet.first else { return false }
    return first >> 4 == 6
  }

  /// ICMPv6 Destination Unreachable (no route), addressed back at the sender.
  ///
  /// Built from the offending packet's first 1232 bytes, which is what the
  /// error body is allowed to quote, so the sender can match it to its query.
  private static func icmpv6DestinationUnreachable(for packet: Data) -> Data? {
    guard packet.count >= 40, isIPv6(packet) else { return nil }
    let bytes = [UInt8](packet)
    let sender = Array(bytes[8..<40])
    let target = Array(bytes[24..<40])

    let quoted = Array(bytes.prefix(1232))
    var body: [UInt8] = [1, 0, 0, 0, 0, 0, 0, 0]
    body.append(contentsOf: quoted)

    var packetOut: [UInt8] = []
    packetOut.append(contentsOf: [0x60, 0, 0, 0])
    let payloadLength = UInt16(body.count)
    packetOut.append(UInt8(payloadLength >> 8))
    packetOut.append(UInt8(payloadLength & 0xFF))
    packetOut.append(contentsOf: [58, 255]) // ICMPv6, hop limit 255
    // The reply goes back the way the packet came: target first, sender second.
    packetOut.append(contentsOf: target)
    packetOut.append(contentsOf: sender)
    packetOut.append(contentsOf: body)

    let checksum = icmpv6Checksum(
      source: target,
      destination: sender,
      payload: body
    )
    packetOut[42] = UInt8(checksum >> 8)
    packetOut[43] = UInt8(checksum & 0xFF)
    return Data(packetOut)
  }

  private static func icmpv6Checksum(
    source: [UInt8],
    destination: [UInt8],
    payload: [UInt8]
  ) -> UInt16 {
    var sum: UInt32 = 0
    func add(_ value: UInt32) { sum = sum &+ value }
    for index in stride(from: 0, to: source.count, by: 2) {
      add((UInt32(source[index]) << 8) | UInt32(source[index + 1]))
    }
    for index in stride(from: 0, to: destination.count, by: 2) {
      add((UInt32(destination[index]) << 8) | UInt32(destination[index + 1]))
    }
    let length = UInt32(payload.count)
    add(length >> 16)
    add(length & 0xFFFF)
    add(58) // next header
    var index = 0
    while index + 1 < payload.count {
      add((UInt32(payload[index]) << 8) | UInt32(payload[index + 1]))
      index += 2
    }
    if index < payload.count {
      add(UInt32(payload[index]) << 8)
    }
    while (sum >> 16) != 0 {
      sum = (sum & 0xFFFF) &+ (sum >> 16)
    }
    return UInt16(~sum & 0xFFFF)
  }

  private static func err(_ code: Int, _ message: String) -> NSError {
    NSError(
      domain: "su.proxydom.app.vpn",
      code: code,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}

extension ShareTunnelEngine: Hy2bindPacketWriterProtocol {
  func writePacket(_ packet: Data?) throws {
    guard let packet, !packet.isEmpty, let provider else { return }
    egressPackets += 1
    let proto: NSNumber = {
      guard let first = packet.first else { return NSNumber(value: AF_INET) }
      return NSNumber(value: first >> 4 == 6 ? AF_INET6 : AF_INET)
    }()
    provider.packetFlow.writePackets([packet], withProtocols: [proto])
  }
}

/// The document and the address the tunnel is pinned to.
///
/// The document is the whole v2ray config the Dart side built; the address is
/// only for `tunnelRemoteAddress`, which NetworkExtension insists on and which
/// never reaches the core.
struct ShareStartConfig {
  let document: String
  let remoteHost: String

  init?(paramsJson: String) {
    guard
      let paramsData = paramsJson.data(using: .utf8),
      let params = (try? JSONSerialization.jsonObject(with: paramsData)) as? [String: Any],
      let document = params["vlessConfig"] as? String,
      !document.isEmpty,
      let documentData = document.data(using: .utf8),
      let documentRoot = (try? JSONSerialization.jsonObject(with: documentData)) as? [String: Any]
    else {
      return nil
    }
    if (documentRoot["engine"] as? String) == "reality" {
      // The REALITY document has no v2ray outbounds: the server is a top-level
      // field. NetworkExtension still needs a non-empty tunnelRemoteAddress,
      // and that address never reaches the engine.
      guard let host = documentRoot["server"] as? String, !host.isEmpty else {
        return nil
      }
      self.document = document
      self.remoteHost = host
      return
    }
    guard
      let outbounds = documentRoot["outbounds"] as? [[String: Any]],
      let first = outbounds.first,
      let settings = first["settings"] as? [String: Any],
      let host = ShareStartConfig.address(from: settings)
    else {
      return nil
    }
    self.document = document
    self.remoteHost = host
  }

  private static func address(from settings: [String: Any]) -> String? {
    if let vnext = settings["vnext"] as? [[String: Any]],
       let first = vnext.first,
       let address = first["address"] as? String,
       !address.isEmpty {
      return address
    }
    if let servers = settings["servers"] as? [[String: Any]],
       let first = servers.first,
       let address = first["address"] as? String,
       !address.isEmpty {
      return address
    }
    return nil
  }
}
