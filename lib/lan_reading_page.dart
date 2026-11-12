import 'package:flutter/material.dart';
import 'lan_reading_sync.dart';

class LanReadingPage extends StatelessWidget {
  const LanReadingPage({
    super.key,
    required this.sync,
    required this.reduceMotion,
  });
  final LanReadingSync sync;
  final bool reduceMotion;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('附近设备续读')),
    body: const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('此版本暂不支持附近设备续读。请使用本地备份导入导出迁移阅读资料。'),
      ),
    ),
  );
}
