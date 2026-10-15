// Run with macOS Swift before the iOS build to expose converter availability.
// All output below comes from constant fixtures, never user review text.
import CoreFoundation
import Foundation

for cf in [CFStringEncoding(CFStringEncodings.GBK_95.rawValue),
  CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)] {
  let ns = CFStringConvertEncodingToNSStringEncoding(cf)
  let encoding = String.Encoding(rawValue: ns)
  print("encoding cf=\(cf) ns=\(ns) available=\(CFStringIsEncodingAvailable(cf))")
  for fixture in ["中文", " +&~.-*_", "😀"] {
    let nsBytes = fixture.data(using: encoding, allowLossyConversion: false)
    let cfBytes = CFStringCreateExternalRepresentation(nil, fixture as CFString, cf, 0) as Data?
    let nsHex = nsBytes?.map { String(format: "%02X", $0) }.joined() ?? "nil"
    let cfHex = cfBytes?.map { String(format: "%02X", $0) }.joined() ?? "nil"
    let roundtrip = nsBytes.flatMap { String(data: $0, encoding: encoding) } == fixture
    print("fixture scalars=\(fixture.unicodeScalars.map { String($0.value, radix: 16) }) NSString=\(nsHex) CFString=\(cfHex) roundtrip=\(roundtrip)")
  }
}
