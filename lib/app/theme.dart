import 'package:flutter/material.dart';

ThemeData buildAppTheme() {
  const ink = Color(0xFF111D49);
  const violet = Color(0xFF5D36E8);

  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: violet,
      brightness: Brightness.light,
      primary: violet,
      surface: const Color(0xFFF6F7FC),
    ),
    scaffoldBackgroundColor: const Color(0xFFF6F7FC),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        color: ink,
        fontSize: 34,
        height: 1.05,
        fontWeight: FontWeight.w800,
      ),
      headlineMedium: TextStyle(
        color: ink,
        fontSize: 26,
        fontWeight: FontWeight.w800,
      ),
      titleLarge: TextStyle(color: ink, fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(color: ink),
      bodyMedium: TextStyle(color: Color(0xFF52607B)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.84),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.8)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
    ),
  );
}
