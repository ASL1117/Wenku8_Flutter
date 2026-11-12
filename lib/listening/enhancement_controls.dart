import 'package:flutter/material.dart';
import 'enhancement.dart';

class ListeningEnhancementSettings extends StatelessWidget {
  const ListeningEnhancementSettings({
    super.key,
    required this.enhancement,
    required this.onChanged,
  });
  final ListeningEnhancement enhancement;
  final Future<void> Function(ListeningEnhancementPreference) onChanged;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: enhancement,
    builder: (context, _) {
      if (!enhancement.supported) {
        return const Text('此平台暂不支持额外声音增强，正常朗读音量由系统控制。');
      }
      final value = enhancement.preference;
      return Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('声音增强'),
            value: value.enabled,
            onChanged: (enabled) => onChanged(
              ListeningEnhancementPreference(
                enabled: enabled,
                gainDb: value.gainDb,
              ),
            ),
          ),
          Slider(
            min: 0,
            max: 12,
            divisions: 12,
            value: value.gainDb,
            label: '${value.gainDb.round()} dB',
            onChanged: value.enabled
                ? (gain) => onChanged(
                    ListeningEnhancementPreference(enabled: true, gainDb: gain),
                  )
                : null,
          ),
        ],
      );
    },
  );
}
