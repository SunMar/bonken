import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var brightnessChannel: FlutterMethodChannel?
  private var savedBrightness: CGFloat?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerBrightnessChannel(with: engineBridge)
  }

  // Self-written screen-brightness channel (no third-party dependency). The
  // channel name is derived from the bundle identifier so it matches the Dart
  // side (package_info's packageName) without hardcoding the app id.
  private func registerBrightnessChannel(with engineBridge: FlutterImplicitEngineBridge) {
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BonkenBrightness")
    else { return }
    let name = "\(Bundle.main.bundleIdentifier ?? "")/brightness"
    let channel = FlutterMethodChannel(name: name, binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "setMax":
        // UIScreen.main.brightness is global; save it once so `reset` restores
        // exactly what the user had before.
        if self.savedBrightness == nil {
          self.savedBrightness = UIScreen.main.brightness
        }
        UIScreen.main.brightness = 1.0
        result(nil)
      case "reset":
        if let saved = self.savedBrightness {
          UIScreen.main.brightness = saved
          self.savedBrightness = nil
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    brightnessChannel = channel
  }
}
