import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let appIconChannel = "majidalbana/app_icon"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      FlutterMethodChannel(
        name: appIconChannel,
        binaryMessenger: controller.binaryMessenger
      ).setMethodCallHandler { call, result in
        if call.method == "setAppIcon" {
          let args = call.arguments as? [String: Any]
          let isDark = args?["isDark"] as? Bool ?? false
          self.setAppIcon(isDark: isDark, result: result)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func setAppIcon(isDark: Bool, result: @escaping FlutterResult) {
    guard UIApplication.shared.supportsAlternateIcons else {
      result(false)
      return
    }

    let targetIconName: String? = isDark ? "AppIconBlackAlt" : "AppIconWhiteAlt"

    if UIApplication.shared.alternateIconName == targetIconName {
      result(true)
      return
    }

    UIApplication.shared.setAlternateIconName(targetIconName) { error in
      result(error == nil)
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
