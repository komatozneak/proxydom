import Foundation
import NetworkExtension

/// Shared App Group + UserDefaults keys (Runner ↔ Packet Tunnel).
enum TeremokVpnShared {
  static let appGroupId = "group.online.teremokconnect.app"
  static let tunnelBundleId = "online.teremokconnect.app.VpnTunnelProvider"
  static let paramsKey = "vpn.paramsJson"
  static let statusKey = "vpn.status"
  static let lastErrorKey = "vpn.lastError"
  /// Bumped by Runner on each start so a late `stopTunnel` cannot wipe
  /// status / lastError from a newer connect (YouTube hot-switch race).
  static let generationKey = "vpn.generation"

  static var defaults: UserDefaults? {
    UserDefaults(suiteName: appGroupId)
  }

  static func currentGeneration() -> Int {
    defaults?.integer(forKey: generationKey) ?? 0
  }

  /// Returns the new generation after bump.
  @discardableResult
  static func bumpGeneration() -> Int {
    let next = currentGeneration() + 1
    defaults?.set(next, forKey: generationKey)
    return next
  }

  static func setStatus(_ status: String, generation: Int? = nil) {
    if let generation, generation != currentGeneration() { return }
    defaults?.set(status, forKey: statusKey)
  }

  static func setLastError(_ message: String?, generation: Int? = nil) {
    if let generation, generation != currentGeneration() { return }
    if let message {
      defaults?.set(message, forKey: lastErrorKey)
    } else {
      defaults?.removeObject(forKey: lastErrorKey)
    }
  }
}
