import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private let localNetworkPermissionHelper = LocalNetworkPermissionHelper()
  private var localNetworkChannel: FlutterMethodChannel?

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    guard localNetworkChannel == nil,
      let controller = window?.rootViewController as? FlutterViewController
    else {
      return
    }
    localNetworkChannel = FlutterMethodChannel(
      name: "read/local_network",
      binaryMessenger: controller.binaryMessenger
    )
    localNetworkChannel?.setMethodCallHandler { [weak self] call, result in
      self?.handleLocalNetworkCall(call, result: result)
    }
  }

  private func handleLocalNetworkCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "requestLocalNetworkAuthorization" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard #available(iOS 14.0, *) else {
      result("not_required")
      return
    }
    let args = call.arguments as? [String: Any]
    let timeoutMs = args?["timeoutMs"] as? Int ?? 2500
    localNetworkPermissionHelper.request(timeoutMs: timeoutMs) { status in
      result(status)
    }
  }
}
