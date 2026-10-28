import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// Material 3 theme built from the Pocket tokens.
class AppTheme {
  const AppTheme._();

  /// Tests set this to false so no font is fetched over the network.
  static bool useGoogleFonts = true;

  static TextStyle sans(TextStyle base) => useGoogleFonts ? GoogleFonts.getFont('DM Sans', textStyle: base) : base;

  static TextStyle display(TextStyle base) =>
      useGoogleFonts ? GoogleFonts.getFont('Instrument Serif', textStyle: base) : base.copyWith(fontFamily: 'serif');

  static TextStyle mono(TextStyle base) =>
      useGoogleFonts ? GoogleFonts.getFont('IBM Plex Mono', textStyle: base) : base.copyWith(fontFamily: 'monospace');

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = dark ? Palette.backgroundDark : Palette.background;
    final card = dark ? Palette.cardDark : Palette.card;
    final fg = dark ? Palette.foregroundDark : Palette.foreground;
    final border = dark ? Palette.borderDark : Palette.border;
    final primary = dark ? Palette.primaryDark : Palette.primary;
    final onPrimary = dark ? Palette.onPrimaryDark : Palette.onPrimary;
    final secondary = dark ? Palette.secondaryDark : Palette.secondary;
    final onSecondary = dark ? Palette.onSecondaryDark : Palette.onSecondary;
    final muted = dark ? Palette.mutedDark : Palette.muted;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      secondary: secondary,
      onSecondary: onSecondary,
      tertiary: Palette.gold,
      onTertiary: Palette.onPrimary,
      error: Palette.destructive,
      onError: Palette.onPrimary,
      surface: background,
      onSurface: fg,
      surfaceContainerLowest: card,
      surfaceContainerLow: card,
      surfaceContainer: card,
      surfaceContainerHigh: card,
      surfaceContainerHighest: muted,
      outline: dark ? Palette.inputDark : Palette.input,
      outlineVariant: border,
      secondaryContainer: secondary,
      onSecondaryContainer: onSecondary,
    );

    final base = ThemeData(brightness: brightness, useMaterial3: true).textTheme;
    final textTheme = TextTheme(
      displayLarge: display(base.displayLarge!.copyWith(fontSize: 43, height: 1.04, letterSpacing: -1, fontWeight: FontWeight.w400)),
      displayMedium: display(base.displayMedium!.copyWith(fontSize: 36, height: 1.05, letterSpacing: -0.8, fontWeight: FontWeight.w400)),
      displaySmall: display(base.displaySmall!.copyWith(fontSize: 30, height: 1.1, letterSpacing: -0.5, fontWeight: FontWeight.w400)),
      headlineMedium: display(base.headlineMedium!.copyWith(fontSize: 28, height: 1.1, fontWeight: FontWeight.w400)),
      headlineSmall: sans(base.headlineSmall!.copyWith(fontSize: 23, letterSpacing: -0.55, fontWeight: FontWeight.w400)),
      titleLarge: sans(base.titleLarge!.copyWith(fontSize: 19, letterSpacing: -0.45, fontWeight: FontWeight.w600)),
      titleMedium: sans(base.titleMedium!.copyWith(fontSize: 17, height: 1.35, letterSpacing: -0.3, fontWeight: FontWeight.w600)),
      titleSmall: sans(base.titleSmall!.copyWith(fontSize: 15, fontWeight: FontWeight.w600)),
      bodyLarge: sans(base.bodyLarge!.copyWith(fontSize: 16, height: 1.55)),
      bodyMedium: sans(base.bodyMedium!.copyWith(fontSize: 15, height: 1.55)),
      bodySmall: sans(base.bodySmall!.copyWith(fontSize: 14, height: 1.5)),
      labelLarge: sans(base.labelLarge!.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
      labelMedium: sans(base.labelMedium!.copyWith(fontSize: 13, fontWeight: FontWeight.w500)),
      labelSmall: mono(base.labelSmall!.copyWith(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 1.1)),
    ).apply(bodyColor: fg, displayColor: fg);

    final controlShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control));

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      extensions: [dark ? PocketColors.dark : PocketColors.light],
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card), side: BorderSide(color: border)),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 46),
          shape: controlShape,
          textStyle: textTheme.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 46),
          shape: controlShape,
          foregroundColor: fg,
          side: BorderSide(color: dark ? Palette.inputDark : Palette.input),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 44), shape: controlShape, textStyle: textTheme.labelLarge),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: card,
        selectedColor: secondary,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
        labelStyle: textTheme.labelMedium,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        indicatorColor: secondary,
        height: 72,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: card,
        indicatorColor: secondary,
        selectedLabelTextStyle: textTheme.labelLarge,
        unselectedLabelTextStyle: textTheme.labelMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.surface))),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }
}

/// Shared input decoration (kept out of ThemeData for SDK-version stability).
InputDecoration pocketInput(BuildContext context, {String? label, String? hint, String? helper, String? error, Widget? prefixIcon}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final borderColor = dark ? Palette.inputDark : Palette.input;
  OutlineInputBorder outline(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.control), borderSide: BorderSide(color: c, width: w));
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    errorText: error,
    helperMaxLines: 3,
    errorMaxLines: 3,
    prefixIcon: prefixIcon,
    filled: true,
    fillColor: dark ? Palette.cardDark : Palette.card,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: outline(borderColor),
    enabledBorder: outline(borderColor),
    focusedBorder: outline(Theme.of(context).colorScheme.primary, 1.6),
    errorBorder: outline(Palette.destructive),
    focusedErrorBorder: outline(Palette.destructive, 1.6),
  );
}
