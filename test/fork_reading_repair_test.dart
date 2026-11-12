import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenku8_flutter/reader_paper_geometry.dart';
import 'package:wenku8_flutter/reading_widget_skin.dart';
import 'package:wenku8_flutter/reading_widget_snapshot.dart';
import 'package:wenku8_flutter/reading_widget_design.dart';
import 'package:wenku8_flutter/reading_widget_reference.dart';
import 'package:wenku8_flutter/reading_widget_reference_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('paper ownership changes faces and geometry remains finite', () {
    for (final progress in [0.0, .25, .5, .75, 1.0]) {
      final geometry = ReaderPaperGeometry(
        size: const Size(440, 956),
        gap: 8,
        progress: progress,
        touchY: .7,
      );
      for (final mesh in [geometry.front, geometry.back]) {
        expect(mesh.positions.every((v) => v.isFinite), isTrue);
        expect(mesh.uv.length, mesh.positions.length);
        expect(mesh.normals.length * 2, mesh.positions.length);
        expect(mesh.indices.every((v) => v < mesh.normals.length), isTrue);
      }
      if (progress == 0) {
        expect(geometry.back.indices, isEmpty);
        expect(geometry.front.outline.getBounds().width, closeTo(440, .001));
      }
      if (progress == 1) {
        expect(geometry.front.indices, isEmpty);
        expect(geometry.back.outline.getBounds().width, closeTo(440, .001));
      }
    }
  });
  test(
    'skin identifiers preserve native host fallback and unknown measurements',
    () {
      expect(ReadingWidgetSkin.fromId('future'), ReadingWidgetSkin.original);
      expect(readingDailyGoal(-1), 0);
      expect(readingDailyGoal(9999), 1440);
      expect(readingGoalCaption(30, null), contains('尚无计时数据'));
      expect(readingGoalCaption(30, 120), contains('已读 2 分钟'));
    },
  );
  test(
    'each desktop size produces a complete PNG with doubled dimensions',
    () async {
      final day = DateTime(2026, 11, 11);
      final data = ReadingWidgetSnapshot(
        generatedAt: day,
        localDay: day,
        verifiedTotalSeconds: null,
        verifiedTodaySeconds: null,
        qualifiedStreakDays: null,
        week: [
          for (var i = 6; i >= 0; i--)
            ReadingWidgetDay(
              date: DateTime(2026, 11, 11 - i),
              verifiedSeconds: null,
            ),
        ],
        skin: ReadingWidgetSkin.seasons,
        design: ReadingWidgetDesign.calendar,
      );
      for (final size in ReadingDesktopSize.values) {
        final bytes = await renderReadingDesktopCard(data, size);
        expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, (size.dimensions.width * 2).round());
        expect(frame.image.height, (size.dimensions.height * 2).round());
        frame.image.dispose();
        codec.dispose();
      }
    },
  );
}
