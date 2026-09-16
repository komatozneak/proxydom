import Flutter
import UIKit

// Flutter 3.35.1 (CI pin): no FlutterImplicitEngineDelegate yet (that lands in 3.41).
// Plugins still register here. Method channel: SceneDelegate after the engine exists.
@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
