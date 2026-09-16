import Flutter
import Foundation
import NetworkExtension
import UIKit

/// iOS side of MethodChannel `teremok/vpn` (same name as Android).
/// Starts `NETunnelProviderManager` → Packet Tunnel appex (ADR 019).
enum TeremokVpnChannel {
  static let methodChannelName = "teremok/vpn"
  static let statusEventChannelName = "teremok/vpn/status"
  static let sessionEventChannelName = "teremok/vpn/session"
  static let trafficEventChannelName = "teremok/vpn/traffic"
  static let pingEventChannelName = "teremok/vpn/ping"
  static let appGroupId = "group.online.teremokconnect.app"
  static let tunnelBundleId = "online.teremokconnect.app.VpnTunnelProvider"
  static let paramsKey = "vpn.paramsJson"
  static let statusKey = "vpn.status"
  static let lastErrorKey = "vpn.lastError"

  private static var statusHandler: StatusStreamHandler?
  private static var sessionHandler: SessionStreamHandler?
  private static var trafficHandler: StubMapStreamHandler?
  private static var pingHandler: StubMapStreamHandler?

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
      case "requestPermission":
        // Android: VpnService.prepare. iOS consent is the system VPN dialog on
        // startVPNTunnel — do not block Connect with MissingPluginException.
        result(true)
      case "requestNotificationPermission":
        // No Android-style POST_NOTIFICATIONS gate on consumer iOS VPN.
        result(true)
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

    let status = StatusStreamHandler()
    statusHandler = status
    FlutterEventChannel(name: statusEventChannelName, binaryMessenger: messenger)
      .setStreamHandler(status)

    let session = SessionStreamHandler()
    sessionHandler = session
    FlutterEventChannel(name: sessionEventChannelName, binaryMessenger: messenger)
      .setStreamHandler(session)

    let traffic = StubMapStreamHandler(payload: ["downlinkBps": 0, "uplinkBps": 0])
    trafficHandler = traffic
    FlutterEventChannel(name: trafficEventChannelName, binaryMessenger: messenger)
      .setStreamHandler(traffic)

    let ping = StubMapStreamHandler(payload: ["delayMs": NSNull()])
    pingHandler = ping
    FlutterEventChannel(name: pingEventChannelName, binaryMessenger: messenger)
      .setStreamHandler(ping)
  }

  private static func defaults() -> UserDefaults? {
    UserDefaults(suiteName: appGroupId)
  }

  private static func readStatus() -> String {
    defaults()?.string(forKey: statusKey) ?? "idle"
  }

  private static func publishStatus(_ status: String) {
    defaults()?.set(status, forKey: statusKey)
    statusHandler?.emit(status)
    sessionHandler?.emit(forStatus: status)
  }

  private static func startTunnel(paramsJson: String, result: @escaping FlutterResult) {
    guard !paramsJson.isEmpty else {
      result(
        FlutterError(code: "bad_args", message: "paramsJson empty", details: nil)
      )
      return
    }
    defaults()?.set(paramsJson, forKey: paramsKey)
    defaults()?.removeObject(forKey: lastErrorKey)
    publishStatus("connecting")

    loadManager(paramsJson: paramsJson) { manager, error in
      if let error {
        defaults()?.set(error.localizedDescription, forKey: lastErrorKey)
        publishStatus("idle")
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
        defaults()?.set(error.localizedDescription, forKey: lastErrorKey)
        publishStatus("idle")
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
      publishStatus("idle")
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
      if #available(iOS 14.2, *) {
        proto.excludeLocalNetworks = true
      }
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

  fileprivate static func mapNEVPNStatus(_ status: NEVPNStatus) -> String {
    switch status {
    case .invalid, .disconnected:
      return "idle"
    case .connecting, .reasserting:
      return "connecting"
    case .connected:
      return "connected"
    case .disconnecting:
      return "disconnecting"
    @unknown default:
      return "idle"
    }
  }
}

// MARK: - EventChannel handlers

private final class StatusStreamHandler: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var observer: NSObjectProtocol?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    events(TeremokVpnChannel.readStatusPublic())
    observer = NotificationCenter.default.addObserver(
      forName: .NEVPNStatusDidChange,
      object: nil,
      queue: .main
    ) { [weak self] note in
      guard let connection = note.object as? NEVPNConnection else { return }
      let mapped = TeremokVpnChannel.mapNEVPNStatus(connection.status)
      // Prefer App Group when extension already wrote honest status.
      let fromGroup = UserDefaults(suiteName: TeremokVpnChannel.appGroupId)?
        .string(forKey: TeremokVpnChannel.statusKey)
      let status = fromGroup ?? mapped
      self?.sink?(status)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let observer {
      NotificationCenter.default.removeObserver(observer)
    }
    observer = nil
    sink = nil
    return nil
  }

  func emit(_ status: String) {
    sink?(status)
  }
}

private final class SessionStreamHandler: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    events(Self.snapshot(for: TeremokVpnChannel.readStatusPublic()))
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  func emit(forStatus status: String) {
    sink?(Self.snapshot(for: status))
  }

  private static func snapshot(for status: String) -> [String: Any] {
    let phase: String
    switch status {
    case "connected":
      phase = "connectedHealthy"
    case "connecting", "preparing":
      phase = "binding"
    case "disconnecting":
      phase = "stopping"
    default:
      phase = "idle"
    }
    return [
      "phase": phase,
      "generation": 0,
      "reason": "none",
      "legacyStatus": status,
    ]
  }
}

private final class StubMapStreamHandler: NSObject, FlutterStreamHandler {
  private let payload: [String: Any]
  private var sink: FlutterEventSink?

  init(payload: [String: Any]) {
    self.payload = payload
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    events(payload)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }
}

extension TeremokVpnChannel {
  fileprivate static func readStatusPublic() -> String {
    readStatus()
  }
}
