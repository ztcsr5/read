import Flutter
import Network
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let localNetworkPermissionHelper = LocalNetworkPermissionHelper()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "read/local_network",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
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
        self?.localNetworkPermissionHelper.request(timeoutMs: timeoutMs) { status in
          result(status)
        }
      }
    }
    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

private final class LocalNetworkPermissionHelper {
  private let serviceType = "_preflight_check._tcp"
  private let queue = DispatchQueue(label: "read.local-network-preflight")
  private var listener: NWListener?
  private var browser: NWBrowser?
  private var completion: ((String) -> Void)?
  private var resolved = false

  func request(timeoutMs: Int, completion: @escaping (String) -> Void) {
    queue.async {
      self.cancelLocked()
      self.resolved = false
      self.completion = completion

      do {
        let listenerParameters = NWParameters(tls: .none, tcp: NWProtocolTCP.Options())
        listenerParameters.includePeerToPeer = true
        let listener = try NWListener(using: listenerParameters)
        listener.service = NWListener.Service(
          name: UUID().uuidString,
          type: self.serviceType
        )
        listener.newConnectionHandler = { connection in
          connection.cancel()
        }
        listener.stateUpdateHandler = { [weak self] state in
          self?.handle(state: state)
        }

        let browserParameters = NWParameters()
        browserParameters.includePeerToPeer = true
        let browser = NWBrowser(
          for: .bonjour(type: self.serviceType, domain: nil),
          using: browserParameters
        )
        browser.stateUpdateHandler = { [weak self] state in
          self?.handle(state: state)
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
          if !results.isEmpty {
            self?.finish("granted")
          }
        }

        self.listener = listener
        self.browser = browser
        listener.start(queue: self.queue)
        browser.start(queue: self.queue)

        let deadline = DispatchTime.now() + .milliseconds(max(800, timeoutMs))
        self.queue.asyncAfter(deadline: deadline) { [weak self] in
          self?.finish("timeout")
        }
      } catch {
        self.finish("failed:\(error.localizedDescription)")
      }
    }
  }

  private func handle(state: NWListener.State) {
    switch state {
    case .failed(let error):
      finish(status(for: error))
    case .waiting(let error):
      if isPolicyDenied(error) {
        finish("denied")
      }
    default:
      break
    }
  }

  private func handle(state: NWBrowser.State) {
    switch state {
    case .failed(let error):
      finish(status(for: error))
    case .waiting(let error):
      if isPolicyDenied(error) {
        finish("denied")
      }
    default:
      break
    }
  }

  private func status(for error: NWError) -> String {
    isPolicyDenied(error) ? "denied" : "failed:\(error.localizedDescription)"
  }

  private func isPolicyDenied(_ error: NWError) -> Bool {
    String(describing: error).contains("PolicyDenied") ||
      String(describing: error).contains("policy denied")
  }

  private func finish(_ status: String) {
    queue.async {
      guard !self.resolved else { return }
      self.resolved = true
      let completion = self.completion
      self.completion = nil
      self.cancelLocked()
      DispatchQueue.main.async {
        completion?(status)
      }
    }
  }

  private func cancelLocked() {
    browser?.cancel()
    listener?.cancel()
    browser = nil
    listener = nil
  }
}
