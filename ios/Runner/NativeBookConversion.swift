import Foundation
import WenkuBookEngine

/// Mirrors the public Dart import limits; source handles are never unbounded.
enum BookImportFormatPolicy {
  static let extensions: Set<String> = ["txt", "epub", "zip", "pdf", "mobi", "azw", "azw3", "prc", "fb2", "doc", "docx", "rtf", "html", "htm", "xhtml", "md", "markdown"]
  static func byteLimit(_ ext: String) -> Int {
    switch ext.lowercased() {
    case "epub", "pdf", "docx", "zip": return 512 * 1024 * 1024
    case "mobi", "azw", "azw3", "prc": return 256 * 1024 * 1024
    case "html", "htm", "xhtml", "md", "markdown": return 32 * 1024 * 1024
    default: return 128 * 1024 * 1024
    }
  }
}

/// Converts only app-owned working copies into an empty cache subdirectory.
final class NativeBookConversion {
  private let documents: ManagedBookDocuments
  private let portableRoot: URL

  init(documents: ManagedBookDocuments, portableRoot: URL) throws {
    self.documents = documents
    self.portableRoot = portableRoot.standardizedFileURL.resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: self.portableRoot, withIntermediateDirectories: true)
  }

  private func outputDirectory(_ path: String) throws -> URL {
    let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
    guard url.path.hasPrefix(portableRoot.path + "/") else {
      throw BookDocumentFailure(code: "conversion_path", message: "转换目录不属于导入缓存")
    }
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    guard try FileManager.default.contentsOfDirectory(atPath: url.path).isEmpty else {
      throw BookDocumentFailure(code: "conversion_path", message: "转换目录必须为空")
    }
    return url
  }

  func extractKindle(_ path: String, output: String) throws -> Int {
    let source = try documents.readableSourceURL(path)
    let destination = try outputDirectory(output)
    return Int(source.path.withCString { input in
      destination.path.withCString { directory in wenku_export_mobi(input, directory) }
    })
  }

  func extractPdf(_ path: String, output: String, name: String) throws {
    let source = try documents.readableSourceURL(path)
    let destination = try outputDirectory(output)
    try NativePdfImport.extract(source, output: destination, name: name)
  }
}
