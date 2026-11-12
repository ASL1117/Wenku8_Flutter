import 'dart:io';
import 'dart:ui';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/portable_book_prepare.dart';
import 'package:wenku8_flutter/book_documents.dart';
import 'package:wenku8_flutter/local_book_scanner.dart';
import 'package:wenku8_flutter/local_import_batch.dart';

class ScanDocuments extends BookDocuments {
  final acknowledged = <String>[];
  var finished = false;
  @override
  Future<BookDocumentSelection> stageScanBook(String token) async =>
      BookDocumentSelection(name: '$token.txt', path: token);
  @override
  Future<void> markScanBook(String token) async {
    acknowledged.add(token);
  }

  @override
  Future<void> releaseBooks(Iterable<BookDocumentSelection> books) async {}
  @override
  Future<void> finishBookScan() async {
    finished = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late PortableBookPreparer preparer;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('fork-import-test-');
    preparer = PortableBookPreparer(
      directory: Directory('${root.path}/owned'),
      textCodecToken: RootIsolateToken.instance!,
      decodeNames: (_) async => [],
      convert: (_, _) async => throw const FormatException('unsupported'),
      extractKindle: (_, _) async => 1,
    );
  });
  tearDown(() async => root.delete(recursive: true));
  test('HTML strips scripts and release never deletes originals', () async {
    final source = File('${root.path}/book.html');
    await source.writeAsString(
      '<h1>Title</h1><p>正文</p><script>privateScript()</script>',
    );
    final result = await preparer.prepare('book.html', source.path);
    final text = await File(result.single.path!).readAsString();
    expect(text, contains('正文'));
    expect(text, isNot(contains('privateScript')));
    await preparer.releasePaths([source.path, result.single.path!]);
    expect(await source.exists(), isTrue);
    expect(await File(result.single.path!).exists(), isFalse);
  });
  test('ZIP traversal is rejected without creating an escaped file', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.string('../escaped.txt', 'unsafe'));
    final source = File('${root.path}/book.zip');
    await source.writeAsBytes(ZipEncoder().encode(archive));
    await expectLater(
      preparer.prepare('book.zip', source.path),
      throwsFormatException,
    );
    expect(await File('${root.path}/escaped.txt').exists(), isFalse);
  });
  test(
    'ZIP imports supported members and rejects nested ZIP explicitly',
    () async {
      final archive = Archive()
        ..addFile(ArchiveFile.string('folder/book.txt', '正文'))
        ..addFile(ArchiveFile.string('nested.zip', 'not a zip'));
      final source = File('${root.path}/book.zip');
      await source.writeAsBytes(ZipEncoder().encode(archive));
      final result = await preparer.prepare('book.zip', source.path);
      expect(result.where((entry) => entry.path != null).length, 1);
      expect(result.where((entry) => entry.error != null).length, 1);
    },
  );
  test(
    'encrypted Kindle conversion fails instead of inventing a book',
    () async {
      final source = File('${root.path}/book.mobi');
      await source.writeAsString('fixture');
      await expectLater(
        preparer.prepare('book.mobi', source.path),
        throwsFormatException,
      );
    },
  );
  test('scan acknowledges complete imports only and closes session', () async {
    final documents = ScanDocuments();
    final result = await scanLocalBooks(
      documents: documents,
      linkText: false,
      snapshot: const BookScanSnapshot(
        books: [
          (token: 'good', name: 'good.txt'),
          (token: 'bad', name: 'bad.txt'),
        ],
        total: 2,
      ),
      selectedTokens: {'good', 'bad'},
      importSource: (book) async => book.name == 'good.txt'
          ? const LocalImportReport(bookIds: [1], added: 1, existing: 0)
          : const LocalImportReport(
              bookIds: [2],
              added: 1,
              existing: 0,
              notices: [(name: 'bad', message: 'category write failed')],
            ),
    );
    expect(documents.acknowledged, ['good']);
    expect(documents.finished, isTrue);
    expect(result.report.added, 2);
    expect(result.report.notices.length, 1);
  });
}
