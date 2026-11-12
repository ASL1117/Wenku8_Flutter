import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'reading_widget_design.dart';
import 'reading_widget_reference.dart';
import 'reading_widget_snapshot.dart';

/// This fallback is vector-only; it has no external image streams to warm.
Future<void> warmReadingDesktopImages(ReadingWidgetSnapshot data) async {}

Future<Map<String, Uint8List>> renderReadingDesktopCards(
  ReadingWidgetSnapshot data,
) async => {
  for (final brightness in Brightness.values)
    for (final size in ReadingDesktopSize.values)
      '${size.name}_${brightness.name}': await renderReadingDesktopCard(
        data,
        size,
        brightness: brightness,
      ),
};

Future<Uint8List> renderReadingDesktopCard(
  ReadingWidgetSnapshot data,
  ReadingDesktopSize size, {
  Brightness brightness = Brightness.light,
  bool paintQuote = true,
  String? quoteText,
  String quoteSource = '',
  int quoteCount = 0,
}) async {
  final dimensions = size.dimensions;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(2);
  final ink = data.skin.foreground(brightness),
      accent = data.skin.accent(data.localDay);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      Offset.zero & dimensions,
      const Radius.circular(22),
    ),
    Paint()..color = data.skin.background(brightness),
  );
  void text(
    String value,
    double x,
    double y,
    double font, {
    Color? color,
    int lines = 2,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: 'sans-serif',
          fontSize: font,
          fontWeight: FontWeight.w500,
          color: color ?? ink,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: lines,
      ellipsis: '…',
    )..layout(maxWidth: dimensions.width - x - 18);
    painter.paint(canvas, Offset(x, y));
    painter.dispose();
  }

  text(data.design.label, 18, 16, 14, color: accent);
  text(
    widgetDate(data.localDay),
    18,
    38,
    11,
    color: ink.withValues(alpha: .65),
  );
  switch (data.design) {
    case ReadingWidgetDesign.quote:
      if (paintQuote) {
        text(
          quoteText?.trim().isNotEmpty == true ? quoteText! : '尚无摘录',
          18,
          64,
          17,
          lines: size == ReadingDesktopSize.large ? 9 : 3,
        );
        if (data.showBookDetails && quoteSource.isNotEmpty) {
          text(quoteSource, 18, dimensions.height - 28, 11);
        }
      }
    case ReadingWidgetDesign.memory:
      final completion = data.latestCompletion;
      text(
        completion == null
            ? '尚无阅读纪念'
            : completion.finished
            ? '又读完一个故事'
            : '留下一段阅读',
        18,
        65,
        20,
        lines: 2,
      );
      if (data.showBookDetails && completion != null) {
        text(completion.title ?? '阅读纪念', 18, 115, 13);
      }
    case ReadingWidgetDesign.week:
    case ReadingWidgetDesign.calendar:
      final values = data.design == ReadingWidgetDesign.week
          ? data.week.map((v) => v.verifiedSeconds).toList()
          : data.heatmap
                .window(size == ReadingDesktopSize.large ? 12 : 4)
                .map((v) => v.verifiedSeconds)
                .toList();
      final columns =
          data.design == ReadingWidgetDesign.week ||
              size == ReadingDesktopSize.small
          ? 7
          : size == ReadingDesktopSize.large
          ? 12
          : 14;
      final step = (dimensions.width - 36) / columns;
      final box = (step - 3).clamp(2.0, 22.0);
      for (var i = 0; i < values.length; i++) {
        final value = values[i];
        final opacity = value == null
            ? .07
            : value == 0
            ? .15
            : (.3 + value / 3600).clamp(.3, 1.0);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              18 + i % columns * step,
              67 + i ~/ columns * (box + 4),
              box,
              box,
            ),
            const Radius.circular(3),
          ),
          Paint()..color = accent.withValues(alpha: opacity),
        );
      }
      if (size == ReadingDesktopSize.large) {
        text(
          '有记录的阅读：${widgetMinutes(data.weekSeconds)} 分钟',
          18,
          dimensions.height - 38,
          13,
        );
      }
    case ReadingWidgetDesign.classic:
    case ReadingWidgetDesign.focus:
      text(
        '${widgetMinutes(data.verifiedTodaySeconds)} 分钟',
        18,
        66,
        size == ReadingDesktopSize.small ? 24 : 32,
      );
      if (data.dailyGoalMinutes > 0 && data.verifiedTodaySeconds != null) {
        final ratio =
            (data.verifiedTodaySeconds! / (data.dailyGoalMinutes * 60)).clamp(
              0.0,
              1.0,
            );
        final bar = Rect.fromLTWH(18, 113, dimensions.width - 36, 4);
        canvas.drawRect(bar, Paint()..color = accent.withValues(alpha: .15));
        canvas.drawRect(
          Rect.fromLTWH(bar.left, bar.top, bar.width * ratio, bar.height),
          Paint()..color = accent,
        );
      }
      text(
        data.verifiedTodaySeconds == null
            ? '尚无计时记录'
            : '连续达标 ${data.qualifiedStreakDays ?? 0} 天',
        18,
        130,
        11,
      );
      if (data.showBookDetails &&
          data.currentBook != null &&
          size == ReadingDesktopSize.large) {
        text(
          '${data.currentBook!.title}\n${data.currentBook!.chapter}',
          18,
          195,
          15,
          lines: 5,
        );
      }
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (dimensions.width * 2).round(),
    (dimensions.height * 2).round(),
  );
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw StateError('无法生成小组件图片');
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}
