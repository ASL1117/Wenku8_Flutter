import 'package:flutter/material.dart';
import 'library_state.dart';
import 'local_books.dart';
import 'local_library_preferences.dart';

Future<void> openLocalBookBatch(
  BuildContext context, {
  required LocalBookStore books,
  required LibraryState library,
  Set<int> selected = const {},
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) =>
        _LocalBookBatchPage(books: books, library: library, selected: selected),
  ),
);

class _LocalBookBatchPage extends StatefulWidget {
  const _LocalBookBatchPage({
    required this.books,
    required this.library,
    required this.selected,
  });
  final LocalBookStore books;
  final LibraryState library;
  final Set<int> selected;
  @override
  State<_LocalBookBatchPage> createState() => _LocalBookBatchPageState();
}

class _LocalBookBatchPageState extends State<_LocalBookBatchPage> {
  late final selected = widget.selected.toSet();
  bool busy = false;
  String? error;
  Future<void> assign(String group) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.library.organization.assignMany(selected, group);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => error = '分类保存失败，原分类保留，请重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('批量整理')),
    body: ListView(
      children: [
        if (error != null) ListTile(title: Text(error!)),
        for (final book in widget.books.books)
          CheckboxListTile(
            title: Text(book.title),
            subtitle: Text(book.author),
            value: selected.contains(book.id),
            onChanged: busy
                ? null
                : (value) => setState(() {
                    if (value == true) {
                      selected.add(book.id);
                    } else {
                      selected.remove(book.id);
                    }
                  }),
          ),
        const Divider(),
        const ListTile(title: Text('将所选书籍归入分类')),
        for (final group in {
          LocalLibraryPreferences.unfiled: '未分类',
          ...widget.library.organization.groups,
        }.entries)
          ListTile(
            title: Text(group.value),
            enabled: !busy && selected.isNotEmpty,
            onTap: busy || selected.isEmpty ? null : () => assign(group.key),
          ),
      ],
    ),
  );
}
