// Estilo "liquid glass": fondo con degradado de color, tarjetas translucidas
// con desenfoque y borde de luz. Todo se puede apagar en Ajustes.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Colores de acento para elegir en Ajustes (0 = colores del telefono).
const kAccentChoices = <int>[
  0xFF1DB954,
  0xFF7C4DFF,
  0xFF2979FF,
  0xFF00BCD4,
  0xFFFF4081,
  0xFFFF9100,
  0xFFFF5252,
];

/// Indica a los widgets si el efecto vidrio esta activo.
class GlassScope extends InheritedWidget {
  const GlassScope({super.key, required this.enabled, required super.child});

  final bool enabled;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassScope>()?.enabled ??
      false;

  @override
  bool updateShouldNotify(GlassScope old) => enabled != old.enabled;
}

/// Fondo oscuro con tres manchas de color suaves (usa los colores del tema).
/// Es estatico: no cuesta nada de rendimiento.
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget blob(Color c, double size, double alpha) => SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [c.withValues(alpha: alpha), c.withValues(alpha: 0)],
          ),
        ),
      ),
    );
    return RepaintBoundary(
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(top: -140, left: -120, child: blob(cs.primary, 480, .42)),
            Positioned(
              top: 260,
              right: -220,
              child: blob(cs.secondary, 460, .22),
            ),
            Positioned(
              bottom: -180,
              left: -80,
              child: blob(cs.tertiary, 520, .32),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reemplazo de [Card]: con vidrio activo desenfoca lo que hay detras y
/// agrega un borde de luz fino. Con vidrio apagado es una Card normal.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    this.elevation,
    this.margin,
    this.color,
    this.shape,
    this.clipBehavior,
    required this.child,
  });

  final double? elevation;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final ShapeBorder? shape;
  final Clip? clipBehavior;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final enabled = GlassScope.of(context);
    var shape =
        this.shape ?? RoundedRectangleBorder(borderRadius: BorderRadius.circular(20));
    if (enabled && shape is RoundedRectangleBorder && shape.side == BorderSide.none) {
      shape = shape.copyWith(
        side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
      );
    }
    final card = Card(
      elevation: 0,
      margin: margin,
      color: color,
      shape: shape,
      clipBehavior: clipBehavior ?? Clip.none,
      child: child,
    );
    if (!enabled) return card;
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: card,
      ),
    );
  }
}
