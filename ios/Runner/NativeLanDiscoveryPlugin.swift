import Flutter

/// Pairing/encrypted-transfer sources are absent. Do not expose Bonjour peers
/// or open an unauthenticated transport while the Dart capability is disabled.
final class NativeLanDiscoveryPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "org.mewx.wenku8/lan_discovery", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(NativeLanDiscoveryPlugin(), channel: channel)
  }
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    result(FlutterError(code: "UNAVAILABLE", message: "Nearby reading is unavailable in this build", details: nil))
  }
}
