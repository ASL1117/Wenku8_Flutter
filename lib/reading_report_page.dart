import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'app_ui.dart';
import 'catalog.dart';
import 'feature_pages.dart';
import 'library_state.dart';
import 'local_platform.dart';
import 'reading_report_options.dart';
import 'reading_report_range.dart';
import 'reading_statistics_data.dart';

/// A deterministic report of measured records. Missing historical measurements
/// remain unavailable, and privacy choices apply before pixels are generated.
Future<Uint8List> renderReadingReportPng(
  ReadingStatisticsData data,
  ReadingReportOptions options,
) async {
  final lines = <String>[
    options.title.trim().isEmpty ? '我的阅读报告' : options.title.trim(),
    '${statisticsDate(data.dates.first)} — ${statisticsDate(data.dates.last)}',
    if (options.nickname.trim().isNotEmpty) options.nickname.trim(),
    data.observedDays == 0
        ? '所选日期尚无计时记录'
        : '记录内阅读 ${statisticsDuration(data.periodSeconds)}',
    '活跃 ${data.activeDays} 天 · 阅读 ${data.periodBooks} 本',
    if (options.modules.contains(ReadingReportModule.rhythm))
      '有记录日均 ${data.observedDays == 0 ? '—' : statisticsDuration(data.averageSeconds)}',
    if (options.modules.contains(ReadingReportModule.days))
      '历史最长连续阅读 ${data.longestStreak} 天',
    if (options.modules.contains(ReadingReportModule.progress))
      '累计读完 ${data.finishedBooks} 本 · 进度未知 ${data.unknownProgress} 本',
    if (options.modules.contains(ReadingReportModule.collection))
      '当前书库：在线 ${data.onlineBooks} 本 · 本地 ${data.localBooks} 本',
    if (options.modules.contains(ReadingReportModule.books)) ...[
      '相伴书单',
      if (data.booksByReadingDays.isEmpty) '所选日期尚无书目记录',
      for (final book in data.booksByReadingDays.take(options.bookLimit))
        '${options.hideBookTitles ? '书籍' : book.title ?? '未缓存书名'} · ${book.days} 天${!options.hideAuthorNames && book.author?.isNotEmpty == true ? ' · ${book.author}' : ''}',
    ],
    if (options.modules.contains(ReadingReportModule.excerpts)) ...[
      '书签 ${data.bookmarks} 条 · 划线 ${data.underlines} 条',
      for (final excerpt in data.excerpts.take(3)) ...[
        excerpt.quote,
        if (!options.hideBookTitles) '—— ${excerpt.title}',
        if (options.includeNotes && excerpt.note.isNotEmpty) excerpt.note,
      ],
    ],
    if (options.note.trim().isNotEmpty) options.note.trim(),
    if (options.signature) '轻小说文库 · 阅读记录',
  ];
  final theme = options.template.theme;
  final accent = switch (options.palette) {
    ReadingReportPalette.pine => theme.accent,
    ReadingReportPalette.vermilion => const Color(0xffb4493f),
    ReadingReportPalette.blue => const Color(0xff3e6b93),
    ReadingReportPalette.plum => const Color(0xff80587d),
  };
  final painters = <TextPainter>[];
  for (var i = 0; i < lines.length; i++) {
    painters.add(
      TextPainter(
        text: TextSpan(
          text: lines[i],
          style: TextStyle(
            color: i == 0 ? accent : theme.foreground,
            fontSize: i == 0 ? 29 : 16,
            fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w400,
            height: 1.6,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 8,
        ellipsis: '…',
      )..layout(maxWidth: 512),
    );
  }
  final calendar = options.modules.contains(ReadingReportModule.calendar);
  final calendarHeight = calendar
      ? ((data.dates.length + 13) ~/ 14) * 21 + 20
      : 0;
  final height = painters
      .fold<double>(
        88 + calendarHeight.toDouble(),
        (sum, p) => sum + p.height + 17,
      )
      .ceil();
  if (height > 8192) throw const FormatException('报告内容过长，请减少书目或摘录');
  final recorder = ui.PictureRecorder();
  // Record one bounded canvas; preview and shared image use the same bytes.
  final surface = Canvas(recorder);
  surface.drawRect(
    Rect.fromLTWH(0, 0, 576, height.toDouble()),
    Paint()..color = theme.background,
  );
  var y = 36.0;
  for (final painter in painters) {
    painter.paint(surface, Offset(32, y));
    y += painter.height + 17;
    painter.dispose();
  }
  if (calendar) {
    for (var i = 0; i < data.seconds.length; i++) {
      final seconds = data.seconds[i];
      final rect = Rect.fromLTWH(32 + i % 14 * 36, y + i ~/ 14 * 21, 18, 18);
      final paint = Paint()
        ..color = accent.withValues(
          alpha: seconds == null
              ? .15
              : seconds == 0
              ? .2
              : (.35 + seconds / 3600).clamp(.35, 1),
        );
      if (seconds == null) paint.style = PaintingStyle.stroke;
      surface.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        paint,
      );
    }
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(576, height);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('无法生成报告图片');
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

class ReadingReportPage extends StatefulWidget {
  const ReadingReportPage({
    super.key,
    required this.state,
    required this.repository,
    this.now,
    this.initialRange,
  });
  final LibraryState state;
  final NovelRepository repository;
  final DateTime? now;
  final ReadingReportRange? initialRange;
  @override
  State<ReadingReportPage> createState() => _ReadingReportPageState();
}

class _ReadingReportPageState extends State<ReadingReportPage> {
  ReadingReportOptions _options = const ReadingReportOptions();
  Future<Uint8List>? _image;
  bool _sharing = false;
  String? _error;
  late final DateTime _now = widget.now ?? DateTime.now();
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var options = await ReadingReportOptions.load();
    final range = widget.initialRange;
    if (range != null) {
      options = options.copyWith(
        period: range.period,
        from: range.from,
        until: range.until,
        clearDates: !range.custom,
      );
    }
    if (!mounted) return;
    _update(options);
  }

  void _update(ReadingReportOptions options) {
    final data = ReadingStatisticsData(
      state: widget.state,
      repository: widget.repository,
      now: options.endAt(_now),
      period: options.daysAt(_now),
      snapshotAt: _now,
    );
    setState(() {
      _options = options;
      _error = null;
      _image = renderReadingReportPng(data, options);
    });
  }

  Future<void> _dates() async {
    final dates = await pickReadingReportRange(
      context,
      now: _now,
      range: _options.range,
    );
    if (dates != null && mounted) {
      _update(_options.copyWith(from: dates.start, until: dates.end));
    }
  }

  Future<void> _share() async {
    if (_sharing || _image == null) return;
    setState(() {
      _sharing = true;
      _error = null;
    });
    try {
      final bytes = await _image!;
      await _options.save();
      await LocalPlatform.shareImage(bytes, 'reading-report.png');
    } catch (_) {
      if (mounted) setState(() => _error = '报告未能分享，请重试');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) => ArchiveFeaturePage(
    title: '阅读报告',
    code: 'READING / REPORT',
    child: ListView(
      padding: featurePadding(context),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final days in [7, 30, 90, 365])
              ChoiceChip(
                label: Text('$days 天'),
                selected: !_options.range.custom && _options.period == days,
                onSelected: (_) =>
                    _update(_options.copyWith(period: days, clearDates: true)),
              ),
            ActionChip(label: const Text('选择日期'), onPressed: _dates),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final theme in ReadingReportTemplate.values)
              ChoiceChip(
                label: Text(theme.label),
                selected: theme == _options.template,
                onSelected: (_) => _update(_options.copyWith(template: theme)),
              ),
          ],
        ),
        SwitchListTile(
          title: const Text('隐藏书名'),
          value: _options.hideBookTitles,
          onChanged: (value) =>
              _update(_options.copyWith(hideBookTitles: value)),
        ),
        SwitchListTile(
          title: const Text('隐藏作者'),
          value: _options.hideAuthorNames,
          onChanged: (value) =>
              _update(_options.copyWith(hideAuthorNames: value)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final module in ReadingReportModule.values)
              FilterChip(
                label: Text(module.label),
                selected: _options.modules.contains(module),
                onSelected: (value) {
                  final modules = {..._options.modules};
                  value ? modules.add(module) : modules.remove(module);
                  _update(_options.copyWith(modules: modules));
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (_image != null)
          FutureBuilder<Uint8List>(
            future: _image,
            builder: (context, image) => image.hasData
                ? Image.memory(image.data!, gaplessPlayback: true)
                : image.hasError
                ? const Text('报告未能生成，请减少所选内容后重试')
                : const Center(child: CircularProgressIndicator()),
          ),
        const SizedBox(height: 16),
        GlassTextButton(
          onPressed: _sharing ? null : _share,
          child: Text(_sharing ? '正在生成分享图片' : '分享报告图片'),
        ),
        if (_error != null) Text(_error!),
      ],
    ),
  );
}
