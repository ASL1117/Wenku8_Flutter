import CryptoKit
import CoreFoundation
import Flutter
import Foundation
import ImageIO
import Security

/// The relay's public envelope works on iOS without the Android native library.
final class Wenku8Bridge: NSObject, FlutterPlugin {
  private let content = OperationQueue()
  private let accounts = DispatchQueue(label: "org.mewx.wenku8.accounts")
  private let images = DispatchQueue(label: "org.mewx.wenku8.images")
  private let revisionLock = NSLock()
  private var revision = 0
  // Access to the cookie and Keychain is confined to the account queue.
  private var sessionLoaded = false
  private var sessionCookie: String?
  private let store = WenkuSessionStore()
  private let imageDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("wenku8-illustrations-v1", isDirectory: true)

  override init() {
    super.init()
    content.maxConcurrentOperationCount = 4
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "org.mewx.wenku8/legacy_api", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(Wenku8Bridge(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let accountMethods = ["login", "accountRequest", "hasSession", "clearSession"]
    let imageMethods = ["illustration", "clearIllustrations"]
    guard (accountMethods + imageMethods + ["request", "requestBytes", "cover", "encodeReview"]).contains(call.method) else {
      result(FlutterMethodNotImplemented)
      return
    }
    revisionLock.lock()
    let queuedRevision = revision
    revisionLock.unlock()
    let account = accountMethods.contains(call.method)
    let work: () -> Void = {
      do {
        if account && !self.sessionLoaded {
          self.sessionCookie = try self.store.read()
          self.sessionLoaded = true
        }
        let value = try self.perform(call, queuedRevision: queuedRevision)
        DispatchQueue.main.async { result(value) }
      } catch WenkuError.reviewEncoding {
        DispatchQueue.main.async {
          result(FlutterError(code: "REVIEW_ENCODING", message: "Characters outside the review encoding", details: nil))
        }
      } catch {
        // Never return or log actions, credentials, cookies or transport exceptions.
        DispatchQueue.main.async {
          result(FlutterError(code: "LEGACY_API_ERROR", message: "Request or local storage failed", details: nil))
        }
      }
    }
    if account { accounts.async(execute: work) }
    else if imageMethods.contains(call.method) { images.async(execute: work) }
    else { content.addOperation(work) }
  }

  private func perform(_ call: FlutterMethodCall, queuedRevision: Int) throws -> Any? {
    let arguments = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "hasSession": return sessionCookie != nil
    case "clearSession":
      try store.write(nil)
      sessionCookie = nil
      advanceRevision()
      return nil
    case "encodeReview":
      guard let text = arguments["text"] as? String, text.utf16.count <= 10_000 else { throw WenkuError.invalid }
      return try WenkuWire.encodeReview(text)
    case "illustration":
      guard let raw = arguments["url"] as? String else { throw WenkuError.invalid }
      return FlutterStandardTypedData(bytes: try illustration(raw))
    case "clearIllustrations":
      if FileManager.default.fileExists(atPath: imageDirectory.path) {
        try FileManager.default.removeItem(at: imageDirectory)
      }
      return nil
    default: break
    }
    let action: String
    if call.method == "cover" {
      guard let id = arguments["aid"] as? Int, id > 0 else { throw WenkuError.invalid }
      action = "action=book&do=cover&aid=\(id)"
    } else {
      guard let raw = arguments["action"] as? String,
        !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, raw.utf16.count <= 60_000 else {
        throw WenkuError.invalid
      }
      action = raw
    }
    if call.method == "login" {
      guard action.hasPrefix("action=login&") || action.hasPrefix("action=loginemail&") else { throw WenkuError.invalid }
      let reply = try request(action, cookie: nil)
      let text = String(decoding: reply.data, as: UTF8.self)
      if text.trimmingCharacters(in: .whitespacesAndNewlines) == "1" {
        guard let cookie = reply.cookie else { throw WenkuError.invalid }
        try store.write(cookie)
        sessionCookie = cookie
        advanceRevision()
      }
      return text
    }
    if call.method == "accountRequest" {
      revisionLock.lock()
      let currentRevision = revision
      revisionLock.unlock()
      guard currentRevision == queuedRevision else { throw WenkuError.invalid }
      guard let cookie = sessionCookie else { return "4" }
      let reply = try request(action, cookie: cookie)
      let text = String(decoding: reply.data, as: UTF8.self)
      if let updated = reply.cookie, updated != cookie, text.trimmingCharacters(in: .whitespacesAndNewlines) != "4" {
        try store.write(updated)
        sessionCookie = updated
      }
      return text
    }
    // Public content never sends or updates the account cookie.
    let reply = try request(action, cookie: nil)
    if call.method == "request" { return String(decoding: reply.data, as: UTF8.self) }
    return FlutterStandardTypedData(bytes: reply.data)
  }

  private func advanceRevision() {
    revisionLock.lock()
    revision += 1
    revisionLock.unlock()
  }

  private func request(_ action: String, cookie: String?) throws -> (data: Data, cookie: String?) {
    var request = WenkuWire.request(action: action)
    if let cookie = cookie { request.setValue("PHPSESSID=\(cookie)", forHTTPHeaderField: "Cookie") }
    let reply = try WenkuDownload.fetch(request)
    guard (200...299).contains(reply.response.statusCode) else { throw WenkuError.invalid }
    return (reply.data, WenkuWire.sessionCookie(reply.response))
  }

  private func illustration(_ raw: String) throws -> Data {
    let url = try WenkuIllustrationPolicy.parse(raw)
    let name = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    let file = imageDirectory.appendingPathComponent(name)
    if FileManager.default.fileExists(atPath: file.path) {
      do {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let length = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard (1...WenkuDownload.limit).contains(length) else { throw WenkuError.invalid }
        let data = try Data(contentsOf: file)
        try WenkuIllustrationPolicy.validateImage(data)
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        return data
      } catch { try? FileManager.default.removeItem(at: file) }
    }
    let data = try downloadIllustration(url)
    do {
      try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
      try data.write(to: file, options: .atomic)
      try trimImageCache(keeping: file)
    } catch { /* Online images remain readable if the cache is unavailable. */ }
    return data
  }

  private func downloadIllustration(_ source: URL) throws -> Data {
    var url = source
    for hop in 0...3 {
      var request = URLRequest(url: url)
      request.setValue(WenkuWire.userAgent, forHTTPHeaderField: "User-Agent")
      let reply = try WenkuDownload.fetch(request)
      if [301, 302, 303, 307, 308].contains(reply.response.statusCode) {
        guard hop < 3, let location = reply.response.value(forHTTPHeaderField: "Location") else { throw WenkuError.invalid }
        url = try WenkuIllustrationPolicy.redirect(from: url, location: location)
      } else {
        guard (200...299).contains(reply.response.statusCode) else { throw WenkuError.invalid }
        try WenkuIllustrationPolicy.validateImage(reply.data)
        return reply.data
      }
    }
    throw WenkuError.invalid
  }

  private func trimImageCache(keeping current: URL) throws {
    let files = try FileManager.default.contentsOfDirectory(at: imageDirectory,
      includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
    let entries = try files.map { file -> (URL, Int, Date) in
      let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
      return (file, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
    }.sorted { $0.2 < $1.2 }
    var size = entries.reduce(0) { $0 + $1.1 }
    for (file, length, _) in entries where size > 256 * 1024 * 1024 && file != current {
      try FileManager.default.removeItem(at: file)
      size -= length
    }
  }
}

enum WenkuError: Error { case invalid, reviewEncoding }

enum WenkuWire {
  static let userAgent = "Wenku8-Flutter/0.2.3"

  static func request(action: String, milliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> URLRequest {
    var request = URLRequest(url: URL(string: "https://wenku8-relay.mewx.org/")!)
    request.httpMethod = "POST"
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
    // Keep the legacy relay's Base64 field verbatim, matching its published clients.
    let encoded = Data(action.utf8).base64EncodedString()
    request.httpBody = Data("&appver=1.13&request=\(encoded)&timetoken=\(milliseconds)".utf8)
    return request
  }

  static func validCookie(_ cookie: String) -> Bool {
    cookie.range(of: "\\A[A-Za-z0-9,-]{8,256}\\z", options: .regularExpression) != nil
  }

  static func sessionCookie(_ response: HTTPURLResponse) -> String? {
    guard let raw = response.value(forHTTPHeaderField: "Set-Cookie"),
      let expression = try? NSRegularExpression(pattern: "(?:^|[;,]\\s*)PHPSESSID=([A-Za-z0-9,-]{8,256})(?=[;\\s]|$)"),
      let match = expression.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
      let range = Range(match.range(at: 1), in: raw) else { return nil }
    return String(raw[range])
  }

  static func encodeReview(_ text: String) throws -> String {
    guard text.utf16.count <= 10_000 else { throw WenkuError.reviewEncoding }
    var bytes = [UInt8]()
    var run = ""
    for scalar in text.unicodeScalars {
      guard !nonAndroidGBKScalars.contains(scalar.value) else { throw WenkuError.reviewEncoding }
      if let code = androidGBKCode(scalar.value) {
        bytes += try systemGBKBytes(run)
        run = ""
        if code > 0xFF { bytes.append(UInt8(code >> 8)) }
        bytes.append(UInt8(code & 0xFF))
      } else {
        run.unicodeScalars.append(scalar)
      }
    }
    bytes += try systemGBKBytes(run)
    // Android's URLEncoder uses ICU GBK, followed by UTF-8 Base64.
    let safe = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-*_".utf8)
    var encoded = ""
    var index = 0
    while index < bytes.count {
      let byte = bytes[index]
      if byte < 0x80 {
        if byte == 32 { encoded += "+" }
        else if safe.contains(byte) { encoded += String(UnicodeScalar(byte)) }
        else { encoded += String(format: "%%%02X", byte) }
      } else {
        encoded += String(format: "%%%02X", byte)
        if byte >= 0x81 && byte <= 0xFE {
          // A GBK character's ASCII-valued trail is escaped with its lead byte.
          index += 1
          guard index < bytes.count else { throw WenkuError.reviewEncoding }
          encoded += String(format: "%%%02X", bytes[index])
        }
      }
      index += 1
    }
    return Data(encoded.utf8).base64EncodedString()
  }

  private static func systemGBKBytes(_ text: String) throws -> [UInt8] {
    if text.isEmpty { return [] }
    let input = Data(text.utf8)
    // GBK uses at most as many bytes as the same valid UTF-8 text.
    var bytes = [UInt8](repeating: 0, count: input.count)
    var length = bytes.count
    let converted = input.withUnsafeBytes { source in
      bytes.withUnsafeMutableBufferPointer { destination in
        WenkuEncodeGBK(source.bindMemory(to: CChar.self).baseAddress!, input.count, destination.baseAddress!, &length)
      }
    }
    guard converted != 0 else { throw WenkuError.reviewEncoding }
    bytes.removeSubrange(length...)
    return bytes
  }

  // Android ICU aliases GBK to windows-936-2000, unlike desktop OpenJDK GBK.
  // Mapping facts from Unicode ICU's windows-936-2000.ucm (Unicode license):
  // https://android.googlesource.com/platform/external/icu/+/refs/heads/main/icu4c/source/data/mappings/windows-936-2000.ucm
  private static func androidGBKCode(_ scalar: UInt32) -> UInt32? {
    if scalar == 0x20AC { return 0x80 }
    if scalar == 0xF8F5 { return 0xFF }
    // These standard characters otherwise take Apple iconv's non-reversible aliases.
    if scalar == 0x2015 { return 0xA844 }
    if scalar == 0xFFE1 { return 0xA1EA }
    if (0xE000...0xE4C5).contains(scalar) {
      let offset = scalar - 0xE000
      let lead = offset < 564 ? 0xAA + offset / 94 : 0xF8 + (offset - 564) / 94
      return lead * 256 + 0xA1 + offset % 94
    }
    if (0xE4C6...0xE765).contains(scalar) {
      let offset = scalar - 0xE4C6
      var trail = 0x40 + offset % 96
      if trail >= 0x7F { trail += 1 }
      return (0xA1 + offset / 96) * 256 + trail
    }
    for (start, end, first) in privateUseTail where scalar >= start && scalar <= end {
      return first + scalar - start
    }
    return nil
  }

  // All 255 remaining ICU private-use mappings, compressed into 27 linear spans.
  private static let privateUseTail: [(UInt32, UInt32, UInt32)] = [
    (0xE766, 0xE76B, 0xA2AB), (0xE76C, 0xE76D, 0xA2E3),
    (0xE76E, 0xE76F, 0xA2EF), (0xE770, 0xE771, 0xA2FD),
    (0xE772, 0xE77C, 0xA4F4), (0xE77D, 0xE784, 0xA5F7),
    (0xE785, 0xE78C, 0xA6B9), (0xE78D, 0xE793, 0xA6D9),
    (0xE794, 0xE795, 0xA6EC), (0xE796, 0xE796, 0xA6F3),
    (0xE797, 0xE79F, 0xA6F6), (0xE7A0, 0xE7AE, 0xA7C2),
    (0xE7AF, 0xE7BB, 0xA7F2), (0xE7BC, 0xE7C6, 0xA896),
    (0xE7C7, 0xE7C7, 0xA8BC), (0xE7C8, 0xE7C8, 0xA8BF),
    (0xE7C9, 0xE7CC, 0xA8C1), (0xE7CD, 0xE7E1, 0xA8EA),
    (0xE7E2, 0xE7E2, 0xA958), (0xE7E3, 0xE7E3, 0xA95B),
    (0xE7E4, 0xE7E6, 0xA95D), (0xE7E7, 0xE7F3, 0xA989),
    (0xE7F4, 0xE800, 0xA997), (0xE801, 0xE80F, 0xA9F0),
    (0xE810, 0xE814, 0xD7FA), (0xE815, 0xE843, 0xFE50),
    (0xE844, 0xE864, 0xFE80)
  ]

  // Apple GBK assigns these bytes to newer Unicode characters; Android ICU
  // keeps their original private-use assignments instead. Do not expand its contract.
  private static let nonAndroidGBKScalars: Set<UInt32> = [
    0x01F9, 0x2E81, 0x2E84, 0x2E88, 0x2E8B, 0x2E8C, 0x2E97,
    0x2EA7, 0x2EAA, 0x2EAE, 0x2EB3, 0x2EB6, 0x2EB7, 0x2EBB, 0x2ECA,
    0x2FF0, 0x2FF1, 0x2FF2, 0x2FF3, 0x2FF4, 0x2FF5, 0x2FF6, 0x2FF7,
    0x2FF8, 0x2FF9, 0x2FFA, 0x2FFB, 0x303E, 0x3447, 0x3473, 0x359E,
    0x360E, 0x361A, 0x3918, 0x396E, 0x39CF, 0x39D0, 0x39DF, 0x3A73,
    0x3B4E, 0x3C6E, 0x3CE0, 0x4056, 0x415F, 0x4337, 0x43AC, 0x43B1,
    0x43DD, 0x44D6, 0x464C, 0x4661, 0x4723, 0x4729, 0x477C, 0x478D,
    0x4947, 0x497A, 0x497D, 0x4982, 0x4983, 0x4985, 0x4986, 0x499B,
    0x499F, 0x49B6, 0x49B7, 0x4C77, 0x4C9F, 0x4CA0, 0x4CA1, 0x4CA2,
    0x4CA3, 0x4D13, 0x4D14, 0x4D15, 0x4D16, 0x4D17, 0x4D18, 0x4D19, 0x4DAE
  ]
}

enum WenkuIllustrationPolicy {
  static func parse(_ raw: String) throws -> URL {
    guard let parts = URLComponents(string: raw), let host = parts.host?.lowercased(),
      parts.scheme?.lowercased() == "https", parts.user == nil, parts.password == nil,
      parts.port == nil || parts.port == 443,
      ["wenku8.com", "wenku8.net", "wenku8.cn"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) || host == "pic.777743.xyz",
      let url = parts.url else { throw WenkuError.invalid }
    return url
  }

  static func redirect(from source: URL, location: String) throws -> URL {
    guard let resolved = URL(string: location, relativeTo: source)?.absoluteURL,
      var parts = URLComponents(url: resolved, resolvingAgainstBaseURL: true),
      ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
      parts.port == nil || parts.port == 80 || parts.port == 443 else { throw WenkuError.invalid }
    parts.scheme = "https"
    if parts.port == 80 { parts.port = nil }
    guard let secure = parts.string else { throw WenkuError.invalid }
    // URLComponents preserves percent-escaped paths and signed query strings.
    return try parse(secure)
  }

  static func validateImage(_ data: Data) throws {
    guard !data.isEmpty, data.count <= WenkuDownload.limit,
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      CGImageSourceGetStatus(source) == .statusComplete,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
      let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
      width.int64Value > 0, height.int64Value > 0,
      width.int64Value <= 50_000_000 / height.int64Value else { throw WenkuError.invalid }
  }
}

private final class WenkuSessionStore {
  private var query: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "org.mewx.wenku8") + ".account.session.v1",
     kSecAttrAccount as String: "PHPSESSID"]
  }

  func read() throws -> String? {
    var lookup = query
    lookup[kSecReturnData as String] = true
    lookup[kSecMatchLimit as String] = kSecMatchLimitOne
    var value: CFTypeRef?
    let status = SecItemCopyMatching(lookup as CFDictionary, &value)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw WenkuError.invalid }
    guard let data = value as? Data, let cookie = String(data: data, encoding: .utf8), WenkuWire.validCookie(cookie) else {
      try write(nil)
      return nil
    }
    return cookie
  }

  func write(_ cookie: String?) throws {
    guard let cookie = cookie else {
      let status = SecItemDelete(query as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else { throw WenkuError.invalid }
      return
    }
    guard WenkuWire.validCookie(cookie) else { throw WenkuError.invalid }
    let values: [String: Any] = [kSecValueData as String: Data(cookie.utf8),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
    let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
    if status == errSecItemNotFound {
      var entry = query
      values.forEach { entry[$0.key] = $0.value }
      guard SecItemAdd(entry as CFDictionary, nil) == errSecSuccess else { throw WenkuError.invalid }
    } else if status != errSecSuccess { throw WenkuError.invalid }
  }
}

/// A data delegate enforces the limit while receiving, before allocating a full response.
private final class WenkuDownload: NSObject, URLSessionDataDelegate {
  static let limit = 8 * 1024 * 1024
  private let completed = DispatchSemaphore(value: 0)
  private var data = Data()
  private var response: HTTPURLResponse?
  private var failed = false

  static func fetch(_ request: URLRequest) throws -> (data: Data, response: HTTPURLResponse) {
    let delegate = WenkuDownload()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 30
    let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    session.dataTask(with: request).resume()
    guard delegate.completed.wait(timeout: .now() + 35) == .success,
      !delegate.failed, let response = delegate.response else { throw WenkuError.invalid }
    return (delegate.data, response)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
    guard let http = response as? HTTPURLResponse, response.expectedContentLength <= Int64(Self.limit) else {
      failed = true
      completionHandler(.cancel)
      return
    }
    self.response = http
    completionHandler(.allow)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    guard self.data.count + data.count <= Self.limit else {
      failed = true
      dataTask.cancel()
      return
    }
    self.data.append(data)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    // API redirects fail closed; image redirects are revalidated by the caller.
    completionHandler(nil)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if error != nil { failed = true }
    completed.signal()
  }
}
