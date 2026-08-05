import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFF00E5FF); // Cyan / Celeste brillante
  static const Color accent = Color(0xFFD500F9); // Magenta / Morado neón
  static const Color background = Color(0xFF121212); // Fondo oscuro
  
  // Opcional: Un gradiente que combina ambos si lo necesitas en el futuro
  static const LinearGradient neonGradient = LinearGradient(
    colors: [primary, accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
