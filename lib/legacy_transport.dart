import 'package:flutter/services.dart';

/// The same v1.30 POST bridge. Account cookies never cross into Dart or backups.
abstract final class LegacyTransport {
  static const channel = MethodChannel('org.mewx.wenku8/legacy_api');
  static Future<String> request(String action) => _text('request', action);
  static Future<String> accountRequest(String action) =>
      _text('accountRequest', action);

  /// Read-only routes which the service may gate behind a signed-in session.
  /// Public discovery/search remain independent from account cookies.
  static Future<String> sessionRead(String action) async =>
      await hasSession() ? accountRequest(action) : request(action);
  static Future<String> login(String action) => _text('login', action);
  static Future<String> _text(String method, String action) async {
    try {
      final text = await channel.invokeMethod<String>(method, {
        'action': action,
      });
      if (text == null || text.trim().isEmpty) {
        throw const FormatException('接口返回空内容');
      }
      return text;
    } on PlatformException catch (error) {
      // Only native error codes choose user-facing text; never show response
      // bodies or platform messages, which may contain request/session data.
      if (error.code == 'LEGACY_API_HTTP') {
        throw FormatException(switch (error.details) {
          400 => '服务接口拒绝请求，请更新应用后重试。',
          403 => '服务暂时拒绝访问，请稍后重试。',
          429 => '请求过于频繁，请稍后再试。',
          int status when status >= 500 && status < 600 => '服务暂时不可用，请稍后重试。',
          _ => '服务返回异常，请稍后重试。',
        });
      }
      if (error.code == 'LEGACY_API_NETWORK') {
        throw FormatException(switch (error.details) {
          -1009 => '网络不可用，请检查应用的无线数据权限或切换网络后重试。',
          -1001 => '连接超时，请稍后重试。',
          -1003 => '无法解析服务地址，请切换网络后重试。',
          -1004 => '无法连接服务，请稍后重试。',
          -1200 => '无法建立安全连接，请检查系统日期或切换网络后重试。',
          _ => '连接服务失败，请稍后重试。',
        });
      }
      rethrow;
    }
  }

  static Future<bool> hasSession() async =>
      await channel.invokeMethod<bool>('hasSession') ?? false;
  static Future<void> clearSession() =>
      channel.invokeMethod<void>('clearSession');
  static Future<Uint8List> illustration(String url) async {
    final bytes = await channel.invokeMethod<Uint8List>('illustration', {
      'url': url,
    });
    if (bytes == null || bytes.isEmpty) throw const FormatException('插图内容为空');
    return bytes;
  }

  static Future<void> clearIllustrations() =>
      channel.invokeMethod<void>('clearIllustrations');
  static Future<String> encodeReview(String text) async {
    try {
      final encoded = await channel.invokeMethod<String>('encodeReview', {
        'text': text,
      });
      if (encoded == null || encoded.isEmpty) {
        throw const FormatException('书评编码返回空内容');
      }
      return encoded;
    } on PlatformException catch (error) {
      if (error.code == 'REVIEW_ENCODING') {
        throw const FormatException('原版书评接口使用 GBK，请移除表情或特殊字符后重试；草稿仍保留');
      }
      rethrow;
    }
  }
}
