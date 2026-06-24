import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private let appIconChannel = "majidalbana/app_icon"

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    registerAppIconChannel()
  }

  private func registerAppIconChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else { return }

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

  private func setAppIcon(isDark: Bool, result: @escaping FlutterResult) {
    guard UIApplication.shared.supportsAlternateIcons else {
      result(false)
      return
    }

    let targetIconName: String? = isDark ? "AppIconBlackAlt" : nil

    if UIApplication.shared.alternateIconName == targetIconName {
      result(true)
      return
    }

    UIApplication.shared.setAlternateIconName(targetIconName) { error in
      result(error == nil)
    }
  }
}
