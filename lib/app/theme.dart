import 'package:flutter/material.dart';

/// Palette from the Figma "ToBeIT70" style frame (values read off the
/// exported image, so adjust if the file's exact hex differs).
abstract final class AppColors {
  static const base = Color(0xFFF3F5F4);
  static const primary = Color(0xFF0A3A8C);
  static const secondary = Color(0xFF1ADBC1);

  /// Bright brand orange: fills and decoration only (white text on it is
  /// 2.5:1). Use [accentDeep] for bars that carry white text and for orange
  /// text.
  static const accent = Color(0xFFFF7F3F);

  /// Orange that passes 4.5:1 with white and on [base] (4.7:1).
  static const accentDeep = Color(0xFFC2410C);

  /// Placeholder / secondary text on [field] (5.7:1).
  static const hint = Color(0xFF46587F);

  /// Status colours on light surfaces (all >= 4.5:1 on [field]).
  static const success = Color(0xFF1B5E20);
  static const warning = Color(0xFF8A4B00);
  static const danger = Color(0xFFB71C1C);

  /// Status colours on the dark workout overlay.
  static const successOnDark = Color(0xFF69F0AE);
  static const warningOnDark = Color(0xFFFFB74D);
  static const dangerOnDark = Color(0xFFFF8A80);

  /// Fill for inputs and option tiles.
  static const field = Color(0xFFE0E7E8);
}

/// 4/8 px spacing scale.
abstract final class Gap {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 16.0;
  static const l = 24.0;
  static const xl = 32.0;
}

/// Icon sizes.
abstract final class IconSize {
  static const s = 20.0;
  static const m = 24.0;
  static const l = 32.0;
  static const xl = 40.0;
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.primary).copyWith(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    secondary: AppColors.secondary,
    onSecondary: AppColors.primary,
    tertiary: AppColors.accentDeep,
    surface: AppColors.base,
    onSurface: AppColors.primary,
    surfaceContainerHighest: AppColors.field,
  );

  const pill = StadiumBorder();
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.base,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.accentDeep,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.accentDeep,
      indicatorColor: Colors.white,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.accentDeep
              : Colors.white,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: pill,
        minimumSize: const Size(180, 46),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.field,
      hintStyle: const TextStyle(color: AppColors.hint),
      labelStyle: const TextStyle(color: AppColors.hint),
      floatingLabelStyle: const TextStyle(
        color: AppColors.primary,
        fontWeight: FontWeight.w700,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide.none,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.field,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    chipTheme: ChipThemeData(
      selectedColor: AppColors.secondary,
      backgroundColor: AppColors.field,
      side: BorderSide.none,
      shape: pill,
    ),
    listTileTheme: const ListTileThemeData(
      selectedColor: AppColors.accentDeep,
      selectedTileColor: Colors.transparent,
    ),
  );
}
