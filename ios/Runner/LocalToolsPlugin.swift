import Flutter
import UIKit
import UniformTypeIdentifiers

/// Explicit file/share actions never access the API session or account storage.
final class LocalToolsPlugin: NSObject, FlutterPlugin, UIDocumentPickerDelegate {
  private static let maximumBytes = 4 * 1024 * 1024
  private var pending: FlutterResult?
  private var exportURL: URL?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "org.mewx.wenku8/local_tools", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(LocalToolsPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "getKeepScreenOn":
      result(UIApplication.shared.isIdleTimerDisabled)
    case "keepScreenOn":
      UIApplication.shared.isIdleTimerDisabled = call.arguments as? Bool ?? false
      result(nil)
    case "shareText":
      guard let text = arguments["text"] as? String,
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        text.utf16.count <= 10000 else {
        result(FlutterError(code: "input", message: "Invalid share text", details: nil))
        return
      }
      guard let presenter = presenter(), presenter.presentedViewController == nil else {
        result(FlutterError(code: "busy", message: "Another sheet is already active", details: nil))
        return
      }
      let sheet = UIActivityViewController(activityItems: [text], applicationActivities: nil)
      // iPad requires an anchor even though the primary target is iPhone.
      sheet.popoverPresentationController?.sourceView = presenter.view
      sheet.popoverPresentationController?.sourceRect = CGRect(
        x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
      presenter.present(sheet, animated: true) { result(nil) }
    case "exportBackup", "importBackup":
      guard pending == nil, let presenter = presenter(),
        presenter.presentedViewController == nil else {
        result(FlutterError(code: "busy", message: "A document operation is already active", details: nil))
        return
      }
      let picker: UIDocumentPickerViewController
      if call.method == "exportBackup" {
        guard let text = arguments["text"] as? String,
          let data = text.data(using: .utf8), data.count <= Self.maximumBytes else {
          result(FlutterError(code: "size", message: "Backup exceeds the document limit", details: nil))
          return
        }
        do {
          let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wenku8-export-\(UUID().uuidString)", isDirectory: true)
          try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
          let requested = (arguments["name"] as? String ?? "wenku8-backup.json")
          let name = (requested as NSString).lastPathComponent
          let file = directory.appendingPathComponent(name.isEmpty ? "wenku8-backup.json" : name)
          exportURL = file
          try data.write(to: file, options: .atomic)
          if #available(iOS 14.0, *) {
            picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
          } else {
            picker = UIDocumentPickerViewController(url: file, in: .exportToService)
          }
        } catch {
          clearExport()
          result(FlutterError(code: "document", message: "Backup file could not be created", details: nil))
          return
        }
      } else if #available(iOS 14.0, *) {
        picker = UIDocumentPickerViewController(
          forOpeningContentTypes: [.json, .plainText, .data], asCopy: true)
      } else {
        picker = UIDocumentPickerViewController(
          documentTypes: ["public.json", "public.plain-text", "public.data"], in: .import)
      }
      pending = result
      picker.delegate = self
      picker.allowsMultipleSelection = false
      presenter.present(picker, animated: true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(exportURL == nil ? nil : false)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else {
      finish(exportURL == nil ? nil : false)
      return
    }
    if exportURL != nil {
      finish(true)
      return
    }
    // Bound the actual read, including cloud-backed providers whose size metadata may be stale.
    DispatchQueue.global(qos: .userInitiated).async {
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      do {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = handle.readData(ofLength: Self.maximumBytes + 1)
        guard data.count <= Self.maximumBytes, let text = String(data: data, encoding: .utf8) else {
          throw CocoaError(.fileReadCorruptFile)
        }
        DispatchQueue.main.async { self.finish(text) }
      } catch {
        DispatchQueue.main.async {
          self.finish(FlutterError(
            code: "document", message: "Document must be UTF-8 and no larger than 4 MB", details: nil))
        }
      }
    }
  }

  private func finish(_ value: Any?) {
    let result = pending
    pending = nil
    clearExport()
    result?(value)
  }

  private func clearExport() {
    if let file = exportURL {
      try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }
    exportURL = nil
  }

  private func presenter() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    return scene?.windows.first { $0.isKeyWindow }?.rootViewController
  }
}
