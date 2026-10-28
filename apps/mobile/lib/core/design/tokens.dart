import 'package:flutter/material.dart';

/// Design tokens ported from the Career Ops web stylesheet (paper / sage / orange).
class Palette {
  const Palette._();

  // Light ("paper")
  static const background = Color(0xFFF7F7F2);
  static const foreground = Color(0xFF303A2C);
  static const card = Color(0xFFFFFEFA);
  static const primary = Color(0xFFC9532D);
  static const onPrimary = Color(0xFFFFFAF4);
  static const secondary = Color(0xFFE9EEDF);
  static const onSecondary = Color(0xFF475A38);
  static const muted = Color(0xFFEFEFE7);
  static const mutedForeground = Color(0xFF5B6252);
  static const accent = Color(0xFFE8EBDF);
  static const destructive = Color(0xFFAE3E35);
  static const border = Color(0xFFE1E4D9);
  static const input = Color(0xFFD9DDD0);
  static const ring = Color(0xFFAB633E);
  static const olive = Color(0xFF414D38);
  static const sage = Color(0xFFE7EDDF);
  static const gold = Color(0xFFB38711);
  static const peach = Color(0xFFF6E8DD);
  static const softOrange = Color(0xFFEECFBA);
  static const brandDash = Color(0xFF8C8F81);

  // Dark ("evening")
  static const backgroundDark = Color(0xFF20281E);
  static const foregroundDark = Color(0xFFEEEEE2);
  static const cardDark = Color(0xFF293126);
  static const primaryDark = Color(0xFFE6865E);
  static const onPrimaryDark = Color(0xFF24291F);
  static const secondaryDark = Color(0xFF3A4733);
  static const onSecondaryDark = Color(0xFFDAE2CD);
  static const mutedDark = Color(0xFF313C2A);
  static const mutedForegroundDark = Color(0xFFD1DCC5);
  static const accentDark = Color(0xFF394432);
  static const borderDark = Color(0xFF414A39);
  static const inputDark = Color(0xFF515B47);
  static const sageDark = Color(0xFF37462D);
  static const peachDark = Color(0xFF463829);
}

class Radii {
  const Radii._();
  static const card = 15.0;
  static const surface = 17.0;
  static const control = 9.0;
  static const chip = 7.0;
}

/// Status chip colours (same in both themes, as in the web app).
class StatusColors {
  const StatusColors._();

  static ({Color bg, Color fg}) of(String status) {
    switch (status) {
      case 'Inbox':
        return (bg: const Color(0xFFEEEEE7), fg: const Color(0xFF4E5145));
      case 'Applied':
        return (bg: const Color(0xFFE5EAFA), fg: const Color(0xFF4E577E));
      case 'Interview':
        return (bg: const Color(0xFFF6E8D8), fg: const Color(0xFF6F3C00));
      case 'Offer':
      case 'Hired':
        return (bg: const Color(0xFFE6EFDB), fg: const Color(0xFF385515));
      case 'Rejected':
      case 'Discarded':
        return (bg: const Color(0xFFF5E6E1), fg: const Color(0xFF71382E));
      default:
        return (bg: Palette.secondary, fg: const Color(0xFF41582F));
    }
  }
}

/// Extra semantic colours not covered by [ColorScheme].
@immutable
class PocketColors extends ThemeExtension<PocketColors> {
  const PocketColors({
    required this.muted,
    required this.mutedForeground,
    required this.border,
    required this.sage,
    required this.peach,
    required this.scoreText,
    required this.lowScoreText,
  });

  final Color muted;
  final Color mutedForeground;
  final Color border;
  final Color sage;
  final Color peach;
  final Color scoreText;
  final Color lowScoreText;

  static const light = PocketColors(
    muted: Palette.muted,
    mutedForeground: Palette.mutedForeground,
    border: Palette.border,
    sage: Palette.sage,
    peach: Palette.peach,
    scoreText: Color(0xFF4C663B),
    lowScoreText: Color(0xFFA06D34),
  );

  static const dark = PocketColors(
    muted: Palette.mutedDark,
    mutedForeground: Palette.mutedForegroundDark,
    border: Palette.borderDark,
    sage: Palette.sageDark,
    peach: Palette.peachDark,
    scoreText: Color(0xFFC5D9AF),
    lowScoreText: Color(0xFFE0B27E),
  );

  @override
  PocketColors copyWith({
    Color? muted,
    Color? mutedForeground,
    Color? border,
    Color? sage,
    Color? peach,
    Color? scoreText,
    Color? lowScoreText,
  }) {
    return PocketColors(
      muted: muted ?? this.muted,
      mutedForeground: mutedForeground ?? this.mutedForeground,
      border: border ?? this.border,
      sage: sage ?? this.sage,
      peach: peach ?? this.peach,
      scoreText: scoreText ?? this.scoreText,
      lowScoreText: lowScoreText ?? this.lowScoreText,
    );
  }

  @override
  PocketColors lerp(ThemeExtension<PocketColors>? other, double t) {
    if (other is! PocketColors) return this;
    return PocketColors(
      muted: Color.lerp(muted, other.muted, t)!,
      mutedForeground: Color.lerp(mutedForeground, other.mutedForeground, t)!,
      border: Color.lerp(border, other.border, t)!,
      sage: Color.lerp(sage, other.sage, t)!,
      peach: Color.lerp(peach, other.peach, t)!,
      scoreText: Color.lerp(scoreText, other.scoreText, t)!,
      lowScoreText: Color.lerp(lowScoreText, other.lowScoreText, t)!,
    );
  }
}

extension PocketTheme on BuildContext {
  PocketColors get pocket => Theme.of(this).extension<PocketColors>() ?? PocketColors.light;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}
