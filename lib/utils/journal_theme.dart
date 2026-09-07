import 'package:flutter/material.dart';

/// Design tokens for the Journal tab.
///
/// Reconciles two inputs: the "Terra / Rooted Warmth" system (warm ground, very
/// soft shadows, tonal separation over hard borders) and the Stitch journal mock
/// (translucent cards, accent-tinted icon tiles, week dots, full-bleed progress
/// rail). Where the two disagree on the Journal page specifically, the mock
/// wins; where the mock relied on a photo backdrop we don't ship, the Terra
/// ground stands in.
///
/// Resolve once per build with `JournalTheme.of(context)` and read fields off
/// the result. Every colour has a light and a dark value; the dark ground stays
/// warm (green undertone) rather than the mock's cold slate, so it reads as the
/// same family with the lights off.
class JournalTheme {
  final bool isDark;

  const JournalTheme._(this.isDark);

  factory JournalTheme.of(BuildContext context) =>
      JournalTheme._(Theme.of(context).brightness == Brightness.dark);

  // ---------------------------------------------------------------- surfaces
  /// Page ground. Warm cream by day, warm near-black by night — never a
  /// sterile white or a cold slate.
  Color get background =>
      isDark ? const Color(0xFF161815) : const Color(0xFFFAF6F0);

  /// Card fill. A translucent lift off [background] so cards read as layered
  /// tone rather than as outlined boxes.
  Color get surface => isDark
      ? Colors.white.withValues(alpha: 0.05)
      : Colors.white.withValues(alpha: 0.55);

  /// Slightly brighter fill for the greeting panel and the add-habit button.
  Color get surfaceBright => isDark
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.white.withValues(alpha: 0.70);

  /// Low-opacity outline. Tonal separation does most of the work; this only
  /// keeps the card edge from dissolving into the ground.
  Color get outline => isDark
      ? Colors.white.withValues(alpha: 0.10)
      : const Color(0xFFC4C8BC).withValues(alpha: 0.55);

  /// One very soft shadow. No stacked elevations. Deeper in dark, where a
  /// 6%-opacity shadow would be invisible.
  List<BoxShadow> get shadow => [
        BoxShadow(
          color: isDark
              ? Colors.black.withValues(alpha: 0.30)
              : const Color(0xFF2E3230).withValues(alpha: 0.06),
          blurRadius: 20,
          offset: const Offset(0, 4),
        ),
      ];

  /// Fill for calendar cells that carry no state — adjacent months, and days
  /// that haven't happened yet.
  Color get inertCell => isDark
      ? Colors.white.withValues(alpha: 0.04)
      : Colors.black.withValues(alpha: 0.03);

  Color get progressTrack =>
      isDark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.05);

  // ------------------------------------------------------------------- text
  Color get textPrimary =>
      isDark ? const Color(0xFFECEFE9) : const Color(0xFF2E3230);

  Color get textSecondary =>
      isDark ? const Color(0xFFC2C7BC) : const Color(0xFF4A4E4A);

  Color get textMuted =>
      isDark ? const Color(0xFF8A9086) : const Color(0xFF74796E);

  // ------------------------------------------------------------------ accent
  /// Action colour for the add-habit affordance. Kept distinct from every
  /// habit accent so "add" never reads as a habit; lifted in dark so it keeps
  /// its contrast against the near-black ground.
  Color get action => isDark ? const Color(0xFFC084FC) : const Color(0xFF9333EA);

  /// Missed-day red.
  Color get incomplete =>
      isDark ? const Color(0xFFEF5350) : const Color(0xFFE57373);

  /// Completed-day green. Pairs tonally with [incomplete] for the radial
  /// habit tracker, which marks every habit done/missed the same two colours
  /// rather than each habit's own accent, so all rings read at a glance.
  Color get complete =>
      isDark ? const Color(0xFF66BB6A) : const Color(0xFF81C784);

  /// A habit's accent, adjusted for the current ground.
  ///
  /// The six habit colours were picked against cream. Deep ones (Steps
  /// `#2E7D32`, Water `#0097A7`) go muddy on a near-black ground, so dark mode
  /// lifts lightness by 15% and caps it at 70% — enough to separate from the
  /// background without turning pastel.
  Color accent(Color base) {
    if (!isDark) return base;
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withLightness((hsl.lightness + 0.15).clamp(0.0, 0.70))
        // Warm hues (Exercise's coral, Reading's amber) read as muddy brown
        // once they're thinned over a near-black ground. A little extra
        // saturation keeps the hue identifiable at tint opacities.
        .withSaturation((hsl.saturation + 0.10).clamp(0.0, 1.0))
        .toColor();
  }

  /// Text/pip colour that stays legible on top of a solid [accent] fill.
  /// Lifted accents in dark mode can be light enough to need dark ink.
  Color onAccent(Color resolvedAccent) =>
      ThemeData.estimateBrightnessForColor(resolvedAccent) == Brightness.dark
          ? Colors.white
          : Colors.black87;

  // ------------------------------------------------------------------ opacity
  //
  // The accent-opacity ladder carried over from the Journey tab's
  // ActivityInputCard: the same habit colour reused at rising opacity as
  // elements get smaller and more interactive. Every step is nudged up in dark,
  // where a tint over near-black reads far fainter than the same tint over
  // cream.
  double get tintIcon => isDark ? 0.32 : 0.15;
  double get tintBadge => isDark ? 0.28 : 0.15;
  double get tintDotFill => isDark ? 0.55 : 0.30;
  double get tintDotIdle => isDark ? 0.15 : 0.10;
  double get tintDotBorder => isDark ? 0.35 : 0.30;
  double get tintRing => isDark ? 0.90 : 0.80;
  double get tintMissedCell => isDark ? 0.20 : 0.12;

  // ------------------------------------------------------------------- type
  //
  // Sizes mirror the mock's `can-*` scale. The mock also specifies Literata
  // (headlines) and Nunito Sans (body); neither is bundled and `google_fonts`
  // is not a dependency, so weight, size, spacing and colour carry the voice
  // instead.
  static const double sizeEmoji = 24;
  static const double sizeLabel = 12;
  static const double sizeValue = 18;
  static const double sizeUnit = 10;

  TextStyle get habitName => TextStyle(
        fontSize: sizeLabel,
        height: 16 / sizeLabel,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: textPrimary,
      );

  TextStyle get habitTarget => TextStyle(
        fontSize: sizeUnit,
        height: 14 / sizeUnit,
        fontWeight: FontWeight.w400,
        color: textSecondary,
      );

  TextStyle habitValue(Color resolvedAccent) => TextStyle(
        fontSize: sizeValue,
        height: 24 / sizeValue,
        fontWeight: FontWeight.w700,
        color: resolvedAccent,
      );

  static const TextStyle dayLetter = TextStyle(
    fontSize: sizeUnit,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
  );

  TextStyle get headline => TextStyle(
        fontSize: 28,
        height: 36 / 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: textPrimary,
      );

  TextStyle get subhead => TextStyle(
        fontSize: 14,
        height: 22 / 14,
        fontWeight: FontWeight.w600,
        color: textSecondary,
      );

  // ------------------------------------------------------------------ shape
  static const double radiusCard = 16;
  static const double radiusTile = 12;
  static const double radiusChip = 8;
  static const double radiusCell = 10;

  /// Height of the full-bleed progress rail at the foot of each habit card.
  static const double progressHeight = 6;

  // ----------------------------------------------------------------- helpers
  /// Groups an integer with commas: 6500 -> "6,500".
  static String formatCount(int value) {
    final digits = value.abs().toString();
    final buffer = StringBuffer(value < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  /// Single-letter weekday label, Monday-first: M T W T F S S.
  static String weekdayLetter(DateTime date) =>
      const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][date.weekday - 1];
}
