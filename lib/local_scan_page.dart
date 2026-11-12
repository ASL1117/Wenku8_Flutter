import 'package:flutter/material.dart';
import 'book_documents.dart';
import 'local_book_scanner.dart';

class LocalScanPage extends StatefulWidget {
  const LocalScanPage({
    super.key,
    required this.documents,
    required this.changes,
    required this.isBusy,
    required this.progress,
    required this.result,
    required this.failure,
    required this.onScan,
  });
  final BookDocuments documents;
  final Listenable changes;
  final bool Function() isBusy;
  final (int, int)? Function() progress;
  final LocalScanResult? Function() result;
  final String? Function() failure;
  final Future<void> Function(BuildContext) onScan;
  @override
  State<LocalScanPage> createState() => _LocalScanPageState();
}

class _LocalScanPageState extends State<LocalScanPage> {
  BookScanFolder? folder;
  String? error;
  bool working = true;
  Future<void> perform(Future<void> Function() action) async {
    if (mounted) {
      setState(() {
        working = true;
        error = null;
      });
    }
    try {
      await action();
      folder = await widget.documents.scanFolderInfo();
    } catch (_) {
      error = '扫描目录操作未完成，请检查文件授权后重试';
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  void initState() {
    super.initState();
    perform(() async {});
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.changes,
    builder: (context, _) {
      final busy = working || widget.isBusy();
      final progress = widget.progress();
      return Scaffold(
        appBar: AppBar(title: const Text('扫描本地书籍')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(folder?.name ?? '尚未选择扫描目录'),
            if (folder != null && !folder!.readable)
              const Text('目录授权已失效，请重新选择'),
            if (error ?? widget.failure() case final failure?) Text(failure),
            if (widget.result() case final result?) Text(result.summary),
            if (progress != null) Text('正在处理 ${progress.$1} / ${progress.$2}'),
            FilledButton(
              onPressed: busy
                  ? null
                  : () => perform(() async {
                      await widget.documents.selectScanFolder();
                    }),
              child: const Text('选择扫描目录'),
            ),
            SwitchListTile(
              title: const Text('进入书库时自动检查'),
              value: folder?.automatic ?? false,
              onChanged: busy || folder == null
                  ? null
                  : (value) =>
                        perform(() => widget.documents.setScanAutomatic(value)),
            ),
            FilledButton(
              onPressed: busy || folder?.readable != true
                  ? null
                  : () => widget.onScan(context),
              child: const Text('扫描并选择书籍'),
            ),
            TextButton(
              onPressed: busy || folder == null
                  ? null
                  : () => perform(widget.documents.disconnectScanFolder),
              child: const Text('断开目录授权'),
            ),
          ],
        ),
      );
    },
  );
}
