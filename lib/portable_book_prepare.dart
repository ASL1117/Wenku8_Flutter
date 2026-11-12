import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:html/dom.dart' as dom;
import 'dart:ui' show RootIsolateToken;
import 'package:archive/archive.dart';
import 'package:html/parser.dart' as html;
import 'package:markdown/markdown.dart' as markdown;
import 'package:xml/xml.dart';
import 'book_import_limits.dart';
import 'local_book_archive.dart';

typedef PreparedBookDocument = ({String name, String? path, String? error});

/// Owns only run-* temporary folders. User-selected originals are never deleted.
class PortableBookPreparer {
  PortableBookPreparer({
    required this.directory,
    required this.textCodecToken,
    required this.decodeNames,
    required this.convert,
    required this.extractKindle,
    this.extractPdf,
  });
  final Directory directory;
  final RootIsolateToken textCodecToken;
  final Future<List<String>> Function(List<Uint8List>) decodeNames;
  final Future<List<PreparedBookDocument>> Function(String, String) convert;
  final Future<int> Function(String, String) extractKindle;
  final Future<void> Function(String, String, String)? extractPdf;
  static Future<void> clearPreviousRuns(Directory directory) async {
    if (!await directory.exists()) return;
    await for (final entry in directory.list(followLinks: false)) {
      if (entry.uri.pathSegments
          .where((s) => s.isNotEmpty)
          .last
          .startsWith('run-')) {
        await entry.delete(recursive: entry is Directory);
      }
    }
  }

  Future<void> releasePaths(Iterable<String> paths) async {
    if (!await directory.exists()) return;
    final root = await directory.resolveSymbolicLinks();
    for (final path in paths.toSet()) {
      final file = File(path);
      if (!await file.exists()) continue;
      final resolved = await file.resolveSymbolicLinks();
      if (resolved.startsWith('$root${Platform.pathSeparator}')) {
        await file.delete();
      }
    }
  }

  Future<List<PreparedBookDocument>> prepare(String name, String path) async {
    if (!supportsBookImport(name)) {
      return [(name: name, path: null, error: '不支持此文件格式')];
    }
    final input = File(path);
    if (await input.length() > localBookByteLimit(name)) {
      throw FormatException(localBookSizeMessage(name));
    }
    await directory.create(recursive: true);
    final run = await directory.createTemp('run-');
    try {
      return await _prepare(name, input, run, 0);
    } catch (_) {
      await run.delete(recursive: true);
      rethrow;
    }
  }

  Future<List<PreparedBookDocument>> _prepare(
    String name,
    File file,
    Directory run,
    int depth,
  ) async {
    final ext = name.split('.').last.toLowerCase();
    if (ext == 'txt' || ext == 'epub') {
      return [(name: name, path: file.path, error: null)];
    }
    if (ext == 'zip') {
      if (depth > 0) throw const FormatException('不支持嵌套 ZIP，请先解压内层文件');
      final input = InputFileStream(file.path);
      try {
        final archive = readLocalBookArchive(
          input,
          maxSize: 1024 * 1024 * 1024,
          maxEntrySize: maxLocalArchiveBytes,
        );
        final values = <PreparedBookDocument>[];
        for (final entry in archive) {
          if (!entry.isFile || !supportsBookImport(entry.name)) continue;
          if (entry.size > localBookByteLimit(entry.name)) {
            values.add((
              name: entry.name,
              path: null,
              error: localBookSizeMessage(entry.name),
            ));
            continue;
          }
          final target = File('${run.path}/members/${entry.name}');
          await target.parent.create(recursive: true);
          await target.writeAsBytes(readLocalBookArchiveEntry(entry));
          try {
            values.addAll(
              await _prepare(
                entry.name.split('/').last,
                target,
                run,
                depth + 1,
              ),
            );
          } catch (error) {
            values.add((
              name: entry.name,
              path: null,
              error: error is FormatException
                  ? error.message.toString()
                  : '压缩成员转换失败',
            ));
          }
        }
        if (values.isEmpty) throw const FormatException('压缩包没有支持的书籍文件');
        return values;
      } finally {
        await input.close();
      }
    }
    final stem = name
        .split(RegExp(r'[/\\]'))
        .last
        .replaceFirst(RegExp(r'\.[^.]+$'), '');
    final output = await run.createTemp('converted-');
    if (bookFormatKey(name) == 'kindle') {
      final status = await extractKindle(file.path, output.path);
      if (status != 0) {
        throw FormatException(
          status == 1 ? '不支持加密或 DRM Kindle 书籍' : 'Kindle 文件解析失败（$status）',
        );
      }
      final opf = File('${output.path}/content.opf');
      if (!await opf.exists()) throw const FormatException('Kindle 转换未生成有效书籍');
      final zip = Archive();
      zip.addFile(
        ArchiveFile.string('mimetype', 'application/epub+zip')
          ..compression = CompressionType.none,
      );
      zip.addFile(
        ArchiveFile.string(
          'META-INF/container.xml',
          '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
        ),
      );
      await for (final entity in output.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          final relative = entity.path
              .substring(output.path.length + 1)
              .replaceAll('\\', '/');
          zip.addFile(ArchiveFile.bytes(relative, await entity.readAsBytes()));
        }
      }
      final target = File('${output.path}/$stem.epub');
      await target.writeAsBytes(ZipEncoder().encode(zip));
      return [(name: '$stem.epub', path: target.path, error: null)];
    }
    if (ext == 'pdf') {
      if (extractPdf == null) return convert(name, file.path);
      await extractPdf!(name, file.path, output.path);
      final text = File('${output.path}/content.txt');
      if (!await text.exists() || await text.length() == 0) {
        throw const FormatException('PDF 没有可提取的文字；不进行 OCR 或密码破解');
      }
      return [(name: '$stem.txt', path: text.path, error: null)];
    }
    String text;
    if (ext == 'docx') {
      final input = InputFileStream(file.path);
      try {
        final zip = readLocalBookArchive(
          input,
          maxSize: 1024 * 1024 * 1024,
          maxEntrySize: maxLocalArchiveBytes,
        );
        final part = zip.findFile('word/document.xml');
        if (part == null) throw const FormatException('DOCX 缺少正文');
        final doc = XmlDocument.parse(
          utf8.decode(readLocalBookArchiveEntry(part)),
        );
        text = doc.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 'p')
            .map(
              (p) => p.descendants
                  .whereType<XmlElement>()
                  .where((e) => e.name.local == 't')
                  .map((e) => e.innerText)
                  .join(),
            )
            .join('\n\n');
      } finally {
        await input.close();
      }
    } else if (ext == 'fb2') {
      final doc = XmlDocument.parse(await file.readAsString());
      text = doc.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'p')
          .map((e) => e.innerText)
          .join('\n\n');
    } else if (bookFormatKey(name) == 'html' ||
        bookFormatKey(name) == 'markdown') {
      var source = await file.readAsString();
      if (bookFormatKey(name) == 'markdown') {
        source = markdown.markdownToHtml(source);
      }
      final doc = html.parse(source);
      for (final e in doc.querySelectorAll('script,style')) {
        e.remove();
      }
      for (final e in doc.querySelectorAll('p,div,h1,h2,h3,br,li,tr')) {
        e.nodes.add(dom.Text('\n'));
      }
      text = doc.body?.text ?? '';
    } else {
      // Platform converters may implement additional formats; unsupported input
      // must remain an explicit error, never import control codes as prose.
      return convert(name, file.path);
    }
    if (text.trim().isEmpty) throw const FormatException('文件中没有可读取的正文');
    final target = File('${output.path}/$stem.txt');
    await target.writeAsString(text, encoding: utf8);
    return [(name: '$stem.txt', path: target.path, error: null)];
  }
}
