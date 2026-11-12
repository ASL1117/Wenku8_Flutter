import 'package:flutter/material.dart';
import 'catalog.dart';
import 'library_state.dart';
import 'lan_reading_sync.dart';

export 'lan_reading_sync.dart' show LanHandoffReceipt;

class LanHandoffMonitor extends StatelessWidget {
  const LanHandoffMonitor({
    super.key,
    required this.handoff,
    required this.onContinue,
    required this.reduceMotion,
    required this.noticeWrapper,
    required this.child,
  });
  final LanHandoffUnavailable? handoff;
  final Future<void> Function(LanHandoffReceipt) onContinue;
  final bool reduceMotion;
  final Widget Function(Widget) noticeWrapper;
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

class LanSendBookSheet extends StatelessWidget {
  const LanSendBookSheet({
    super.key,
    required this.sync,
    required this.book,
    required this.position,
    required this.reduceMotion,
  });
  final LanReadingSync sync;
  final Novel book;
  final ReadingPosition position;
  final bool reduceMotion;
  @override
  Widget build(BuildContext context) => const SafeArea(
    child: Padding(padding: EdgeInsets.all(24), child: Text('此版本暂不支持附近设备续读')),
  );
}
