import Flutter
import Security
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testLivePublicRelayListChapterAndCover() throws {
    let bridge = Wenku8Bridge()
    _ = try invoke(bridge, method: "clearSession")
    let listing = try XCTUnwrap(try invoke(bridge, method: "request", arguments: [
      "action": "action=novellist&sort=lastupdate&page=1&t=0"
    ]) as? String)
    XCTAssertTrue(listing.contains("<result"))
    let aid = try firstXMLID(listing, element: "item", attribute: "aid")
    let metadata = try XCTUnwrap(try invoke(bridge, method: "request", arguments: [
      "action": "action=book&do=meta&aid=\(aid)&t=0"
    ]) as? String)
    XCTAssertTrue(metadata.contains("<metadata"))
    let chapters = try XCTUnwrap(try invoke(bridge, method: "request", arguments: [
      "action": "action=book&do=list&aid=\(aid)&t=0"
    ]) as? String)
    let cid = try firstXMLID(chapters, element: "chapter", attribute: "cid")
    let body = try XCTUnwrap(try invoke(bridge, method: "request", arguments: [
      "action": "action=book&do=text&aid=\(aid)&cid=\(cid)&t=0"
    ]) as? String)
    XCTAssertGreaterThan(body.trimmingCharacters(in: .whitespacesAndNewlines).count, 10)
    let cover = try XCTUnwrap(try invoke(bridge, method: "cover", arguments: ["aid": aid]) as? FlutterStandardTypedData)
    XCTAssertGreaterThan(cover.data.count, 1000)
    XCTAssertNoThrow(try WenkuIllustrationPolicy.validateImage(cover.data))
    // Public reads must not persist any Set-Cookie header as an account login.
    XCTAssertEqual(try invoke(bridge, method: "hasSession") as? Bool, false)
  }

  func testAccountWithoutSessionAndClearSession() throws {
    let bridge = Wenku8Bridge()
    _ = try invoke(bridge, method: "clearSession")
    XCTAssertEqual(try invoke(bridge, method: "hasSession") as? Bool, false)
    XCTAssertEqual(try invoke(bridge, method: "accountRequest", arguments: [
      "action": "action=bookcase&do=get"
    ]) as? String, "4")
    _ = try invoke(bridge, method: "clearSession")
    XCTAssertEqual(try invoke(bridge, method: "hasSession") as? Bool, false)
    // A new instance reloads Keychain, proving logout also removed persisted state.
    XCTAssertEqual(try invoke(Wenku8Bridge(), method: "hasSession") as? Bool, false)
  }

  private func invoke(_ bridge: Wenku8Bridge, method: String, arguments: [String: Any]? = nil) throws -> Any? {
    let completed = expectation(description: "Legacy bridge \(method)")
    var response: Any?
    bridge.handle(FlutterMethodCall(methodName: method, arguments: arguments)) { value in
      response = value
      completed.fulfill()
    }
    wait(for: [completed], timeout: 40)
    if let error = response as? FlutterError {
      XCTFail("Legacy bridge \(method) returned \(error.code): \(error.message ?? "")")
      throw WenkuError.invalid
    }
    return response
  }

  private func firstXMLID(_ xml: String, element: String, attribute: String) throws -> Int {
    let expression = try NSRegularExpression(pattern: "<\(element)\\b[^>]*\\b\(attribute)\\s*=\\s*[\"']([0-9]+)[\"']")
    let match = try XCTUnwrap(expression.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)))
    let range = try XCTUnwrap(Range(match.range(at: 1), in: xml))
    return try XCTUnwrap(Int(xml[range]))
  }

  func testPublicRelayEnvelopeHasNoCookie() throws {
    let action = "action=novellist&sort=lastupdate&page=1&t=0"
    let request = WenkuWire.request(action: action, milliseconds: 123456789)
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.url?.absoluteString, "https://wenku8-relay.mewx.org/")
    XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Wenku8-Flutter/0.2.3")
    XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
    let expected = "&appver=1.13&request=\(Data(action.utf8).base64EncodedString())&timetoken=123456789"
    XCTAssertEqual(request.httpBody, Data(expected.utf8))
  }

  func testReviewChineseUsesGBKBytes() throws {
    let encoded = try WenkuWire.encodeReview("中文")
    XCTAssertEqual(String(data: try XCTUnwrap(Data(base64Encoded: encoded)), encoding: .utf8),
      "%D6%D0%CE%C4", "Chinese GBK byte mapping differs")
  }

  func testReviewUsesFormEncoding() throws {
    let encoded = try WenkuWire.encodeReview(" +&~.-*_")
    XCTAssertEqual(String(data: try XCTUnwrap(Data(base64Encoded: encoded)), encoding: .utf8),
      "+%2B%26%7E.-*_", "GBK form escaping differs from java.net.URLEncoder")
  }

  func testReviewUsesGBKFormEncoding() throws {
    let encoded = try WenkuWire.encodeReview("中文 +&~")
    XCTAssertEqual(String(data: try XCTUnwrap(Data(base64Encoded: encoded)), encoding: .utf8),
      "%D6%D0%CE%C4+%2B%26%7E")
  }

  func testReviewRejectsEmoji() throws {
    XCTAssertThrowsError(try WenkuWire.encodeReview("😀"), "GBK must reject an unrepresentable emoji")
  }

  func testReviewRetainsLegacyGBKMapping() throws {
    let encoded = try WenkuWire.encodeReview("\u{2641}\u{E7C8}")
    XCTAssertEqual(String(data: try XCTUnwrap(Data(base64Encoded: encoded)), encoding: .utf8),
      "%A8%92%A8%BF", "GBK byte mapping must not change to GB18030")
  }

  func testReviewEmptyAndBoundedInput() throws {
    XCTAssertEqual(try WenkuWire.encodeReview(""), "")
    let withNull = try WenkuWire.encodeReview("A\0中")
    XCTAssertEqual(String(data: try XCTUnwrap(Data(base64Encoded: withNull)), encoding: .utf8), "A%00%D6%D0")
    XCTAssertNoThrow(try WenkuWire.encodeReview(String(repeating: "中", count: 10_000)))
    XCTAssertThrowsError(try WenkuWire.encodeReview(String(repeating: "中", count: 10_001)))
  }

  func testKeychainDeviceBoundFixtureStorage() throws {
    // A throwaway fixture proves the simulator signing permits the production accessibility class.
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "wenku8-runner-test-" + UUID().uuidString,
      kSecAttrAccount as String: "fixture"]
    defer { SecItemDelete(query as CFDictionary) }
    var entry = query
    entry[kSecValueData as String] = Data("fixture-session".utf8)
    entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let added = SecItemAdd(entry as CFDictionary, nil)
    XCTAssertEqual(added, errSecSuccess, "SecItemAdd status=\(added), message=\(SecCopyErrorMessageString(added, nil) as String? ?? "unknown")")
    guard added == errSecSuccess else { return }
    var lookup = query
    lookup[kSecReturnData as String] = true
    var stored: CFTypeRef?
    let read = SecItemCopyMatching(lookup as CFDictionary, &stored)
    XCTAssertEqual(read, errSecSuccess, "SecItemCopyMatching status=\(read)")
    XCTAssertEqual(stored as? Data, Data("fixture-session".utf8))
    let deleted = SecItemDelete(query as CFDictionary)
    XCTAssertEqual(deleted, errSecSuccess, "SecItemDelete status=\(deleted)")
  }

  func testImagePolicyRejectsUntrustedAddresses() throws {
    for raw in ["http://img.wenku8.com/a.jpg", "https://wenku8.com.evil.test/a.jpg",
      "https://wenku8.com@evil.test/a.jpg", "https://user@img.wenku8.com/a.jpg",
      "https://img.wenku8.com:444/a.jpg", "https://127.0.0.1/a.jpg", "file:///a.jpg"] {
      XCTAssertThrowsError(try WenkuIllustrationPolicy.parse(raw), raw)
    }
    for raw in ["https://img.wenku8.com/a.jpg", "https://pic.777743.xyz/a.jpg"] {
      XCTAssertNoThrow(try WenkuIllustrationPolicy.parse(raw))
    }
  }

  func testImageRedirectUpgradesHTTPAndPreservesEscapes() throws {
    let source = try WenkuIllustrationPolicy.parse("https://img.wenku8.com/folder/a.jpg")
    let destination = try WenkuIllustrationPolicy.redirect(from: source,
      location: "http://pic.777743.xyz:80/folder%2Fname.jpg?signature=a%2Bb%2Fc")
    XCTAssertEqual(destination.absoluteString, "https://pic.777743.xyz/folder%2Fname.jpg?signature=a%2Bb%2Fc")
    XCTAssertThrowsError(try WenkuIllustrationPolicy.redirect(from: source, location: "https://evil.test/a.jpg"))
    XCTAssertThrowsError(try WenkuIllustrationPolicy.redirect(from: source, location: "file:///a.jpg"))
  }

  func testSessionCookieValidationAndExtraction() throws {
    XCTAssertTrue(WenkuWire.validCookie("abcd1234,-"))
    for cookie in ["short", "bad;cookie", "cookie\r\nheader", "abcd1234\n", String(repeating: "a", count: 257)] {
      XCTAssertFalse(WenkuWire.validCookie(cookie))
    }
    let url = try XCTUnwrap(URL(string: "https://wenku8-relay.mewx.org/"))
    let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
      headerFields: ["Set-Cookie": "PHPSESSID=abcd1234; path=/; HttpOnly"]))
    XCTAssertEqual(WenkuWire.sessionCookie(response), "abcd1234")
    let invalid = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
      headerFields: ["Set-Cookie": "PHPSESSID=short; path=/"]))
    XCTAssertNil(WenkuWire.sessionCookie(invalid))
  }

  func testImageValidationRejectsNonImagesAndOversizeData() throws {
    XCTAssertThrowsError(try WenkuIllustrationPolicy.validateImage(Data("<html>error</html>".utf8)))
    XCTAssertThrowsError(try WenkuIllustrationPolicy.validateImage(Data(count: 8 * 1024 * 1024 + 1)))
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
    let data = renderer.pngData { context in
      UIColor.white.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    }
    XCTAssertNoThrow(try WenkuIllustrationPolicy.validateImage(data))
  }

}
