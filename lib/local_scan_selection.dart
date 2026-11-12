import 'package:flutter/material.dart';
import 'book_documents.dart';

class LocalScanSelection extends StatefulWidget {
  const LocalScanSelection({super.key, required this.snapshot});
  final BookScanSnapshot snapshot;
  @override
  State<LocalScanSelection> createState() => _LocalScanSelectionState();
}

class _LocalScanSelectionState extends State<LocalScanSelection> {
  late final selected = widget.snapshot.books.map((book) => book.token).toSet();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('选择扫描书籍'),
      actions: [
        TextButton(
          onPressed: () => setState(() {
            if (selected.length == widget.snapshot.books.length) {
              selected.clear();
            } else {
              selected.addAll(widget.snapshot.books.map((book) => book.token));
            }
          }),
          child: const Text('全选 / 取消'),
        ),
      ],
    ),
    body: ListView(
      children: [
        for (final warning in widget.snapshot.warnings)
          ListTile(title: Text(warning)),
        for (final book in widget.snapshot.books)
          CheckboxListTile(
            title: Text(book.name),
            subtitle: Text(widget.snapshot.details[book.token]?.folder ?? ''),
            value: selected.contains(book.token),
            onChanged: (value) => setState(() {
              if (value == true) {
                selected.add(book.token);
              } else {
                selected.remove(book.token);
              }
            }),
          ),
      ],
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: () => Navigator.pop(context, selected.toSet()),
          child: Text('导入 ${selected.length} 本'),
        ),
      ),
    ),
  );
}
