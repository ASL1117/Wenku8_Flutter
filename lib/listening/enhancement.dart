import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class ListeningEnhancementPreference {
  const ListeningEnhancementPreference({this.enabled = false, this.gainDb = 0});
  final bool enabled;
  final double gainDb;
  Map<String, Object> toJson() => {'enabled': enabled, 'gainDb': gainDb};
  factory ListeningEnhancementPreference.fromJson(
    Map<dynamic, dynamic> value,
  ) => ListeningEnhancementPreference(
    enabled: value['enabled'] == true,
    gainDb: value['gainDb'] is num && (value['gainDb'] as num).isFinite
        ? (value['gainDb'] as num).toDouble().clamp(0, 12)
        : 0,
  );
}

class ListeningEnhancement extends ChangeNotifier {
  final effect = AndroidLoudnessEnhancer();
  bool _disposed = false;
  ListeningEnhancementPreference preference =
      const ListeningEnhancementPreference();
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Future<void> configure(
    ListeningEnhancementPreference value, {
    int? audioSessionId,
  }) async {
    if (_disposed) return;
    if (value.gainDb.isNaN || value.gainDb < 0 || value.gainDb > 12) {
      throw const FormatException('声音增强范围为 0～12 dB');
    }
    if (supported) {
      await effect.setTargetGain(value.gainDb);
      await effect.setEnabled(value.enabled);
    }
    preference = value;
    if (!_disposed) notifyListeners();
  }

  Future<void> setPreference(ListeningEnhancementPreference value) =>
      configure(value);
  @override
  Future<void> dispose() async {
    _disposed = true;
    super.dispose();
  }
}
