import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'reading_widget_design.dart';
import 'reading_widget_snapshot.dart';
import 'reading_widget_reference_capture.dart';

enum ReadingDesktopSize {
  small(Size(170, 170)),
  medium(Size(364, 170)),
  large(Size(364, 382));

  const ReadingDesktopSize(this.dimensions);
  final Size dimensions;
}

/// Preview and native-host PNG share one vector renderer and measured snapshot.
class ReadingDesktopCard extends StatelessWidget {
  const ReadingDesktopCard({
    super.key,
    required this.data,
    required this.size,
    this.brightness = Brightness.light,
    this.quoteText,
    this.quoteSource = '',
    this.quoteCount = 0,
  });
  final ReadingWidgetSnapshot data;
  final ReadingDesktopSize size;
  final Brightness brightness;
  final String? quoteText;
  final String quoteSource;
  final int quoteCount;
  @override
  Widget build(BuildContext context) => SizedBox.fromSize(
    size: size.dimensions,
    child: FutureBuilder<Uint8List>(
      future: renderReadingDesktopCard(
        data,
        size,
        brightness: brightness,
        quoteText: quoteText,
        quoteSource: quoteSource,
        quoteCount: quoteCount,
      ),
      builder: (context, image) => image.hasData
          ? Image.memory(
              image.data!,
              gaplessPlayback: true,
              fit: BoxFit.contain,
            )
          : ColoredBox(
              color: data.skin.background(brightness),
              child: Center(
                child: image.hasError
                    ? const Icon(Icons.error_outline)
                    : const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
              ),
            ),
    ),
  );
}

String readingDesktopHeading(ReadingWidgetDesign design) => design.label;
