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
  /// Ring buffer for Runner + Packet Tunnel lines (no secrets) → diagnostics.
  static let nativeLogKey = "vpn.nativeLog"
  static let nativeLogMaxLines = 128

  static var defaults: UserDefaults? {
    UserDefaults(suiteName: appGroupId)
  }

  private static let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()

  /// Append one line to the App Group ring (survives UI kill / appex stop).
  static func appendNativeLog(_ message: String) {
    let stamp = isoFormatter.string(from: Date())
    let line = "\(stamp) \(message)"
    var lines = defaults?.stringArray(forKey: nativeLogKey) ?? []
    lines.append(line)
    if lines.count > nativeLogMaxLines {
      lines = Array(lines.suffix(nativeLogMaxLines))
    }
    defaults?.set(lines, forKey: nativeLogKey)
  }

  static func nativeLogTail() -> String {
    let lines = defaults?.stringArray(forKey: nativeLogKey) ?? []
    return lines.isEmpty ? "(empty)" : lines.joined(separator: "\n")
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
