import AppTrackingTransparency
import AdSupport
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let attChannel = FlutterMethodChannel(
      name: "com.manjot.car_parking_jam/att",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )

    attChannel.setMethodCallHandler { [weak self] call, result in
      if call.method == "requestTrackingAuthorization" {
        self?.requestATTWhenActive(attempt: 0, result: result)
      } else if call.method == "getTrackingStatus" {
        if #available(iOS 14, *) {
          result(self?.statusToString(ATTrackingManager.trackingAuthorizationStatus) ?? "unknown")
        } else {
          result("authorized")
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func requestATTWhenActive(attempt: Int, result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      guard #available(iOS 14, *) else {
        result("authorized")
        return
      }

      // iOS 15+ requires UIApplication.shared.applicationState == .active
      // before ATTrackingManager.requestTrackingAuthorization will display the prompt.
      if UIApplication.shared.applicationState != .active && attempt < 15 {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
          self?.requestATTWhenActive(attempt: attempt + 1, result: result)
        }
        return
      }

      ATTrackingManager.requestTrackingAuthorization { [weak self] status in
        DispatchQueue.main.async {
          result(self?.statusToString(status) ?? "unknown")
        }
      }
    }
  }

  @available(iOS 14, *)
  private func statusToString(_ status: ATTrackingManager.AuthorizationStatus) -> String {
    switch status {
    case .authorized:
      return "authorized"
    case .denied:
      return "denied"
    case .restricted:
      return "restricted"
    case .notDetermined:
      return "notDetermined"
    @unknown default:
      return "unknown"
    }
  }
}
