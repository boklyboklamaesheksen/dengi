import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// Hand-drawn duotone glyphs for the PRO screen: one family (24-unit grid,
/// rounded gradient strokes) instead of stock Material icons.
enum FeatureGlyph {
  unblock,
  speed,
  anonymous,
  hd,
  noLogs,
  noAds,
  instant,
  secure,
}

extension FeatureGlyphColors on FeatureGlyph {
  /// Light → deep tone of the glyph's gradient.
  (Color, Color) get tones => switch (this) {
    FeatureGlyph.unblock => (const Color(0xFF7DD3FC), const Color(0xFF3B82F6)),
    FeatureGlyph.speed => (const Color(0xFFFDE68A), const Color(0xFFF5B50B)),
    FeatureGlyph.anonymous => (
      const Color(0xFFD8B4FE),
      const Color(0xFF8B5CF6),
    ),
    FeatureGlyph.hd => (const Color(0xFFFDA4AF), const Color(0xFFF43F5E)),
    FeatureGlyph.noLogs => (const Color(0xFF86EFAC), const Color(0xFF22C55E)),
    FeatureGlyph.noAds => (const Color(0xFFA5B4FC), const Color(0xFF6366F1)),
    FeatureGlyph.instant => (const Color(0xFF67E8F9), const Color(0xFF06B6D4)),
    FeatureGlyph.secure => (const Color(0xFF86EFAC), const Color(0xFF22C55E)),
  };
}

/// Glyph on a softly tinted glass tile with a matching glow.
class FeatureGlyphTile extends StatelessWidget {
  const FeatureGlyphTile({super.key, required this.glyph, this.size = 40});

  final FeatureGlyph glyph;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (light, deep) = glyph.tones;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            deep.withValues(alpha: 0.24),
            deep.withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(color: light.withValues(alpha: 0.28)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: deep.withValues(alpha: 0.22),
            blurRadius: 16,
            spreadRadius: -4,
          ),
        ],
      ),
      child: Center(
        child: SizedBox.square(
          dimension: size * 0.6,
          child: CustomPaint(painter: FeatureGlyphPainter(glyph)),
        ),
      ),
    );
  }
}

class FeatureGlyphPainter extends CustomPainter {
  const FeatureGlyphPainter(this.glyph);

  final FeatureGlyph glyph;

  @override
  void paint(Canvas canvas, Size size) {
    final (light, deep) = glyph.tones;
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[light, deep],
    ).createShader(const Rect.fromLTWH(0, 0, 24, 24));
    final stroke = Paint()
      ..shader = gradient
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..shader = gradient
      ..style = PaintingStyle.fill;

    switch (glyph) {
      case FeatureGlyph.unblock:
        _globe(canvas, stroke);
      case FeatureGlyph.speed:
        _bolt(canvas, fill, stroke);
      case FeatureGlyph.anonymous:
        _incognito(canvas, stroke, fill);
      case FeatureGlyph.hd:
        _screen(canvas, stroke, fill);
      case FeatureGlyph.noLogs:
        _shieldCheck(canvas, stroke);
      case FeatureGlyph.noAds:
        _noAds(canvas, stroke, light);
      case FeatureGlyph.instant:
        _power(canvas, stroke);
      case FeatureGlyph.secure:
        _lock(canvas, stroke, fill);
    }
    canvas.restore();
  }

  void _globe(Canvas canvas, Paint stroke) {
    const c = Offset(12, 12);
    canvas.drawCircle(c, 8.4, stroke);
    canvas.drawOval(
      Rect.fromCenter(center: c, width: 7.4, height: 16.8),
      stroke,
    );
    canvas.drawLine(const Offset(3.6, 12), const Offset(20.4, 12), stroke);
    final halfChord = math.sqrt(8.4 * 8.4 - 4.2 * 4.2);
    for (final y in <double>[7.8, 16.2]) {
      canvas.drawLine(
        Offset(12 - halfChord, y),
        Offset(12 + halfChord, y),
        stroke..strokeWidth = 1.5,
      );
    }
    stroke.strokeWidth = 1.9;
  }

  void _bolt(Canvas canvas, Paint fill, Paint stroke) {
    final bolt = Path()
      ..moveTo(13.8, 2.6)
      ..lineTo(5.4, 13.4)
      ..lineTo(11.3, 13.4)
      ..lineTo(10.2, 21.4)
      ..lineTo(18.6, 10.4)
      ..lineTo(12.7, 10.4)
      ..close();
    canvas.drawPath(bolt, fill);
    canvas.drawPath(bolt, stroke..strokeWidth = 1.2);
    stroke.strokeWidth = 1.9;
  }

  void _incognito(Canvas canvas, Paint stroke, Paint fill) {
    final crown = Path()
      ..moveTo(6.2, 10.6)
      ..lineTo(7.7, 5.2)
      ..quadraticBezierTo(8.1, 4.2, 9.2, 4.7)
      ..lineTo(12, 5.8)
      ..lineTo(14.8, 4.7)
      ..quadraticBezierTo(15.9, 4.2, 16.3, 5.2)
      ..lineTo(17.8, 10.6)
      ..close();
    canvas.drawPath(crown, fill);
    canvas.drawLine(const Offset(3.2, 10.8), const Offset(20.8, 10.8), stroke);
    canvas.drawCircle(const Offset(8, 16.4), 2.9, stroke);
    canvas.drawCircle(const Offset(16, 16.4), 2.9, stroke);
    final bridge = Path()
      ..moveTo(10.9, 16.1)
      ..quadraticBezierTo(12, 15.1, 13.1, 16.1);
    canvas.drawPath(bridge, stroke);
  }

  void _screen(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawRRect(
      RRect.fromLTRBR(3, 5.2, 21, 18.8, const Radius.circular(3.4)),
      stroke,
    );
    final play = Path()
      ..moveTo(10.2, 9)
      ..lineTo(15.4, 12)
      ..lineTo(10.2, 15)
      ..close();
    canvas.drawPath(play, fill);
    canvas.drawPath(play, stroke..strokeWidth = 1.1);
    stroke.strokeWidth = 1.9;
  }

  void _shieldCheck(Canvas canvas, Paint stroke) {
    final shield = Path()
      ..moveTo(12, 2.8)
      ..cubicTo(14.7, 4.5, 17.4, 5.2, 19.8, 5.4)
      ..lineTo(19.8, 11.4)
      ..cubicTo(19.8, 16.2, 16.6, 19.6, 12, 21.2)
      ..cubicTo(7.4, 19.6, 4.2, 16.2, 4.2, 11.4)
      ..lineTo(4.2, 5.4)
      ..cubicTo(6.6, 5.2, 9.3, 4.5, 12, 2.8)
      ..close();
    canvas.drawPath(shield, stroke);
    final check = Path()
      ..moveTo(8.5, 12.1)
      ..lineTo(11, 14.6)
      ..lineTo(15.7, 9.7);
    canvas.drawPath(check, stroke);
  }

  void _noAds(Canvas canvas, Paint stroke, Color light) {
    // Prohibition sign over "AD".
    const c = Offset(12, 12);
    final label = TextPainter(
      text: TextSpan(
        text: 'AD',
        style: TextStyle(
          color: light,
          fontFamily: AppFonts.display,
          fontSize: 8.6,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, c - Offset(label.width / 2, label.height / 2));
    canvas.drawCircle(c, 9, stroke);
    const a = Offset(5.6, 5.6);
    const b = Offset(18.4, 18.4);
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = const Color(0xFF14152A)
        ..strokeWidth = 3.6
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(a, b, stroke);
  }

  void _power(Canvas canvas, Paint stroke) {
    const c = Offset(12, 13);
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: 7.6),
      -math.pi / 2 + 0.62,
      2 * math.pi - 1.24,
      false,
      stroke,
    );
    canvas.drawLine(const Offset(12, 3.6), const Offset(12, 11.6), stroke);
  }

  void _lock(Canvas canvas, Paint stroke, Paint fill) {
    canvas.drawRRect(
      RRect.fromLTRBR(5.2, 10.4, 18.8, 20.6, const Radius.circular(2.8)),
      stroke,
    );
    final shackle = Path()
      ..moveTo(8.4, 10.4)
      ..lineTo(8.4, 7.6)
      ..arcToPoint(const Offset(15.6, 7.6), radius: const Radius.circular(3.6))
      ..lineTo(15.6, 10.4);
    canvas.drawPath(shackle, stroke);
    canvas.drawCircle(const Offset(12, 14.6), 1.35, fill);
    canvas.drawLine(const Offset(12, 15.4), const Offset(12, 17.4), stroke);
  }

  @override
  bool shouldRepaint(covariant FeatureGlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph;
}

/// Faceted brilliant of the PRO hero: icy blue facets, white light and a few
/// spectral flashes, the way a real cut diamond sparkles.
class PremiumEmblem extends StatelessWidget {
  const PremiumEmblem({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: _GemPainter()),
    );
  }
}

class _GemPainter extends CustomPainter {
  const _GemPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);
    const bounds = Rect.fromLTWH(0, 0, 64, 64);

    // Blue glow the stone throws on the dark backdrop.
    canvas.drawCircle(
      const Offset(32, 33),
      30,
      Paint()
        ..shader = const RadialGradient(
          colors: <Color>[Color(0x4D38BDF8), Color(0x0038BDF8)],
        ).createShader(bounds),
    );

    const top = 18.0, girdle = 27.0, bottom = 52.0;
    const left = 10.0, right = 54.0, inL = 20.0, inR = 44.0;
    Path poly(List<Offset> points) => Path()..addPolygon(points, true);
    Paint facet(Color a, Color b) => Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[a, b],
      ).createShader(bounds);

    // Crown facets: the table catches the light, the far side turns away.
    canvas.drawPath(
      poly(const [Offset(inL, top), Offset(left, girdle), Offset(24, girdle)]),
      facet(const Color(0xFFC4F3FF), const Color(0xFF4CC3F5)),
    );
    canvas.drawPath(
      poly(const [Offset(inL, top), Offset(32, top), Offset(24, girdle)]),
      facet(const Color(0xFFFFFFFF), const Color(0xFFBDEFFF)),
    );
    canvas.drawPath(
      poly(const [Offset(32, top), Offset(40, girdle), Offset(24, girdle)]),
      facet(const Color(0xFFEAFBFF), const Color(0xFF7FD8FA)),
    );
    canvas.drawPath(
      poly(const [Offset(32, top), Offset(inR, top), Offset(40, girdle)]),
      facet(const Color(0xFFFFFFFF), const Color(0xFFCDF4FF)),
    );
    canvas.drawPath(
      poly(const [Offset(inR, top), Offset(right, girdle), Offset(40, girdle)]),
      facet(const Color(0xFF8FDFFB), const Color(0xFF1F96E6)),
    );
    // Pavilion facets.
    canvas.drawPath(
      poly(const [
        Offset(left, girdle),
        Offset(24, girdle),
        Offset(32, bottom),
      ]),
      facet(const Color(0xFF6FD0F8), const Color(0xFF1668CF)),
    );
    canvas.drawPath(
      poly(const [Offset(24, girdle), Offset(40, girdle), Offset(32, bottom)]),
      facet(const Color(0xFFD2F6FF), const Color(0xFF3AAEEE)),
    );
    canvas.drawPath(
      poly(const [
        Offset(40, girdle),
        Offset(right, girdle),
        Offset(32, bottom),
      ]),
      facet(const Color(0xFF2B98E8), const Color(0xFF0B47A8)),
    );

    // Fire: the spectral flashes a cut diamond throws besides white light.
    const fire = <(List<Offset>, Color)>[
      (
        [Offset(13, girdle), Offset(21, girdle), Offset(18.5, 30.5)],
        Color(0x99FF7AD9),
      ),
      ([Offset(30.2, 44), Offset(33.8, 44), Offset(32, 50)], Color(0x99FFD86B)),
      ([Offset(45, 22), Offset(50, 26), Offset(43.5, 26)], Color(0x8C7CFFD4)),
    ];
    for (final (points, color) in fire) {
      canvas.drawPath(poly(points), Paint()..color = color);
    }

    // Facet edges.
    final edge = Paint()
      ..color = const Color(0x59FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..strokeCap = StrokeCap.round;
    const edges = <(Offset, Offset)>[
      (Offset(left, girdle), Offset(right, girdle)),
      (Offset(inL, top), Offset(24, girdle)),
      (Offset(32, top), Offset(24, girdle)),
      (Offset(32, top), Offset(40, girdle)),
      (Offset(inR, top), Offset(40, girdle)),
      (Offset(24, girdle), Offset(32, bottom)),
      (Offset(40, girdle), Offset(32, bottom)),
    ];
    for (final (a, b) in edges) {
      canvas.drawLine(a, b, edge);
    }

    // Outline light.
    final outline = poly(const [
      Offset(inL, top),
      Offset(inR, top),
      Offset(right, girdle),
      Offset(32, bottom),
      Offset(left, girdle),
    ]);
    canvas.drawPath(
      outline,
      Paint()
        ..color = const Color(0xE6F0FCFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..strokeJoin = StrokeJoin.round,
    );
    // Sparkles.
    _sparkle(canvas, const Offset(47, 12), 5, Colors.white);
    _sparkle(canvas, const Offset(12.5, 45), 2.6, const Color(0xE6D9F6FF));
    canvas.restore();
  }

  /// Four-pointed glint of radius [r] around [c].
  static void _sparkle(Canvas canvas, Offset c, double r, Color color) {
    final k = r * 0.16;
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy - r)
        ..quadraticBezierTo(c.dx + k, c.dy - k, c.dx + r, c.dy)
        ..quadraticBezierTo(c.dx + k, c.dy + k, c.dx, c.dy + r)
        ..quadraticBezierTo(c.dx - k, c.dy + k, c.dx - r, c.dy)
        ..quadraticBezierTo(c.dx - k, c.dy - k, c.dx, c.dy - r)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
