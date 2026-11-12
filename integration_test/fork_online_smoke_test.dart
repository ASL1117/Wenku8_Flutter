import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wenku8_flutter/legacy_wenku_repository.dart';
import 'package:wenku8_flutter/legacy_cover.dart';
import 'package:wenku8_flutter/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('fork real iOS catalogue chapter and cover', (tester) async {
    final repository = LegacyWenkuRepository();
    final books = await repository.list();
    expect(books, isNotEmpty);
    final cover = await LegacyCover.bytes(books.first.id);
    expect(cover.length, greaterThan(100));
    final detail = await repository.detail(books.first);
    final chapters = await repository.chapters(detail.id);
    expect(chapters, isNotEmpty);
    expect((await repository.chapterContent(detail.id, chapters.first)).trim(), isNotEmpty);
  });
  testWidgets('fork complete application starts on iPhone', (tester) async {
    await app.main();
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(app.NovelApp), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
