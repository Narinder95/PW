import 'package:shared_preferences/shared_preferences.dart';

import 'sprite_library.dart';

/// Picks which streak-celebration sprite sheet to play next.
///
/// Cycles through every `streak_N` clip the atlas manifest actually contains
/// (see the `streak_*` entries in `tool/build_atlases.dart`), in order,
/// wrapping back to the first — a literal round robin across the art, not one
/// keyed to the user's streak count. The position is persisted so relaunching
/// the app mid-cycle doesn't always replay the same clip first.
class StreakCelebrationPicker {
  static const _prefsKey = 'pw.streakCelebration.nextIndex';

  final SpriteLibrary _library;

  StreakCelebrationPicker({SpriteLibrary? library})
      : _library = library ?? SpriteLibrary.instance;

  /// The next clip's manifest name (e.g. `streak_3`), or null if none built.
  Future<String?> next() async {
    final names = await _library.namesWithPrefix('streak_');
    if (names.isEmpty) return null;

    SharedPreferences? prefs;
    var index = 0;
    try {
      prefs = await SharedPreferences.getInstance();
      index = prefs.getInt(_prefsKey) ?? 0;
    } on Exception {
      prefs = null;
    }

    final name = names[index % names.length];

    try {
      await prefs?.setInt(_prefsKey, (index + 1) % names.length);
    } on Exception {
      // Best-effort: a lost rotation just repeats a clip once.
    }

    return name;
  }
}
