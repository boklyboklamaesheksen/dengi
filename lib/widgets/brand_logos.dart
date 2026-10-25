import 'package:flutter/material.dart';

/// Official brand marks drawn from their published SVG path data, so they
/// stay crisp at any size without image assets or an SVG package.

/// Parses SVG path data (M L H V C S Q T A Z, absolute and relative).
Path parseSvgPath(String data) {
  final path = Path();
  final tokens = RegExp(
    r'[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?',
  ).allMatches(data).map((m) => m.group(0)!).toList();
  bool isCommand(String token) => RegExp(r'^[A-Za-z]$').hasMatch(token);

  var i = 0;
  var command = 'M';
  var current = Offset.zero;
  var start = Offset.zero;
  Offset? cubicControl;
  Offset? quadControl;
  double next() => double.parse(tokens[i++]);

  try {
    while (i < tokens.length) {
      if (isCommand(tokens[i])) command = tokens[i++];
      final relative = command == command.toLowerCase();
      Offset point(double x, double y) =>
          relative ? current + Offset(x, y) : Offset(x, y);
      switch (command.toUpperCase()) {
        case 'M':
          current = point(next(), next());
          start = current;
          path.moveTo(current.dx, current.dy);
          // Further pairs after a moveto are implicit linetos.
          command = relative ? 'l' : 'L';
          cubicControl = quadControl = null;
        case 'L':
          current = point(next(), next());
          path.lineTo(current.dx, current.dy);
          cubicControl = quadControl = null;
        case 'H':
          final x = next();
          current = Offset(relative ? current.dx + x : x, current.dy);
          path.lineTo(current.dx, current.dy);
          cubicControl = quadControl = null;
        case 'V':
          final y = next();
          current = Offset(current.dx, relative ? current.dy + y : y);
          path.lineTo(current.dx, current.dy);
          cubicControl = quadControl = null;
        case 'C':
          final c1 = point(next(), next());
          final c2 = point(next(), next());
          final end = point(next(), next());
          path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
          cubicControl = c2;
          quadControl = null;
          current = end;
        case 'S':
          final c1 = cubicControl == null
              ? current
              : current * 2 - cubicControl;
          final c2 = point(next(), next());
          final end = point(next(), next());
          path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
          cubicControl = c2;
          quadControl = null;
          current = end;
        case 'Q':
          final control = point(next(), next());
          final end = point(next(), next());
          path.quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
          quadControl = control;
          cubicControl = null;
          current = end;
        case 'T':
          final control = quadControl == null
              ? current
              : current * 2 - quadControl;
          final end = point(next(), next());
          path.quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
          quadControl = control;
          cubicControl = null;
          current = end;
        case 'A':
          final rx = next();
          final ry = next();
          final rotation = next();
          final largeArc = next() != 0;
          final sweep = next() != 0;
          final end = point(next(), next());
          path.arcToPoint(
            end,
            radius: Radius.elliptical(rx, ry),
            rotation: rotation,
            largeArc: largeArc,
            clockwise: sweep,
          );
          cubicControl = quadControl = null;
          current = end;
        case 'Z':
          path.close();
          current = start;
          cubicControl = quadControl = null;
          // Numbers right after a closepath are malformed; skip them.
          while (i < tokens.length && !isCommand(tokens[i])) {
            i++;
          }
      }
    }
  } on RangeError {
    // Truncated data: keep what was parsed.
  }
  return path;
}

/// Telegram logo (telegram.org website icon, 16×16 grid).
class TelegramLogo extends StatelessWidget {
  const TelegramLogo({super.key, this.size = 44});

  final double size;

  static const Color blue = Color(0xFF2AABEE);
  static const Color blueDeep = Color(0xFF229ED9);

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: _TelegramPainter()),
    );
  }
}

class _TelegramPainter extends CustomPainter {
  const _TelegramPainter();

  static final Path _plane = parseSvgPath(
    'M3.17026167,7.83635602 C5.78750201,6.74265999 7.53273882,6.02162863 '
    '8.40597211,5.67326193 C10.8992306,4.67860423 11.2454541,4.53439191 '
    '11.5831299,4.52864956 C11.6573986,4.52743168 11.8385417,4.55776042 '
    '11.9798438,4.67645833 C12.1211458,4.79515625 12.1635786,4.87206678 '
    '12.1755371,4.93908691 C12.1874957,5.00610705 12.1862759,5.21456762 '
    '12.1744385,5.3338623 C12.0393279,6.69547283 11.5259342,9.83829771 '
    '11.2285121,11.3633248 C11.1026617,12.008621 10.8548582,12.2249854 '
    '10.6149558,12.2461596 C10.0935924,12.2921758 9.69769267,11.9156852 '
    '9.19272668,11.5981993 C8.40255458,11.1013965 8.13911734,10.9180161 '
    '7.3721185,10.4332283 C6.48571864,9.87297217 6.85080034,9.6784879 '
    '7.35595703,9.17524981 C7.48815894,9.04355001 9.67825076,7.04590073 '
    '9.71077046,6.86250183 C9.7391276,6.70257812 9.7494847,6.68189389 '
    '9.67664063,6.60973958 C9.60379655,6.53758527 9.51674192,6.54658941 '
    '9.46083149,6.55876051 C9.38158015,6.57601267 8.17521836,7.33962686 '
    '5.84174612,8.84960308 C5.48344358,9.08558775 5.15890428,9.20056741 '
    '4.86812819,9.19454205 C4.54757089,9.18789957 3.93094724,9.02070014 '
    '3.47255094,8.87778221 C2.91030922,8.70248755 2.46345069,8.609808 '
    '2.50236203,8.31210343 C2.52262946,8.15704047 2.74526267,7.998458 '
    '3.17026167,7.83635602 Z',
  );

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 16, size.height / 16);
    const circle = Rect.fromLTWH(0, 0, 16, 16);
    canvas.drawOval(
      circle,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF38AEEB), Color(0xFF279AD1)],
        ).createShader(circle),
    );
    canvas.drawPath(_plane, Paint()..color = Colors.white);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Bare Telegram paper plane, for buttons on a blue fill.
class TelegramPlane extends StatelessWidget {
  const TelegramPlane({super.key, this.size = 18, this.color = Colors.white});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _PlanePainter(color)),
    );
  }
}

class _PlanePainter extends CustomPainter {
  const _PlanePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // The plane spans x 2.5–12.2, y 4.5–12.3 of the 16-unit logo grid.
    final scale = size.width / 10.6;
    canvas.save();
    canvas.scale(scale);
    canvas.translate(-2.05, -3.11);
    canvas.drawPath(_TelegramPainter._plane, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PlanePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Google Play triangle in the 2022 brand colours.
class GooglePlayLogo extends StatelessWidget {
  const GooglePlayLogo({super.key, this.size = 26});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 120.9 / 129.2,
      height: size,
      child: const CustomPaint(painter: _GooglePlayPainter()),
    );
  }
}

class _GooglePlayPainter extends CustomPainter {
  const _GooglePlayPainter();

  static final List<(Path, Color)> _parts = <(Path, Color)>[
    (
      parseSvgPath(
        'M119.2,421.2c15.3-8.4,27-14.8,28-15.3c3.2-1.7,6.5-6.2,0-9.7'
        'c-2.1-1.1-13.4-7.3-28-15.3l-20.1,20.2L119.2,421.2z',
      ),
      const Color(0xFFFBBC04),
    ),
    (
      parseSvgPath(
        'M99.1,401.1l-64.2,64.7c1.5,0.2,3.2-0.2,5.2-1.3'
        'c4.2-2.3,48.8-26.7,79.1-43.3L99.1,401.1L99.1,401.1z',
      ),
      const Color(0xFFEA4335),
    ),
    (
      parseSvgPath(
        'M99.1,401.1l20.1-20.2c0,0-74.6-40.7-79.1-43.1'
        'c-1.7-1-3.6-1.3-5.3-1L99.1,401.1z',
      ),
      const Color(0xFF34A853),
    ),
    (
      parseSvgPath(
        'M99.1,401.1l-64.3-64.3c-2.6,0.6-4.8,2.9-4.8,7.6'
        'c0,7.5,0,107.5,0,113.8c0,4.3,1.7,7.4,4.9,7.7L99.1,401.1z',
      ),
      const Color(0xFF4285F4),
    ),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 120.9, size.height / 129.2);
    canvas.translate(-30, -336.7);
    for (final (path, color) in _parts) {
      canvas.drawPath(path, Paint()..color = color);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Envelope mark for the e-mail channel: white letter on a violet tile.
class MailMark extends StatelessWidget {
  const MailMark({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: _MailPainter()),
    );
  }
}

class _MailPainter extends CustomPainter {
  const _MailPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final tile = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(s * 0.3),
    );
    canvas.drawRRect(
      tile,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF8E7BFF), Color(0xFF5B5BF0)],
        ).createShader(Offset.zero & size),
    );
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * 0.2, s * 0.29, s * 0.6, s * 0.43),
      Radius.circular(s * 0.07),
    );
    canvas.drawRRect(body, Paint()..color = Colors.white);
    final flap = Path()
      ..moveTo(s * 0.24, s * 0.34)
      ..lineTo(s * 0.5, s * 0.53)
      ..lineTo(s * 0.76, s * 0.34);
    canvas.drawPath(
      flap,
      Paint()
        ..color = const Color(0xFF6A63F4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.055
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
