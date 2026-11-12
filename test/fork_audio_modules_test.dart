import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/listening/custom_tts.dart';
import 'package:wenku8_flutter/listening/enhancement.dart';
import 'package:wenku8_flutter/listening/models.dart';

class Headers extends Fake implements HttpHeaders {
  final values = <String, Object>{};
  @override
  ContentType? contentType;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = value;
  }
}

class Response extends Fake implements HttpClientResponse {
  Response(this.statusCode, this.parts);
  @override
  final int statusCode;
  final List<List<int>> parts;
  @override
  Stream<List<int>> timeout(
    Duration timeLimit, {
    void Function(EventSink<List<int>>)? onTimeout,
  }) => Stream.fromIterable(parts).timeout(timeLimit, onTimeout: onTimeout);
}

class Request extends Fake implements HttpClientRequest {
  Request(this.response);
  final Response response;
  @override
  bool followRedirects = true;
  @override
  final Headers headers = Headers();
  final body = BytesBuilder();
  @override
  void add(List<int> bytes) => body.add(bytes);
  @override
  Future<HttpClientResponse> close() async => response;
}

class Client extends Fake implements HttpClient {
  Client(this.request);
  final Request request;
  bool closed = false;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> postUrl(Uri url) async => request;
  @override
  void close({bool force = false}) {
    closed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  CustomSpeechConfig config({
    String endpoint = 'https://speech.example.test/synthesize',
    String key = 'fixture',
  }) => CustomSpeechConfig(
    endpoint: endpoint,
    voiceId: 'zh-CN-XiaoxiaoNeural',
    subscriptionKey: key,
  );
  test('configuration rejects insecure URLs and header injection', () {
    for (final url in [
      'http://speech.example.test',
      'https://user:pass@speech.example.test',
      'https://speech.example.test/#fragment',
    ]) {
      expect(() => config(endpoint: url), throwsFormatException);
    }
    expect(() => config(key: 'key\r\nheader'), throwsFormatException);
    expect(config(key: 'a').namespace, isNot(config(key: 'b').namespace));
    expect(config().namespace, isNot(contains('fixture')));
  });
  test(
    'credentials use native secure storage and a failed save keeps old configuration',
    () async {
      const channel = MethodChannel('org.mewx.wenku8/custom_speech');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      String? stored;
      bool fail = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'read') return stored;
        if (fail) throw PlatformException(code: 'secure_storage');
        stored = call.arguments as String?;
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final settings = CustomSpeechSettings();
      addTearDown(settings.dispose);
      await settings.save(config());
      final old = settings.config;
      fail = true;
      await expectLater(
        settings.save(config(key: 'changed')),
        throwsA(isA<PlatformException>()),
      );
      expect(settings.config, same(old));
      final reloaded = CustomSpeechSettings();
      addTearDown(reloaded.dispose);
      await reloaded.load();
      expect(reloaded.config?.subscriptionKey, 'fixture');
    },
  );
  test(
    'SSML escapes book text and never redirects subscription credentials',
    () async {
      final audio = [0x49, 0x44, 0x33, ...List.filled(120, 0)];
      final request = Request(Response(200, [audio]));
      final client = Client(request);
      final result = await CustomSpeechClient(
        createClient: () => client,
      ).synthesize('A & <voice>', config(), SpeechCancellation());
      expect(result, audio);
      expect(
        utf8.decode(request.body.toBytes()),
        contains('A &amp; &lt;voice&gt;'),
      );
      expect(request.followRedirects, isFalse);
      expect(request.headers.values['Ocp-Apim-Subscription-Key'], 'fixture');
      expect(client.closed, isTrue);
    },
  );
  test(
    'unexpected HTTP responses, HTML and oversize audio fail closed',
    () async {
      for (final response in [
        Response(302, []),
        Response(200, [utf8.encode('<html>error</html>')]),
        Response(200, [Uint8List(8 * 1024 * 1024 + 1)]),
      ]) {
        final client = Client(Request(response));
        await expectLater(
          CustomSpeechClient(
            createClient: () => client,
          ).synthesize('hello', config(), SpeechCancellation()),
          throwsA(isA<SpeechFailure>()),
        );
        expect(client.closed, isTrue);
      }
    },
  );
  test('cancelled synthesis never opens a connection', () async {
    final token = SpeechCancellation()..cancel();
    await expectLater(
      CustomSpeechClient(
        createClient: () => throw StateError('must not connect'),
      ).synthesize('hello', config(), token),
      throwsA(isA<SpeechCancelled>()),
    );
  });
  test(
    'enhancement preference rejects nonfinite stored values and preserves bounds',
    () {
      expect(
        ListeningEnhancementPreference.fromJson({'gainDb': double.nan}).gainDb,
        0,
      );
      expect(
        ListeningEnhancementPreference.fromJson({'gainDb': 100}).gainDb,
        12,
      );
      expect(ListeningEnhancementPreference.fromJson({'gainDb': -5}).gainDb, 0);
    },
  );
}
