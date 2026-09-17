import Darwin
import Foundation
import Network
import NetworkExtension

/// Pure path-change reducer for Packet Tunnel Hy2 reset (testable without NE).
enum TunnelPathResetDecision: Equatable {
  case ignore
  case reset(reason: String)
}

struct TunnelPathSnapshot: Equatable {
  var satisfied: Bool
  var expensive: Bool
  var usesWifi: Bool
  var usesCellular: Bool
  var usesWired: Bool

  static func from(_ path: Network.NWPath) -> TunnelPathSnapshot {
    TunnelPathSnapshot(
      satisfied: path.status == .satisfied,
      expensive: path.isExpensive,
      usesWifi: path.usesInterfaceType(Network.NWInterface.InterfaceType.wifi),
      usesCellular: path.usesInterfaceType(Network.NWInterface.InterfaceType.cellular),
      usesWired: path.usesInterfaceType(Network.NWInterface.InterfaceType.wiredEthernet)
    )
  }
}

enum TunnelPathReducer {
  /// First callback is baseline only. Meaningful satisfied changes or return
  /// from unsatisfied → one reset reason string for Hy2bindResetNetwork.
  static func decide(
    previous: TunnelPathSnapshot?,
    next: TunnelPathSnapshot
  ) -> (TunnelPathResetDecision, TunnelPathSnapshot) {
    guard let previous else {
      return (.ignore, next)
    }
    if !previous.satisfied && next.satisfied {
      return (.reset(reason: "path_satisfied"), next)
    }
    if previous.satisfied && next.satisfied {
      let ifaceChanged =
        previous.usesWifi != next.usesWifi
        || previous.usesCellular != next.usesCellular
        || previous.usesWired != next.usesWired
        || previous.expensive != next.expensive
      if ifaceChanged {
        return (.reset(reason: "path_iface"), next)
      }
    }
    return (.ignore, next)
  }
}

enum TunnelRouteMerge {
  /// Deduped IPv4 /32 excludes: endpoint + control-plane hosts (IP literals only).
  static func ipv4Excludes(endpointHost: String, controlPlaneHosts: [String]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for host in [endpointHost] + controlPlaneHosts {
      let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, isIPv4Literal(trimmed), !seen.contains(trimmed) else { continue }
      seen.insert(trimmed)
      out.append(trimmed)
    }
    return out
  }

  /// Deduped IPv6 /128 excludes: endpoint + control-plane hosts (IP literals only).
  static func ipv6Excludes(endpointHost: String, controlPlaneHosts: [String]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for host in [endpointHost] + controlPlaneHosts {
      let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, isIPv6Literal(trimmed), !seen.contains(trimmed) else { continue }
      seen.insert(trimmed)
      out.append(trimmed)
    }
    return out
  }

  static func isIPv4Literal(_ host: String) -> Bool {
    var addr = in_addr()
    return host.withCString { inet_pton(AF_INET, $0, &addr) == 1 }
  }

  static func isIPv6Literal(_ host: String) -> Bool {
    var addr = in6_addr()
    return host.withCString { inet_pton(AF_INET6, $0, &addr) == 1 }
  }
}

enum TunnelStopIntent {
  /// A stop caused by explicit user/configuration intent must not resurrect.
  static func clearsSessionActive(_ reason: NEProviderStopReason) -> Bool {
    switch reason {
    case .userInitiated,
         .providerDisabled,
         .configurationDisabled,
         .configurationRemoved,
         .userLogout:
      return true
    default:
      return false
    }
  }
}
