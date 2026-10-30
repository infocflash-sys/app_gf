import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Paleta institucional Grupo Flash: azul marino y negro.
class Brand {
  static const navy = Color(0xFF0A1F44);
  static const navyDeep = Color(0xFF061331);
  static const navySoft = Color(0xFF16306B);
  static const black = Color(0xFF000000);
  static const ink = Color(0xFF05070D);
  static const accent = Color(0xFF4C8DFF); // azul vivo para contraste sobre negro
  static const flash = Color(0xFFFFC53D); // destello puntual (rayo / alertas)
}

class StatusColors {
  static const entregado = Color(0xFF22A06B);
  static const novedad = Color(0xFFE5484D);

  // Regla de negocio: estado definitivo = azul; cualquier otro = verde (en gestión).
  static const definitivoLight = Color(0xFF2A62E8);
  static const definitivoDark = Color(0xFF6BA3FF);
  static const gestionLight = Color(0xFF1B9A5F);
  static const gestionDark = Color(0xFF3FD091);

  static Color of(BuildContext context, {required bool definitivo}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return definitivo
        ? (dark ? definitivoDark : definitivoLight)
        : (dark ? gestionDark : gestionLight);
  }
}

class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final dark = b == Brightness.dark;
    final primary = dark ? Brand.accent : Brand.navy;
    final scheme = ColorScheme.fromSeed(
      seedColor: Brand.navy,
      brightness: b,
    ).copyWith(
      primary: primary,
      onPrimary: dark ? Brand.black : Colors.white,
      secondary: Brand.accent,
      surface: dark ? const Color(0xFF0B0F1A) : Colors.white,
      onSurface: dark ? const Color(0xFFE8ECF5) : const Color(0xFF0B1220),
      surfaceContainerHighest:
          dark ? const Color(0xFF141B2D) : const Color(0xFFEDF1F8),
      outlineVariant: dark ? const Color(0xFF222B42) : const Color(0xFFDCE3F0),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? Brand.ink : const Color(0xFFF4F6FB),
    );

    final text = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    return base.copyWith(
      textTheme: text.copyWith(
        headlineMedium: text.headlineMedium
            ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        titleLarge: text.titleLarge
            ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: scheme.onSurface,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primary, width: 1.6),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: primary.withValues(alpha: 0.16),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      }),
    );
  }
}
