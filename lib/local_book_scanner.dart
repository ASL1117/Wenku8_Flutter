import 'book_documents.dart';
import 'local_import_batch.dart';

class LocalScanResult {
  const LocalScanResult({
    required this.report,
    required this.total,
    this.unchanged = 0,
    this.warnings = const [],
    this.pending = 0,
  });
  final LocalImportReport report;
  final int total, unchanged, pending;
  final List<String> warnings;
  String get summary =>
      '${report.summary}，未变化 $unchanged 本${pending == 0 ? '' : '，待确认 $pending 本'}';
}

Future<LocalScanResult> scanLocalBooks({
  required BookDocuments documents,
  required BookScanSnapshot snapshot,
  required Set<String> selectedTokens,
  required Future<LocalImportReport> Function(BookDocumentSelection)
  importSource,
  bool linkText = true,
  bool Function()? current,
  void Function(int done, int total)? onProgress,
}) async {
  final ids = <int>{},
      failures = <LocalImportNotice>[],
      notices = <LocalImportNotice>[];
  var added = 0, existing = 0, done = 0;
  final selected = snapshot.books
      .where((book) => selectedTokens.contains(book.token))
      .toList();
  try {
    for (final book in selected) {
      if (current != null && !current()) break;
      BookDocumentSelection? staged;
      try {
        staged =
            linkText &&
                RegExp(
                  r'\.(txt|epub)$',
                  caseSensitive: false,
                ).hasMatch(book.name)
            ? await documents.linkScanBook(book.token)
            : await documents.stageScanBook(book.token);
        final result = await importSource(staged);
        ids.addAll(result.bookIds);
        added += result.added;
        existing += result.existing;
        failures.addAll(result.failures);
        notices.addAll(result.notices);
        // Acknowledge only complete imports; failed category writes remain retryable.
        if (result.failures.isEmpty &&
            result.notices.isEmpty &&
            result.bookIds.isNotEmpty) {
          await documents.markScanBook(book.token);
        }
      } catch (_) {
        failures.add((name: book.name, message: '扫描文件导入未完成，请重试'));
      } finally {
        if (staged != null) {
          try {
            await documents.releaseBooks([staged]);
          } catch (_) {
            notices.add((name: book.name, message: '已完成处理，临时文件清理未完成'));
          }
        }
        onProgress?.call(++done, selected.length);
      }
    }
  } finally {
    await documents.finishBookScan();
  }
  return LocalScanResult(
    report: LocalImportReport(
      bookIds: ids.toList(),
      added: added,
      existing: existing,
      failures: failures,
      notices: notices,
    ),
    total: snapshot.total,
    unchanged: snapshot.unchanged,
    warnings: snapshot.warnings,
    pending: snapshot.books.length - done,
  );
}
