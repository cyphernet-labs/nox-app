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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NoxSave") {
      NoxSave.register(with: registrar)
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

/// The save dialog of the file view (5.3): Files' export picker, handed the
/// plain copy of the file (phase 048), which it copies to the place the
/// person chose. file_selector has no save dialog on iOS - its
/// getSaveLocation is not implemented there.
final class NoxSave: NSObject, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
  private let registrar: FlutterPluginRegistrar
  /// The answer the open picker owes; one picker at a time.
  private var pending: FlutterResult?

  private init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let save = NoxSave(registrar: registrar)
    let channel = FlutterMethodChannel(name: "nox/save", binaryMessenger: registrar.messenger())
    // The handler keeps the instance for as long as the engine lives.
    channel.setMethodCallHandler(save.handle)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "save",
          let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String
    else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard pending == nil else {
      result(FlutterError(code: "busy", message: nil, details: nil))
      return
    }
    guard var top = registrar.viewController else {
      result(FlutterError(code: "no_view", message: nil, details: nil))
      return
    }
    while let presented = top.presentedViewController {
      top = presented
    }
    let file = URL(fileURLWithPath: path)
    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
    } else {
      picker = UIDocumentPickerViewController(url: file, in: .exportToService)
    }
    picker.delegate = self
    picker.presentationController?.delegate = self
    pending = result
    top.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    finish(true)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(false)
  }

  /// Swiped down: the picker goes without calling either of the two above.
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    finish(false)
  }

  private func finish(_ saved: Bool) {
    let result = pending
    pending = nil
    result?(saved)
  }
}
