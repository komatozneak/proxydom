import Flutter
import Foundation
import NetworkExtension
import UIKit

/// iOS side of MethodChannel `teremok/vpn` (same name as Android).
/// Starts `NETunnelProviderManager` → Packet Tunnel appex (ADR 019).
enum TeremokVpnChannel {
  static let methodChannelName = "teremok/vpn"
  static let appGroupId = "group.online.teremokconnect.app"
  static let tunnelBundleId = "online.teremokconnect.app.VpnTunnelProvider"
  static let paramsKey = "vpn.paramsJson"
  static let statusKey = "vpn.status"
  static let lastErrorKey = "vpn.lastError"

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "start":
        let args = call.arguments as? [String: Any]
        let paramsJson = args?["paramsJson"] as? String ?? ""
        startTunnel(paramsJson: paramsJson, result: result)
      case "startAuto":
        // iOS: first candidate only for now (Android proves sequentially).
        let args = call.arguments as? [String: Any]
        let list = args?["candidatesJson"] as? [String] ?? []
        guard let first = list.first else {
          result(
            FlutterError(code: "empty", message: "auto pool empty", details: nil)
          )
          return
        }
        startTunnel(paramsJson: first, result: result)
      case "stop", "wipeSession":
        stopTunnel(wipe: call.method == "wipeSession", result: result)
      case "getStatus":
        result(readStatus())
      case "hasActiveSession":
        result(readStatus() == "connected" || readStatus() == "connecting")
      case "getLastError":
        result(UserDefaults(suiteName: appGroupId)?.string(forKey: lastErrorKey))
      case "isLockdownEnabled", "queryLockdownState":
        // No Android-style Always-on lockdown API for consumer iOS VPN.
        result(call.method == "queryLockdownState" ? "unsupported" : false)
      case "openVpnSettings":
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
          result(true)
        } else {
          result(false)
        }
      case "getSingBoxStderrTail", "getVpnCoreStderrTail":
        result(UserDefaults(suiteName: appGroupId)?.string(forKey: lastErrorKey))
      case "getUnderlyingNetworkInterface":
        result(nil)
      case "requestAddQsTile", "isShadeNotificationEnabled",
           "setShadeNotificationEnabled", "listLauncherApps":
        result(FlutterMethodNotImplemented)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func defaults() -> UserDefaults? {
    UserDefaults(suiteName: appGroupId)
  }

  private static func readStatus() -> String {
    defaults()?.string(forKey: statusKey) ?? "idle"
  }

  private static func startTunnel(paramsJson: String, result: @escaping FlutterResult) {
    guard !paramsJson.isEmpty else {
      result(
        FlutterError(code: "bad_args", message: "paramsJson empty", details: nil)
      )
      return
    }
    defaults()?.set(paramsJson, forKey: paramsKey)
    defaults()?.set("connecting", forKey: statusKey)
    defaults()?.removeObject(forKey: lastErrorKey)

    loadManager(paramsJson: paramsJson) { manager, error in
      if let error {
        defaults()?.set("idle", forKey: statusKey)
        defaults()?.set(error.localizedDescription, forKey: lastErrorKey)
        result(
          FlutterError(
            code: "manager",
            message: error.localizedDescription,
            details: nil
          )
        )
        return
      }
      guard let manager else {
        result(
          FlutterError(code: "manager", message: "nil manager", details: nil)
        )
        return
      }
      do {
        try manager.connection.startVPNTunnel()
        // Honest Connected is decided by the extension (status App Group).
        // Flutter polls getStatus / EventChannel; return true = start requested.
        result(true)
      } catch {
        defaults()?.set("idle", forKey: statusKey)
        defaults()?.set(error.localizedDescription, forKey: lastErrorKey)
        result(
          FlutterError(
            code: "start",
            message: error.localizedDescription,
            details: nil
          )
        )
      }
    }
  }

  private static func stopTunnel(wipe: Bool, result: @escaping FlutterResult) {
    NETunnelProviderManager.loadAllFromPreferences { managers, _ in
      let ours = managers?.filter {
        ($0.protocolConfiguration as? NETunnelProviderProtocol)?
          .providerBundleIdentifier == tunnelBundleId
      } ?? []
      for manager in ours {
        manager.connection.stopVPNTunnel()
        if wipe {
          manager.isEnabled = false
          manager.saveToPreferences(completionHandler: nil)
        }
      }
      if wipe {
        defaults()?.removeObject(forKey: paramsKey)
      }
      defaults()?.set("idle", forKey: statusKey)
      result(true)
    }
  }

  private static func loadManager(
    paramsJson: String,
    completion: @escaping (NETunnelProviderManager?, Error?) -> Void
  ) {
    NETunnelProviderManager.loadAllFromPreferences { managers, error in
      if let error {
        completion(nil, error)
        return
      }
      let existing = managers?.first {
        ($0.protocolConfiguration as? NETunnelProviderProtocol)?
          .providerBundleIdentifier == tunnelBundleId
      }
      let manager = existing ?? NETunnelProviderManager()
      let proto = NETunnelProviderProtocol()
      proto.providerBundleIdentifier = tunnelBundleId
      proto.serverAddress = hostFromParams(paramsJson) ?? "Teremok VPN"
      proto.excludeLocalNetworks = true
      manager.protocolConfiguration = proto
      manager.localizedDescription = "Teremok VPN"
      manager.isEnabled = true
      manager.saveToPreferences { saveError in
        if let saveError {
          completion(nil, saveError)
          return
        }
        manager.loadFromPreferences { loadError in
          completion(manager, loadError)
        }
      }
    }
  }

  private static func hostFromParams(_ paramsJson: String) -> String? {
    guard
      let data = paramsJson.data(using: .utf8),
      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let server = obj["hysteriaServer"] as? String
    else {
      return nil
    }
    let host = server.split(separator: ":", maxSplits: 1).first.map(String.init)
    return host?.isEmpty == false ? host : nil
  }
}
