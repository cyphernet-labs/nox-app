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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NoxBackup") {
      NoxBackup.register(with: registrar.messenger())
    }
  }
}

/// Keeps a folder out of the device's backups (phase 048): the app's data
/// folder goes to neither iCloud nor a backup to a computer. The conversation
/// comes back from the server once the device is paired again, and nothing on
/// this disk is worth carrying anywhere.
enum NoxBackup {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "nox/backup", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "exclude",
            let arguments = call.arguments as? [String: Any],
            let path = arguments["path"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      var url = URL(fileURLWithPath: path, isDirectory: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      do {
        try url.setResourceValues(values)
        result(true)
      } catch {
        // No path in the error: it names the folder, and errors reach logs.
        result(FlutterError(code: "exclude_failed", message: nil, details: nil))
      }
    }
  }
}
