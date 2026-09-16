import Foundation
import NetworkExtension

/// Shared App Group + UserDefaults keys (Runner ↔ Packet Tunnel).
enum TeremokVpnShared {
  static let appGroupId = "group.online.teremokconnect.app"
  static let tunnelBundleId = "online.teremokconnect.app.VpnTunnelProvider"
  static let paramsKey = "vpn.paramsJson"
  static let statusKey = "vpn.status"
  static let lastErrorKey = "vpn.lastError"

  static var defaults: UserDefaults? {
    UserDefaults(suiteName: appGroupId)
  }

  static func setStatus(_ status: String) {
    defaults?.set(status, forKey: statusKey)
  }

  static func setLastError(_ message: String?) {
    if let message {
      defaults?.set(message, forKey: lastErrorKey)
    } else {
      defaults?.removeObject(forKey: lastErrorKey)
    }
  }
}
