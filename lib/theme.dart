import 'package:flutter/material.dart';

/// Color base (se usa si el telefono no da colores dinamicos).
const kSeedColor = Color(0xFF1DB954);

/// [accent]: 0 = colores del telefono; otro valor = color elegido (ARGB).
/// [glass]: superficies translucidas. [aurora]: fondo con degradado, por lo
/// que los Scaffold pasan a ser transparentes.
ThemeData buildTheme(
  ColorScheme? dynamicDark,
  String? fontFamily, {
  int accent = 0,
  bool glass = true,
  bool aurora = true,
}) {
  final base = accent != 0
      ? ColorScheme.fromSeed(
          seedColor: Color(accent),
          brightness: Brightness.dark,
        )
      : (dynamicDark ??
            ColorScheme.fromSeed(
              seedColor: kSeedColor,
              brightness: Brightness.dark,
            ));
  var scheme = base.copyWith(surface: Colors.black);
  if (glass) {
    scheme = scheme.copyWith(
      surfaceContainer: Colors.white.withValues(alpha: 0.08),
    );
  }
  final bg = aurora ? Colors.transparent : Colors.black;
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    fontFamily: fontFamily,
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: true,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: const Color(0xF21C1C1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
