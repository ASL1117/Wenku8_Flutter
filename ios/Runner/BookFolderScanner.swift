import Foundation

/// Folder bookmarks authorize reads only. Import acknowledgement never deletes
/// or moves source files, and cancelled scans leave pending members retryable.
final class BookFolderScanner {
  private struct Configuration: Codable {
    var bookmark: Data?
    var applicationDocuments = false
    var automatic = false
    var extensions = ["txt", "epub", "zip", "pdf", "mobi", "azw", "azw3", "prc", "html", "htm", "xhtml", "md", "markdown", "fb2", "docx", "rtf"]
    var imported = [String: String]()
  }
  private struct Member { let url: URL; let key: String; let fingerprint: String }
  private let stateFile: URL
  private let documentsDirectory: URL
  private var configuration: Configuration
  private var members = [String: Member]()
  private var scope: URL?
  private var scoped = false
  init(stateFile: URL, documentsDirectory: URL) throws {
    self.stateFile = stateFile
    self.documentsDirectory = documentsDirectory
    configuration = FileManager.default.fileExists(atPath: stateFile.path)
      ? try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: stateFile)) : Configuration()
  }
  deinit { if scoped { scope?.stopAccessingSecurityScopedResource() } }
  private func save(_ value: Configuration) throws {
    try FileManager.default.createDirectory(at: stateFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(value).write(to: stateFile, options: .atomic)
    configuration = value
  }
  private func folder() throws -> URL? {
    if configuration.applicationDocuments { return documentsDirectory }
    guard let bookmark = configuration.bookmark else { return nil }
    var stale = false
    let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    if stale {
      let access = url.startAccessingSecurityScopedResource()
      defer { if access { url.stopAccessingSecurityScopedResource() } }
      var next = configuration
      next.bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
      try save(next)
    }
    return url
  }
  func info() throws -> [String: Any]? {
    guard configuration.applicationDocuments || configuration.bookmark != nil else { return nil }
    guard let url = try? folder() else { return ["name": "扫描目录", "readable": false, "automatic": configuration.automatic, "all": false] }
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    let readable = FileManager.default.isReadableFile(atPath: url.path)
    return ["name": url.lastPathComponent, "readable": readable, "automatic": configuration.automatic, "all": configuration.applicationDocuments]
  }
  func select(_ url: URL) throws -> [String: Any]? {
    let access = url.startAccessingSecurityScopedResource()
    defer { if access { url.stopAccessingSecurityScopedResource() } }
    guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw invalid() }
    var next = Configuration()
    next.bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    try save(next)
    return try info()
  }
  func selectApplicationDocuments() throws -> [String: Any]? {
    var next = Configuration(); next.applicationDocuments = true
    try save(next); return try info()
  }
  func formats() throws -> [String] { configuration.extensions }
  func setFormats(_ formats: [String]) throws {
    let supported = Set(Configuration().extensions)
    guard !formats.isEmpty, formats.allSatisfy({ supported.contains($0) }) else { throw invalid() }
    var next = configuration; next.extensions = Array(Set(formats)).sorted(); try save(next)
  }
  func setAutomatic(_ value: Bool) throws { var next = configuration; next.automatic = value; try save(next) }
  func disconnect() throws { try finish(); try save(Configuration()) }
  private func fingerprint(_ url: URL) throws -> String {
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
    return "\(values.fileSize ?? -1):\(values.contentModificationDate?.timeIntervalSince1970 ?? -1)"
  }
  func scan() throws -> [String: Any] {
    try finish()
    guard let folder = try folder() else { throw invalid() }
    scoped = folder.startAccessingSecurityScopedResource(); scope = folder
    let root = folder.standardizedFileURL.resolvingSymlinksInPath().path
    var warnings = [String](), books = [[String: Any]](), total = 0, unchanged = 0
    guard let enumeration = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles], errorHandler: { _, _ in
      if warnings.count < 20 { warnings.append("部分文件无法读取，请检查目录授权") }; return true
    }) else { try finish(); throw invalid() }
    for case let url as URL in enumeration {
      let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
      guard values.isRegularFile == true, values.isSymbolicLink != true,
        configuration.extensions.contains(url.pathExtension.lowercased()) else { continue }
      let canonical = url.standardizedFileURL.resolvingSymlinksInPath().path
      guard canonical.hasPrefix(root + "/") else { continue }
      total += 1
      if total > 10000 { warnings.append("目录超过一万本，请选择较小目录分批扫描"); break }
      let key = String(canonical.dropFirst(root.count + 1)), stamp = try fingerprint(url)
      if configuration.imported[key] == stamp { unchanged += 1; continue }
      let token = UUID().uuidString
      members[token] = Member(url: url, key: key, fingerprint: stamp)
      books.append(["token": token, "name": url.lastPathComponent, "size": values.fileSize ?? 0, "folder": (key as NSString).deletingLastPathComponent])
    }
    return ["books": books, "total": total, "unchanged": unchanged, "warnings": warnings]
  }
  func stage(_ token: String, documents: ManagedBookDocuments) throws -> [String: Any] {
    guard let member = members[token] else { throw invalid() }
    let output = try documents.copy(member.url, maximumBytes: BookImportFormatPolicy.byteLimit(member.url.pathExtension))
    return ["name": member.url.lastPathComponent, "path": output.path]
  }
  func link(_ token: String, documents: LinkedBookDocuments) throws -> [String: Any] {
    guard let member = members[token], let scope else { throw invalid() }
    return try documents.retain(member.url, relativeTo: scope)
  }
  func markImported(_ token: String) throws {
    guard let member = members[token], try fingerprint(member.url) == member.fingerprint else { throw invalid() }
    var next = configuration; next.imported[member.key] = member.fingerprint; try save(next)
  }
  func finish() throws {
    members.removeAll()
    if scoped { scope?.stopAccessingSecurityScopedResource() }
    scope = nil; scoped = false
  }
  private func invalid() -> BookDocumentFailure { BookDocumentFailure(code: "scan_permission", message: "扫描目录或文件已不可用，请重新授权后重试") }
}
