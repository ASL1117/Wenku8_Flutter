import 'package:flutter/material.dart';
import 'reading_widget_reference.dart';
import 'reading_widget_skin.dart';
import 'reading_widget_snapshot.dart';

class ReadingWidgetSkinPicker extends StatelessWidget {
  const ReadingWidgetSkinPicker({
    super.key,
    required this.value,
    required this.size,
    required this.snapshot,
    required this.onChanged,
    required this.previewBuilder,
  });
  final ReadingWidgetSkin value;
  final ReadingDesktopSize size;
  final ReadingWidgetSnapshot snapshot;
  final ValueChanged<ReadingWidgetSkin>? onChanged;
  final Widget Function(ReadingWidgetSkin) previewBuilder;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FittedBox(fit: BoxFit.scaleDown, child: previewBuilder(value)),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final skin in ReadingWidgetSkin.values)
            ChoiceChip(
              label: Text(skin.label),
              selected: skin == value,
              onSelected: onChanged == null ? null : (_) => onChanged!(skin),
            ),
        ],
      ),
    ],
  );
}
