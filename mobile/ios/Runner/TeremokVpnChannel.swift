import Flutter
import Foundation
import NetworkExtension
import UIKit

/// iOS side of MethodChannel `teremok/vpn` (same name as Android).
/// Starts `NETunnelProviderManager` → Packet Tunnel appex (ADR 019).
private final class TunnelHealthOnce {
  var done = false
  let result: FlutterResult

  init(_ result: @escaping FlutterResult) {
    self.result = result
  }

  func finish(_ value: Any?) {
    DispatchQueue.main.async {
      guard !self.done else { return }
      self.done = true
      self.result(value)
    }
  }
}

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
  static let generationKey = "vpn.generation"
  /// How long stop waits for NEVPN disconnected before returning to Dart.
  private static let stopIdleTimeout: TimeInterval = 3.0
  /// How long start waits if the previous tunnel is still disconnecting.
  private static let startDisconnectWait: TimeInterval = 3.0

  private static var statusHandler: StatusStreamHandler?
  private static var sessionHandler: SessionStreamHandler?
  private static var trafficHandler: StubMapStreamHandler?
  private static var pingHandler: StubMapStreamHandler?
  /// Last observed system VPN status (NEVPNStatusDidChange + load callbacks).
  private static var cachedNEVPNStatus: NEVPNStatus = .invalid
  /// After first `loadAllFromPreferences`, `.invalid` is treated like disconnected.
  private static var nevpnPreferencesLoaded = false
  private static var nevpnObserver: NSObjectProtocol?

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
        let args = call.arguments as? [String: Any]
        let reason = args?["reason"] as? String
        stopTunnel(
          wipe: call.method == "wipeSession",
          reason: reason,
          result: result
        )
      case "getTunnelHealth":
        fetchTunnelHealth(result: result)
      case "getStatus":
        let s = resolveStatus(log: true)
        result(s)
      case "hasActiveSession":
        // Parity with Android KEY_ACTIVE — not live NEVPN (idle+session → reconnect).
        let active = TeremokVpnShared.isSessionActive()
        TeremokVpnShared.appendNativeLog(
          "channel.hasActiveSession=\(active) status=\(resolveStatus(log: false))"
        )
        result(active)
      case "getLastError":
        result(UserDefaults(suiteName: appGroupId)?.string(forKey: lastErrorKey))
      case "getNativeLogTail":
        result(TeremokVpnShared.nativeLogTail())
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
      case "setCoreLogLevel", "clearCoreLog":
        result(true)
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

    installNEVPNObserver()
    refreshCachedNEVPNStatus()
  }

  private static func defaults() -> UserDefaults? {
    UserDefaults(suiteName: appGroupId)
  }

  @discardableResult
  private static func bumpGeneration() -> Int {
    let next = (defaults()?.integer(forKey: generationKey) ?? 0) + 1
    defaults()?.set(next, forKey: generationKey)
    return next
  }

  private static func readAppGroupStatus() -> String {
    defaults()?.string(forKey: statusKey) ?? "idle"
  }

  /// Clear stale App Group `connected` when NEVPN is already down (iOS killed tunnel).
  private static func clearStaleAppGroupConnected() {
    let group = readAppGroupStatus()
    if group == "connected" || group == "connecting" {
      defaults()?.set("idle", forKey: statusKey)
    }
  }

  /// Live NEVPN is SoT. Never invent Connected from a leftover App Group row
  /// after iOS tears the Packet Tunnel down without our `stopTunnel`.
  private static func resolveStatus(log: Bool) -> String {
    let group = readAppGroupStatus()
    let out: String
    switch cachedNEVPNStatus {
    case .connecting, .reasserting:
      out = "connecting"
    case .connected:
      out = "connected"
    case .disconnecting, .disconnected:
      clearStaleAppGroupConnected()
      out = "idle"
    case .invalid:
      if !nevpnPreferencesLoaded {
        // Pre-load: never trust App Group Connected without live NEVPN.
        out = (group == "connected") ? "connecting" : group
      } else {
        clearStaleAppGroupConnected()
        out = "idle"
      }
    @unknown default:
      clearStaleAppGroupConnected()
      out = "idle"
    }
    if log {
      TeremokVpnShared.appendNativeLog(
        "channel.resolve nevpn=\(cachedNEVPNStatus.rawValue) group=\(group) out=\(out)"
      )
    }
    return out
  }

  private static func publishStatus(_ status: String) {
    defaults()?.set(status, forKey: statusKey)
    statusHandler?.emit(status)
    sessionHandler?.emit(forStatus: status)
  }

  private static func installNEVPNObserver() {
    if nevpnObserver != nil { return }
    nevpnObserver = NotificationCenter.default.addObserver(
      forName: .NEVPNStatusDidChange,
      object: nil,
      queue: .main
    ) { note in
      guard let connection = note.object as? NEVPNConnection else { return }
      cachedNEVPNStatus = connection.status
      let mapped = mapNEVPNStatus(connection.status)
      TeremokVpnShared.appendNativeLog(
        "NEVPNStatusDidChange raw=\(connection.status.rawValue) mapped=\(mapped)"
      )
      // Keep App Group honest when iOS drops the tunnel without channel.stop.
      if mapped == "idle" {
        clearStaleAppGroupConnected()
        defaults()?.set("idle", forKey: statusKey)
      }
      statusHandler?.emit(mapped)
      sessionHandler?.emit(forStatus: mapped)
    }
  }

  private static func refreshCachedNEVPNStatus() {
    NETunnelProviderManager.loadAllFromPreferences { managers, _ in
      nevpnPreferencesLoaded = true
      let ours = managers?.first {
        ($0.protocolConfiguration as? NETunnelProviderProtocol)?
          .providerBundleIdentifier == tunnelBundleId
      }
      if let ours {
        cachedNEVPNStatus = ours.connection.status
        if mapNEVPNStatus(ours.connection.status) == "idle" {
          clearStaleAppGroupConnected()
        }
      } else {
        // No manager → not connected.
        cachedNEVPNStatus = .disconnected
        clearStaleAppGroupConnected()
      }
      let out = resolveStatus(log: true)
      statusHandler?.emit(out)
      sessionHandler?.emit(forStatus: out)
    }
  }

  private static func startTunnel(paramsJson: String, result: @escaping FlutterResult) {
    guard !paramsJson.isEmpty else {
      result(
        FlutterError(code: "bad_args", message: "paramsJson empty", details: nil)
      )
      return
    }
    TeremokVpnShared.appendNativeLog("channel.startTunnel")
    bumpGeneration()
    defaults()?.set(paramsJson, forKey: paramsKey)
    defaults()?.removeObject(forKey: lastErrorKey)
    TeremokVpnShared.setSessionActive(true)
    publishStatus("connecting")

    loadManager(paramsJson: paramsJson) { manager, error in
      if let error {
        defaults()?.set(error.localizedDescription, forKey: lastErrorKey)
        TeremokVpnShared.setSessionActive(false)
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
        TeremokVpnShared.setSessionActive(false)
        result(
          FlutterError(code: "manager", message: "nil manager", details: nil)
        )
        return
      }
      cachedNEVPNStatus = manager.connection.status
      waitUntilNotDisconnecting(manager: manager, timeout: startDisconnectWait) {
        do {
          // Never start while still tearing down the previous tunnel.
          if manager.connection.status == .disconnecting {
            defaults()?.set(
              "previous tunnel still disconnecting",
              forKey: lastErrorKey
            )
            TeremokVpnShared.setSessionActive(false)
            publishStatus("idle")
            result(
              FlutterError(
                code: "start",
                message: "previous tunnel still disconnecting",
                details: nil
              )
            )
            return
          }
          try manager.connection.startVPNTunnel()
          cachedNEVPNStatus = manager.connection.status
          // Honest Connected is decided by the extension (status App Group).
          // Flutter polls getStatus / EventChannel; return true = start requested.
          result(true)
        } catch {
          defaults()?.set(error.localizedDescription, forKey: lastErrorKey)
          TeremokVpnShared.setSessionActive(false)
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
  }

  private static func stopTunnel(
    wipe: Bool,
    reason: String?,
    result: @escaping FlutterResult
  ) {
    let tag = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
    let reasonTag = (tag?.isEmpty == false) ? tag! : (wipe ? "wipe" : "user_tap")
    TeremokVpnShared.setLastStopReason(reasonTag)
    TeremokVpnShared.appendNativeLog(
      "channel.stopTunnel wipe=\(wipe) reason=\(reasonTag)"
    )
    // User-initiated stop — do not auto-reconnect.
    TeremokVpnShared.setSessionActive(false)
    NETunnelProviderManager.loadAllFromPreferences { managers, _ in
      nevpnPreferencesLoaded = true
      let ours = managers?.filter {
        ($0.protocolConfiguration as? NETunnelProviderProtocol)?
          .providerBundleIdentifier == tunnelBundleId
      } ?? []
      if ours.isEmpty {
        publishStatus("idle")
        cachedNEVPNStatus = .disconnected
        result(true)
        return
      }
      for manager in ours {
        let status = manager.connection.status
        TeremokVpnShared.appendNativeLog(
          "channel.stopTunnel nevpn=\(status.rawValue)"
        )
        if status == .connected || status == .connecting || status == .reasserting {
          manager.connection.stopVPNTunnel()
        }
        cachedNEVPNStatus = manager.connection.status
        if wipe {
          manager.isEnabled = false
          manager.saveToPreferences(completionHandler: nil)
        }
      }
      if wipe {
        defaults()?.removeObject(forKey: paramsKey)
      }
      // Do NOT publish idle yet — wait for real NEVPN disconnected so Dart
      // waitUntilNativeIdle / hot-switch start see the truth.
      waitUntilDisconnected(managers: ours, timeout: stopIdleTimeout) {
        cachedNEVPNStatus = .disconnected
        publishStatus("idle")
        result(true)
      }
    }
  }

  private static func fetchTunnelHealth(result: @escaping FlutterResult) {
    let once = TunnelHealthOnce(result)
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
      let persisted = TeremokVpnShared.lastTunnelHealth()
      once.finish(persisted.isEmpty ? nil : persisted)
    }
    NETunnelProviderManager.loadAllFromPreferences { managers, _ in
      nevpnPreferencesLoaded = true
      let ours = managers?.first {
        ($0.protocolConfiguration as? NETunnelProviderProtocol)?
          .providerBundleIdentifier == tunnelBundleId
      }
      guard
        let manager = ours,
        let session = manager.connection as? NETunnelProviderSession,
        manager.connection.status == .connected
          || manager.connection.status == .connecting
          || manager.connection.status == .reasserting
      else {
        let persisted = TeremokVpnShared.lastTunnelHealth()
        once.finish(persisted.isEmpty ? nil : persisted)
        return
      }
      let msg = "health".data(using: .utf8)!
      do {
        try session.sendProviderMessage(msg) { data in
          if let data, let s = String(data: data, encoding: .utf8), !s.isEmpty {
            once.finish(s)
            return
          }
          let persisted = TeremokVpnShared.lastTunnelHealth()
          once.finish(persisted.isEmpty ? nil : persisted)
        }
      } catch {
        let persisted = TeremokVpnShared.lastTunnelHealth()
        once.finish(persisted.isEmpty ? nil : persisted)
      }
    }
  }

  private static func waitUntilDisconnected(
    managers: [NETunnelProviderManager],
    timeout: TimeInterval,
    completion: @escaping () -> Void
  ) {
    let deadline = Date().addingTimeInterval(timeout)
    func poll() {
      let stillUp = managers.contains {
        let s = $0.connection.status
        return s == .connected || s == .connecting || s == .reasserting
          || s == .disconnecting
      }
      if !stillUp || Date() >= deadline {
        completion()
        return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: poll)
    }
    poll()
  }

  private static func waitUntilNotDisconnecting(
    manager: NETunnelProviderManager,
    timeout: TimeInterval,
    completion: @escaping () -> Void
  ) {
    let deadline = Date().addingTimeInterval(timeout)
    func poll() {
      cachedNEVPNStatus = manager.connection.status
      if manager.connection.status != .disconnecting || Date() >= deadline {
        completion()
        return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: poll)
    }
    poll()
  }

  private static func loadManager(
    paramsJson: String,
    completion: @escaping (NETunnelProviderManager?, Error?) -> Void
  ) {
    NETunnelProviderManager.loadAllFromPreferences { managers, error in
      nevpnPreferencesLoaded = true
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
          cachedNEVPNStatus = manager.connection.status
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
      // Surface as idle so Flutter does not keep Nest Connected during tear-down.
      return "idle"
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
      self?.sink?(mapped)
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
    resolveStatus(log: false)
  }
}
