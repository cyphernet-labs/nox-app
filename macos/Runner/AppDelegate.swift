import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

/// Keeps a folder out of the Mac's backups (phase 048): Time Machine skips
/// the app's data folder. The conversation comes back from the server once
/// the device is paired again, and nothing on this disk is worth carrying to
/// another Mac. Registered by the main window, with the engine it creates,
/// before the app's Dart code can call it.
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
