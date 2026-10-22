import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenku8_flutter/app_ui.dart';
import 'package:wenku8_flutter/legacy_transport.dart';
import 'package:wenku8_flutter/legacy_wenku_repository.dart';
import 'package:wenku8_flutter/library_state.dart';
import 'package:wenku8_flutter/novel_feed_controller.dart';
import 'package:wenku8_flutter/pages.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  void failWith(String code, Object? details) {
    messenger.setMockMethodCallHandler(LegacyTransport.channel, (_) async {
      throw PlatformException(
        code: code,
        message: 'unsafe server response PHPSESSID=private-value',
        details: details,
      );
    });
  }

  tearDown(
    () => messenger.setMockMethodCallHandler(LegacyTransport.channel, null),
  );

  for (final (code, details, message) in <(String, Object?, String)>[
    ('LEGACY_API_HTTP', 400, '服务接口拒绝请求，请更新应用后重试。'),
    ('LEGACY_API_HTTP', 403, '服务暂时拒绝访问，请稍后重试。'),
    ('LEGACY_API_HTTP', 429, '请求过于频繁，请稍后再试。'),
    ('LEGACY_API_HTTP', 500, '服务暂时不可用，请稍后重试。'),
    ('LEGACY_API_HTTP', 599, '服务暂时不可用，请稍后重试。'),
    ('LEGACY_API_HTTP', 404, '服务返回异常，请稍后重试。'),
    ('LEGACY_API_HTTP', {'body': 'private-value'}, '服务返回异常，请稍后重试。'),
    ('LEGACY_API_NETWORK', -1009, '网络不可用，请检查应用的无线数据权限或切换网络后重试。'),
    ('LEGACY_API_NETWORK', -1001, '连接超时，请稍后重试。'),
    ('LEGACY_API_NETWORK', -1003, '无法解析服务地址，请切换网络后重试。'),
    ('LEGACY_API_NETWORK', -1004, '无法连接服务，请稍后重试。'),
    ('LEGACY_API_NETWORK', -1200, '无法建立安全连接，请检查系统日期或切换网络后重试。'),
    ('LEGACY_API_NETWORK', null, '连接服务失败，请稍后重试。'),
  ]) {
    test(
      'native $code $details exposes only a safe recovery message',
      () async {
        failWith(code, details);
        await expectLater(
          LegacyTransport.request('action=novellist'),
          throwsA(
            isA<FormatException>().having((e) => e.message, 'message', message),
          ),
        );
      },
    );
  }

  test('account and login text calls share native error mapping', () async {
    failWith('LEGACY_API_NETWORK', -1001);
    for (final request in [
      LegacyTransport.accountRequest,
      LegacyTransport.login,
    ]) {
      await expectLater(
        request('action=test'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            '连接超时，请稍后重试。',
          ),
        ),
      );
    }
  });

  test('existing Android and unknown bridge errors stay unchanged', () async {
    failWith('LEGACY_API_ERROR', 400);
    await expectLater(
      LegacyTransport.request('action=novellist'),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'LEGACY_API_ERROR',
        ),
      ),
    );
  });

  testWidgets(
    'discovery presents the iOS service failure and retains retry',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final state = await LibraryState.load();
      final repository = LegacyWenkuRepository();
      final feed = NovelFeedController(repository);
      addTearDown(state.dispose);
      addTearDown(feed.dispose);
      failWith('LEGACY_API_HTTP', 400);
      await feed.loadInitial();
      await tester.pumpWidget(
        MaterialApp(
          theme: novelTheme(Brightness.light),
          home: Scaffold(
            body: DiscoverPage(
              books: const [],
              state: state,
              repository: repository,
              feed: feed,
              onSearch: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('书籍加载失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      final expected = defaultTargetPlatform == TargetPlatform.iOS
          ? '服务接口拒绝请求，请更新应用后重试。\n已保存的书架与阅读记录仍保留。'
          : '检查网络后再试，已保存的书架与阅读记录仍保留。';
      expect(find.text(expected), findsOneWidget);
      expect(find.textContaining('private-value'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );
}
