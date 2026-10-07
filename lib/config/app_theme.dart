import 'package:flutter/material.dart';

/// Zapret VPN colour system — "Stark Mono".
///
/// Dark-first, monochrome palette modelled on the xAI design language:
/// an almost-black canvas (#1F2228) with pure white as the single accent,
/// borders made of low-opacity white, and no decorative gradients or
/// colour noise. Functional colours (error / warning / success) stay
/// outside the monochrome ramp so status stays readable at a glance.
class AppColors {
  AppColors._();

  // ───── Surfaces ──────────────────────────────────────────────────────
  /// Scaffold background — true full-dark canvas (OLED black).
  static const Color base = Color(0xFF07080A);

  /// Primary elevated surface (cards, tiles) — a hair above the canvas.
  static const Color surface = Color(0xFF101216);

  /// Second-tier elevation — inputs, nested cards, modal sheets.
  static const Color surfaceElevated = Color(0xFF171A1F);

  /// Uniform hairline — white at 10% opacity (xAI border default).
  static const Color border = Color(0x1AFFFFFF);

  /// Brighter border reserved for selected / focused states — white 20%.
  static const Color borderStrong = Color(0x33FFFFFF);

  // ───── Brand accents (monochrome ramp) ───────────────────────────────
  /// Primary accent — pure white. The voice of the whole interface.
  static const Color emerald = Color(0xFFFFFFFF);

  /// Bright silver of the monochrome ramp (secondary strokes, icons).
  static const Color teal = Color(0xFFD2D6DC);

  /// Slate mid tone — charts, secondary strokes.
  static const Color cyan = Color(0xFF8B919B);

  /// Deep slate — quiet end of the ramp.
  static const Color sky = Color(0xFF565C66);

  /// Pressed / dimmed variant of the white accent.
  static const Color emeraldDeep = Color(0xFFD6D9DD);

  /// Soft white tint for account/security features.
  static const Color violet = Color(0xFFE6E9ED);

  // ───── Functional (kept outside the mono ramp) ───────────────────────
  static const Color success = Color(0xFF3ECF8E);
  static const Color error = Color(0xFFFF5D7A);
  static const Color warning = Color(0xFFFFB020);

  // ───── Typography ────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xB3FFFFFF); // 70% white
  static const Color textMuted = Color(0x80FFFFFF); // 50% white

  // ───── Gradients ─────────────────────────────────────────────────────
  /// Primary brand gradient — white → silver → slate. Reads as a beam of
  /// light fading into the dark canvas instead of a colour gradient.
  static const LinearGradient signal = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [emerald, teal, cyan, sky],
    stops: [0.0, 0.38, 0.72, 1.0],
  );

  /// Soft variant for behind-card washes — 18 % alpha with the calmer tones.
  static const LinearGradient signalSoft = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0x2EFFFFFF),
      Color(0x2EC9CDD4),
      Color(0x2E9BA1A9),
      Color(0x2E5C626B),
    ],
    stops: [0.0, 0.38, 0.72, 1.0],
  );

  /// Glass sheen gradient (top-left highlight fading to bottom-right
  /// transparency).
  static const LinearGradient sheen = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0x1FFFFFFF),
      Color(0x06FFFFFF),
    ],
  );

  /// Radial wash used behind the "connected" state — very subtle.
  static const RadialGradient connectedHalo = RadialGradient(
    center: Alignment.center,
    radius: 0.9,
    colors: [
      Color(0x28FFFFFF),
      Color(0x00FFFFFF),
    ],
    stops: [0.0, 1.0],
  );
}

/// Shared corner radii — one source of truth for the app's squircle feel.
class AppRadii {
  AppRadii._();
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
  static const BorderRadius chunk = BorderRadius.all(Radius.circular(28));
  static const BorderRadius card = BorderRadius.all(Radius.circular(22));
  static const BorderRadius tile = BorderRadius.all(Radius.circular(16));
  static const BorderRadius tight = BorderRadius.all(Radius.circular(12));
}

/// Typography voices: two bundled families for the whole app.
///
/// Both faces ship with the binary under `assets/fonts/`, so rendering never
/// depends on the fonts installed on the user's phone. [brand] is the Lenta
/// wordmark face — a single Regular (400) cut reserved for the logo text
/// only (splash, home header, welcome): do not ask for `FontWeight.bold`
/// on top of it, the glyphs are already dense and the closest-match picker
/// must never be pushed past 400. Everything else — buttons, statuses,
/// timers, body copy — speaks [display]/[body], the bundled Inter in
/// weights 300–900.
class AppFonts {
  AppFonts._();

  /// Brand wordmark voice — bundled Lenta Regular, logo text only.
  static const String brand = 'Lenta';

  /// Display / button voice — bundled Inter.
  static const String display = 'Inter';

  /// Only consulted for glyphs the bundled faces do not cover (emoji and
  /// the like); ordinary text never leaves the bundled families.
  static const List<String> displayFallback = <String>['monospace'];

  /// Reading voice — the same bundled Inter, so body copy and headlines
  /// share one look regardless of the platform default sans.
  static const String body = 'Inter';
}

/// Material theme for Zapret VPN. Dark-only by design.
class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme {
    const base = AppColors.base;
    const surface = AppColors.surface;

    final colorScheme = const ColorScheme.dark(
      primary: AppColors.emerald,
      onPrimary: AppColors.base,
      secondary: AppColors.teal,
      onSecondary: AppColors.base,
      tertiary: AppColors.cyan,
      surface: surface,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.surfaceElevated,
      error: AppColors.error,
      onError: Colors.white,
      outline: AppColors.border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: base,
      canvasColor: base,
      // All press feedback is handled by PressScale widget — Material ripples
      // are switched off so the two systems don't fight.
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      fontFamily: AppFonts.body,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.card),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // xAI primary action: white surface, near-black label.
          backgroundColor: AppColors.emerald,
          foregroundColor: AppColors.base,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.tile),
          textStyle: const TextStyle(
            fontFamily: AppFonts.display,
            fontFamilyFallback: AppFonts.displayFallback,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.4,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.borderStrong),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.tile),
          textStyle: const TextStyle(
            fontFamily: AppFonts.display,
            fontFamilyFallback: AppFonts.displayFallback,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.4,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          textStyle: const TextStyle(
            fontFamily: AppFonts.display,
            fontFamilyFallback: AppFonts.displayFallback,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.2,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceElevated,
        border: OutlineInputBorder(
          borderRadius: AppRadii.tile,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.tile,
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.tile,
          borderSide:
              const BorderSide(color: AppColors.emerald, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadii.tile,
          borderSide: const BorderSide(color: AppColors.error),
        ),
        hintStyle: const TextStyle(color: AppColors.textMuted),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      textTheme: const TextTheme(
        // Display sizes carry the monospace voice — the xAI brand move.
        displayLarge: TextStyle(
          fontFamily: AppFonts.display,
          fontFamilyFallback: AppFonts.displayFallback,
          fontSize: 48,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
          letterSpacing: -1.0,
        ),
        displayMedium: TextStyle(
          fontFamily: AppFonts.display,
          fontFamilyFallback: AppFonts.displayFallback,
          fontSize: 36,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
          letterSpacing: -0.8,
        ),
        displaySmall: TextStyle(
          fontFamily: AppFonts.display,
          fontFamilyFallback: AppFonts.displayFallback,
          fontSize: 28,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
          letterSpacing: -0.4,
        ),
        headlineMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          color: AppColors.textPrimary,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: AppColors.textSecondary,
          height: 1.55,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          color: AppColors.textMuted,
          height: 1.5,
        ),
        labelLarge: TextStyle(
          fontFamily: AppFonts.display,
          fontFamilyFallback: AppFonts.displayFallback,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}
