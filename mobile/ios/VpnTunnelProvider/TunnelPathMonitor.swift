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

struct HostRouteAddresses: Equatable {
  var v4: [String]
  var v6: [String]
}

struct TunnelRoutePlan: Equatable {
  var v4: [String]
  var v6: [String]
  var requestedHosts: Int
  var completedHosts: Int
  var resolvedHosts: Int
  var droppedIPv4: Int
  var droppedIPv6: Int
  var timedOut: Bool

  var capped: Bool {
    droppedIPv4 > 0 || droppedIPv6 > 0
  }
}

/// Thread-safe collector. `finish` closes the batch so late getaddrinfo results
/// cannot mutate state after a timeout snapshot has been returned.
final class LockedHostResolutionResults {
  private let lock = NSLock()
  private var accepting = true
  private var results: [Int: HostRouteAddresses] = [:]
  private var completed = 0

  func submit(index: Int, addresses: HostRouteAddresses) {
    lock.lock()
    defer { lock.unlock() }
    guard accepting else { return }
    completed += 1
    results[index] = addresses
  }

  func finish() -> (results: [Int: HostRouteAddresses], completed: Int) {
    lock.lock()
    defer { lock.unlock() }
    accepting = false
    return (results, completed)
  }
}

enum TunnelRoutePlanner {
  /// Base endpoint/control-plane routes are never dropped. Ordered host results
  /// are custom first, catalog second, so route caps are deterministic.
  static func build(
    baseIPv4: [String],
    baseIPv6: [String],
    orderedHostResults: [HostRouteAddresses],
    requestedHosts: Int,
    completedHosts: Int,
    timedOut: Bool,
    maxIPv4: Int,
    maxIPv6: Int
  ) -> TunnelRoutePlan {
    var v4 = orderedUnique(baseIPv4)
    var v6 = orderedUnique(baseIPv6)
    var seenV4 = Set(v4)
    var seenV6 = Set(v6)
    var resolvedHosts = 0
    var droppedV4 = 0
    var droppedV6 = 0

    for addresses in orderedHostResults {
      if !addresses.v4.isEmpty || !addresses.v6.isEmpty {
        resolvedHosts += 1
      }
      for address in addresses.v4 where !seenV4.contains(address) {
        seenV4.insert(address)
        if v4.count < maxIPv4 {
          v4.append(address)
        } else {
          droppedV4 += 1
        }
      }
      for address in addresses.v6 where !seenV6.contains(address) {
        seenV6.insert(address)
        if v6.count < maxIPv6 {
          v6.append(address)
        } else {
          droppedV6 += 1
        }
      }
    }

    return TunnelRoutePlan(
      v4: v4,
      v6: v6,
      requestedHosts: requestedHosts,
      completedHosts: completedHosts,
      resolvedHosts: resolvedHosts,
      droppedIPv4: droppedV4,
      droppedIPv6: droppedV6,
      timedOut: timedOut
    )
  }

  static func orderedUnique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
  }
}
