import 'package:flutter/material.dart';

/// IDs and palette match the native WidgetKit/Android widget hosts.
enum ReadingWidgetSkin {
  original('原有主题'),
  seasons('四季'),
  archive('档案'),
  night('夜读'),
  film('胶片'),
  paper('纸笺');

  const ReadingWidgetSkin(this.label);
  final String label;
  static ReadingWidgetSkin fromId(String? id) =>
      values.where((v) => v.name == id).firstOrNull ?? original;
  Color background(Brightness brightness) => switch (this) {
    night => const Color(0xff101419),
    film => const Color(0xff10100f),
    paper => const Color(0xffecece5),
    original when brightness == Brightness.dark => const Color(0xff18232c),
    _ => const Color(0xfff4f0e6),
  };
  Color foreground(Brightness brightness) =>
      this == night ||
          this == film ||
          this == original && brightness == Brightness.dark
      ? const Color(0xfff6f1e6)
      : const Color(0xff272c29);
  Color accent(DateTime date) => switch (this) {
    seasons =>
      const [
        Color(0xffaf7d8b),
        Color(0xff5786a2),
        Color(0xffb18842),
        Color(0xff4f8985),
      ][date.month >= 3 && date.month <= 5
          ? 0
          : date.month >= 6 && date.month <= 8
          ? 1
          : date.month >= 9 && date.month <= 11
          ? 2
          : 3],
    night || film => const Color(0xffdcb65e),
    paper => const Color(0xff606d5d),
    _ => const Color(0xff4f8985),
  };
}

int readingDailyGoal(int? minutes) =>
    minutes == null || minutes < 0 ? 0 : minutes.clamp(0, 1440);
String readingGoalCaption(int minutes, int? seconds) {
  final goal = readingDailyGoal(minutes);
  if (goal == 0) return '按自己的节奏阅读';
  if (seconds == null) return '每日目标 $goal 分钟 · 尚无计时数据';
  return '每日目标 $goal 分钟 · 已读 ${seconds ~/ 60} 分钟';
}
