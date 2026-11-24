import 'package:flutter/material.dart';

/// Palette from the Figma "ToBeIT70" style frame (values read off the
/// exported image, so adjust if the file's exact hex differs).
abstract final class AppColors {
  static const base = Color(0xFFF3F5F4);
  static const primary = Color(0xFF0A3A8C);
  static const secondary = Color(0xFF1ADBC1);
  static const accent = Color(0xFFFF7F3F);

  /// Fill for inputs and option tiles.
  static const field = Color(0xFFE0E7E8);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.primary).copyWith(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    secondary: AppColors.secondary,
    onSecondary: AppColors.primary,
    tertiary: AppColors.accent,
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
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
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
      hintStyle: TextStyle(color: AppColors.primary.withValues(alpha: 0.55)),
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
      selectedColor: AppColors.accent,
      selectedTileColor: Colors.transparent,
    ),
  );
}
