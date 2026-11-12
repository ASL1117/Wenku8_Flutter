import 'book_documents.dart';
import 'catalog.dart';
import 'local_books.dart';

typedef LocalImportNotice = ({String name, String message});

class LocalImportReport {
  const LocalImportReport({
    required this.bookIds,
    required this.added,
    required this.existing,
    this.failures = const [],
    this.notices = const [],
  });
  final List<int> bookIds;
  final int added, existing;
  final List<LocalImportNotice> failures, notices;
  String get summary =>
      '新增 $added 本，已有 $existing 本${failures.isEmpty ? '' : '，${failures.length} 本未导入'}';
}

Future<LocalImportReport> importLocalDocuments({
  required List<BookDocumentSelection> selections,
  required BookDocuments documents,
  required LocalBookStore books,
  required Future<Novel> Function(String name, String path) importFile,
  Future<Novel> Function(BookDocumentSelection)? importSelection,
  bool releaseSources = false,
  void Function(List<BookDocumentSelection>)? onCleanupFailed,
  void Function(int done, int total)? onProgress,
}) async {
  final ids = <int>{}, failures = <LocalImportNotice>[];
  var added = 0, existing = 0, done = 0;
  for (final source in selections) {
    final temporary = <BookDocumentSelection>[];
    try {
      final staged = await documents.stageForImport(source);
      temporary.add(staged);
      final prepared = await documents.prepareBook(staged);
      temporary.addAll(prepared);
      for (final item in prepared) {
        try {
          if (item.error != null) throw FormatException(item.error!);
          final before = books.originals.map((book) => book.id).toSet();
          final imported = importSelection != null
              ? await importSelection(item)
              : item.path != null
              ? await importFile(item.name, item.path!)
              : throw const FormatException('文件未授权，请重新选择');
          if (ids.add(imported.id)) {
            if (before.contains(imported.id)) {
              existing++;
            } else {
              added++;
            }
          }
        } catch (error) {
          failures.add((
            name: item.name,
            message: error is FormatException
                ? error.message.toString()
                : '导入失败，原文件保留，可重新选择后重试',
          ));
        }
      }
    } catch (error) {
      failures.add((
        name: source.name,
        message: error is FormatException
            ? error.message.toString()
            : '无法读取文件，请检查授权后重试',
      ));
    } finally {
      if (releaseSources) {
        try {
          await documents.releaseBooks(temporary);
        } catch (_) {
          onCleanupFailed?.call(temporary);
        }
      }
      onProgress?.call(++done, selections.length);
    }
  }
  return LocalImportReport(
    bookIds: ids.toList(),
    added: added,
    existing: existing,
    failures: failures,
  );
}

class LocalImportGroup {
  const LocalImportGroup({
    required this.seed,
    required this.title,
    required this.volumes,
    this.targetId,
    this.needsTarget = false,
  });
  final int seed;
  final String title;
  final List<({int bookId, String title})> volumes;
  final int? targetId;
  final bool needsTarget;
}

List<LocalImportGroup> localImportGroups(
  LocalBookStore books,
  Iterable<int> imported,
) {
  final groups = <String, List<int>>{};
  for (final id in imported.toSet()) {
    final hint = books.seriesHint(id);
    if (hint != null && books.seriesFor(id) == null) {
      (groups['${hint.key}/${books.book(id)?.author}'] ??= []).add(id);
    }
  }
  return [
    for (final ids in groups.values)
      if (ids.length >= 2)
        (() {
          ids.sort(
            (a, b) => books
                .seriesHint(a)!
                .number
                .compareTo(books.seriesHint(b)!.number),
          );
          return LocalImportGroup(
            seed: ids.first,
            title: books.seriesHint(ids.first)!.title,
            volumes: [
              for (final id in ids)
                (bookId: id, title: books.seriesHint(id)!.volumeTitle),
            ],
          );
        })(),
  ];
}
