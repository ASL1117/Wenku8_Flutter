import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/legacy_wenku_repository.dart';

String listing(int id, {int pages = 10}) =>
    '''<result>
<item aid="$id"><data name="Title" value="测试书$id"/>
<data name="Author" value="测试作者"/><data name="Tags" value="奇幻 冒险"/>
<data name="BookStatus" value="未完结"/></item><page num="$pages"/>
</result>''';

void main() {
  test('lists preserve metadata and parse volume-aware chapters', () async {
    final repository = LegacyWenkuRepository(
      request: (action) async {
        if (action.contains('do=list')) {
          return '<result><volume vid="7" name="第一卷">'
              '<chapter cid="11">开篇</chapter><chapter cid="11">重复</chapter>'
              '<chapter cid="0">占位</chapter></volume></result>';
        }
        return listing(42);
      },
    );
    final books = await repository.list();
    expect(books.single.title, '测试书42');
    expect(books.single.isComplete, isFalse);
    final chapters = await repository.chapters(42);
    expect(chapters.single.id, 11);
    expect(chapters.single.volumeId, 7);
    expect(chapters.single.volumeTitle, '第一卷');
  });

  test('publication categories use actual sort attributes', () async {
    final repository = LegacyWenkuRepository(
      request: (_) async => '<metadata><item sort="1">电击文库</item></metadata>',
    );
    final libraries = await repository.publicationLibraries();
    expect(libraries.single.id, 1);
    expect(libraries.single.name, '电击文库');
  });

  test(
    'empty and malformed responses fail rather than becoming fake books',
    () async {
      for (final response in ['', '<html>unavailable</html>']) {
        final repository = LegacyWenkuRepository(
          request: (_) async => response,
        );
        await expectLater(repository.list(), throwsA(isA<FormatException>()));
      }
    },
  );

  test(
    'tag reads are bounded to three pages and stop when cancelled',
    () async {
      final requested = <int>[];
      final repository = LegacyWenkuRepository(
        request: (action) async {
          final page = int.parse(Uri.splitQueryString(action)['page']!);
          requested.add(page);
          return listing(page);
        },
      );
      final result = await repository.tagPage('奇幻');
      expect(requested, [1, 2, 3]);
      expect(result.items.map((book) => book.id), [1, 2, 3]);
      expect(result.totalPages, 4);
      await repository.tagPage('奇幻', page: 2, current: () => false);
      expect(requested, [1, 2, 3]);
    },
  );
}
