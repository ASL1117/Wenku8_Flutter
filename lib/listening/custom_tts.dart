import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';

class CustomSpeechConfig {
  CustomSpeechConfig({
    required this.endpoint,
    required this.voiceId,
    this.locale = 'zh-CN',
    this.subscriptionKey = '',
    this.label = '自定义语音',
  }) {
    final uri = Uri.tryParse(endpoint);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !RegExp(r'^[A-Za-z0-9_.-]{1,160}$').hasMatch(voiceId) ||
        !RegExp(r'^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$').hasMatch(locale) ||
        subscriptionKey.contains(RegExp(r'[\r\n]'))) {
      throw const FormatException('请填写有效的 HTTPS 地址、音色 ID 和语言');
    }
  }
  final String endpoint, voiceId, locale, subscriptionKey, label;
  String get namespace =>
      'custom:${sha256.convert(utf8.encode('$endpoint|$subscriptionKey'))}';
  SpeechVoice get voice => SpeechVoice(
    id: voiceId,
    label: label,
    locale: locale,
    source: ListeningSource.custom,
    engine: namespace,
  );
  Map<String, String> toJson() => {
    'endpoint': endpoint,
    'voice': voiceId,
    'locale': locale,
    'key': subscriptionKey,
    'label': label,
  };
  factory CustomSpeechConfig.fromJson(Map<String, dynamic> json) =>
      CustomSpeechConfig(
        endpoint: json['endpoint'] as String,
        voiceId: json['voice'] as String,
        locale: json['locale'] as String? ?? 'zh-CN',
        subscriptionKey: json['key'] as String? ?? '',
        label: json['label'] as String? ?? '自定义语音',
      );
}

class CustomSpeechSettings extends ChangeNotifier {
  static const _channel = MethodChannel('org.mewx.wenku8/custom_speech');
  CustomSpeechConfig? config;
  String? error;
  Future<void> load() async {
    try {
      final text = await _channel.invokeMethod<String>('read');
      config = text == null
          ? null
          : CustomSpeechConfig.fromJson(
              jsonDecode(text) as Map<String, dynamic>,
            );
      error = null;
    } catch (_) {
      config = null;
      error = '安全配置暂不可读取，请重新保存配置';
    }
  }

  Future<void> save(CustomSpeechConfig? value) async {
    // Credentials only go to the host's Keychain / encrypted configuration store.
    await _channel.invokeMethod<void>(
      'write',
      value == null ? null : jsonEncode(value.toJson()),
    );
    config = value;
    error = null;
    notifyListeners();
  }
}

class CustomSpeechClient {
  CustomSpeechClient({HttpClient Function()? createClient})
    : _createClient = createClient ?? (() => HttpClient());
  final HttpClient Function() _createClient;
  Future<Uint8List> synthesize(
    String text,
    CustomSpeechConfig config,
    SpeechCancellation cancellation,
  ) async {
    cancellation.check();
    if (text.length > 20_000) throw const SpeechFailure('语段过长，请缩短后重试');
    final client = _createClient()
      ..connectionTimeout = const Duration(seconds: 15);
    final remove = cancellation.onCancel(() => client.close(force: true));
    try {
      final request = await cancellation.wait(
        client.postUrl(Uri.parse(config.endpoint)),
      );
      request.followRedirects = false;
      request.headers.contentType = ContentType(
        'application',
        'ssml+xml',
        charset: 'utf-8',
      );
      request.headers.set(
        'X-Microsoft-OutputFormat',
        'audio-24khz-48kbitrate-mono-mp3',
      );
      if (config.subscriptionKey.isNotEmpty) {
        request.headers.set(
          'Ocp-Apim-Subscription-Key',
          config.subscriptionKey,
        );
      }
      final escaped = const HtmlEscape(HtmlEscapeMode.element).convert(text);
      request.add(
        utf8.encode(
          '<speak version="1.0" xml:lang="${config.locale}"><voice name="${config.voiceId}">$escaped</voice></speak>',
        ),
      );
      final response = await cancellation.wait(
        request.close().timeout(const Duration(seconds: 35)),
      );
      if (response.statusCode != 200) {
        throw const SpeechFailure('自定义语音接口拒绝请求，请检查配置');
      }
      final bytes = BytesBuilder(copy: false);
      await cancellation.wait(
        () async {
          await for (final part in response.timeout(
            const Duration(seconds: 30),
          )) {
            cancellation.check();
            if (bytes.length + part.length > 8 * 1024 * 1024) {
              throw const SpeechFailure('语音响应超过大小限制');
            }
            bytes.add(part);
          }
        }().timeout(const Duration(seconds: 35)),
      );
      final audio = bytes.takeBytes();
      final mp3 =
          audio.length > 100 &&
          ((audio[0] == 0x49 && audio[1] == 0x44 && audio[2] == 0x33) ||
              (audio[0] == 0xff && audio[1] & 0xe0 == 0xe0));
      if (!mp3) throw const SpeechFailure('接口未返回 MP3 音频');
      return audio;
    } catch (_) {
      cancellation.check();
      throw const SpeechFailure('自定义语音合成失败，请检查配置或网络');
    } finally {
      remove();
      client.close(force: true);
    }
  }
}
