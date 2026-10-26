import 'package:flutter/material.dart';

/// Color base de Mornye (se usa si el telefono no da colores dinamicos).
const kSeedColor = Color(0xFF1DB954);

ThemeData buildTheme(ColorScheme? dynamicDark, String? fontFamily) {
  final base =
      dynamicDark ??
      ColorScheme.fromSeed(seedColor: kSeedColor, brightness: Brightness.dark);
  final scheme = base.copyWith(surface: Colors.black);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.black,
    fontFamily: fontFamily,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.black,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: true,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
