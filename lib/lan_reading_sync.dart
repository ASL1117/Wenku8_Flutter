import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'catalog.dart';
import 'library_state.dart';
import 'local_books.dart';
import 'online_book_handoff.dart';

/// The public source omits pairing and encrypted transfer. This boundary never
/// opens sockets or fabricates a successful sync; the capability stays off.
class LanReadingSync extends ChangeNotifier {
  LanReadingSync({
    required this.state,
    required this.preferences,
    this.books,
    this.repository,
  });
  static const supported = false;
  final LibraryState state;
  final SharedPreferences preferences;
  final LocalBookStore? books;
  final NovelRepository? repository;
  final handoff = LanHandoffUnavailable();
  Future<void> initialize() async {}
  @override
  void dispose() {
    handoff.dispose();
    super.dispose();
  }
}

class LanHandoffReceipt {
  const LanHandoffReceipt({this.online});
  final OnlineBookHandoff? online;
}

class LanHandoffUnavailable extends ChangeNotifier {
  LanHandoffReceipt? get received => null;
  Future<({Novel book, ReadingPosition position})> resolveReceipt(
    LanHandoffReceipt receipt,
  ) => Future.error(const FormatException('此版本暂不支持附近设备续读'));
  void dismissReceipt() {}
}

class LanSyncScope extends InheritedWidget {
  const LanSyncScope({super.key, required this.sync, required super.child});
  final LanReadingSync? sync;
  static LanReadingSync? maybeOf(BuildContext context) {
    // Do not advertise an unavailable transfer capability in reader controls.
    return null;
  }

  @override
  bool updateShouldNotify(LanSyncScope oldWidget) => oldWidget.sync != sync;
}
