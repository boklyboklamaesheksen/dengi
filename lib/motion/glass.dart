import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'lite_mode.dart';

enum LiquidEdgeStyle { horizontal, diagonal }

/// Visual constants for Rabochiy's "liquid glass" language.
///
/// The system replaces the previous uniform white hairline with an
/// asymmetric highlight recipe that reads as a panel floating above the
/// background:
/// * a prominent top edge (the brightest line — simulating light hitting
///   the rounded top),
/// * a softer bottom edge (returning light, giving the element mass),
/// * barely-visible left / right sides (so the rectangle never looks like
///   a sticker cut out of white).
///
/// Interiors are intentionally darker than the canvas — the element looks
/// slightly inset yet lifted by the shadow below it.
class GlassPalette {
  GlassPalette._();

  /// Translucent tint painted on top of a [BackdropFilter].
  /// Kept near-black so the frosted element reads as "deeper" than the
  /// base, rather than washed out.
  static const Color sheet = Color(0x5C0C0E12);

  /// Slight interior gradient top-stop — a hint of brightness from the
  /// light overhead that produces the top highlight.
  static const Color interiorTop = Color(0xFF15181D);

  /// Interior gradient bottom-stop — noticeably darker than the top so
  /// the element feels 3-D even without the highlight.
  static const Color interiorBottom = Color(0xFF0C0E11);

  /// Interior tint used when a frosted surface is stacked over blur —
  /// lower alpha than [interiorTop] because the blur itself supplies
  /// material.
  static const Color blurredTop = Color(0xA615181D);
  static const Color blurredBottom = Color(0xA60C0E11);

  /// Hairline colour for the uniform base border — kept very faint so it
  /// only suggests the rectangle's silhouette. The visible structure
  /// comes from the top/bottom highlight lines.
  static const Color border = Color(0x1AFFFFFF); // ~7% white

  /// Drop shadow beneath a lifted panel — understated navy-black.
  static const Color shadow = Color(0xA6000000);

  /// Intensity presets for [LiquidEdges].
  static const double topHighlightAlpha = 0.346;
  static const double topHighlightAlphaStrong = 0.475;
  static const double bottomHighlightAlpha = 0.151;
  static const double bottomHighlightAlphaStrong = 0.238;

  /// Colour of the uniform perimeter border used by [CompactBorder] on
  /// small, roughly 1:1 controls (icon buttons, avatars, chips). On
  /// these sizes the asymmetric top/bottom highlight recipe reads as a
  /// loud band, so we swap it for a plain semi-white outline that
  /// simply describes the shape.
  static const Color compactBorder = Color(0x59FFFFFF); // ~35% white
  static const double compactBorderWidth = 0.5;
}

/// Curvature presets so every rounded surface shares the same language.
class GlassRadii {
  GlassRadii._();
  static const Radius pill = Radius.circular(999);
  static const Radius chunk = Radius.circular(28);
  static const Radius card = Radius.circular(22);
  static const Radius tile = Radius.circular(16);
  static const Radius tight = Radius.circular(12);
}

/// Drop-in overlay that paints the "liquid" edges recipe: a bright top
/// highlight line, a softer bottom one, and the uniform hairline that
/// handles the left/right sides. Must be stacked inside a rounded-rect
/// clip (e.g. [ClipRRect]) so the highlights fall off naturally at the
/// corners.
///
/// This widget does NOT fill the background — the parent is expected to
/// provide its own colour/gradient beneath. It is purely the lighting
/// layer.
class LiquidEdges extends StatelessWidget {
  const LiquidEdges({
    super.key,
    required this.borderRadius,
    this.style = LiquidEdgeStyle.horizontal,
    this.topAlpha = GlassPalette.topHighlightAlpha,
    this.bottomAlpha = GlassPalette.bottomHighlightAlpha,
    this.sideAlpha = 0.065,
    this.topThickness = 1.296,
    this.bottomThickness = 1.08,
    this.accent,
  });

  final BorderRadius borderRadius;
  final LiquidEdgeStyle style;

  /// White alpha at the brightest point of the top line.
  final double topAlpha;

  /// White alpha at the brightest point of the bottom line.
  final double bottomAlpha;

  /// White alpha for the uniform hairline (mostly visible on L/R sides).
  final double sideAlpha;

  /// Height of the top highlight in logical px. 1.0–1.6 reads well.
  final double topThickness;

  /// Height of the bottom highlight in logical px. Typically a touch
  /// thinner than [topThickness].
  final double bottomThickness;

  /// Optional accent colour mixed into the highlights (e.g. emerald for
  /// a selected state). When null the highlights stay cool white.
  final Color? accent;

  Color _lerpToAccent(double alpha) {
    if (accent == null) return Colors.white.withValues(alpha: alpha);
    // Blend white with the accent so the highlight still reads as light,
    // not as a painted stripe.
    return Color.lerp(Colors.white, accent, 0.55)!.withValues(alpha: alpha);
  }

  @override
  Widget build(BuildContext context) {
    final Color topBright = _lerpToAccent(topAlpha);
    final double effectiveBottomAlpha =
        style == LiquidEdgeStyle.diagonal && bottomAlpha < topAlpha * 0.92
        ? topAlpha * 0.92
        : bottomAlpha;
    final Color bottomBright = _lerpToAccent(effectiveBottomAlpha);
    final Color hairline = accent == null
        ? Colors.white.withValues(alpha: sideAlpha)
        : Color.lerp(
            Colors.white,
            accent,
            0.4,
          )!.withValues(alpha: (sideAlpha + 0.04).clamp(0.0, 1.0));

    if (style == LiquidEdgeStyle.diagonal) {
      return IgnorePointer(
        child: CustomPaint(
          painter: _DiagonalLiquidEdgesPainter(
            borderRadius: borderRadius,
            topBright: topBright,
            bottomBright: bottomBright,
            hairline: hairline,
            topThickness: topThickness,
            bottomThickness: bottomThickness,
          ),
        ),
      );
    }

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // Uniform hairline — purposely thin so L / R edges read as
          // "barely there" per the design brief.
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              border: Border.all(color: hairline, width: 0.648),
            ),
          ),
          // Top highlight: gradient line that fades at both corners so
          // the rounding reads naturally.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topThickness,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: <Color>[
                    topBright.withValues(alpha: 0),
                    topBright,
                    topBright.withValues(alpha: 0),
                  ],
                  stops: const <double>[0.04, 0.5, 0.96],
                ),
              ),
            ),
          ),
          // Bottom highlight.
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: bottomThickness,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: <Color>[
                    bottomBright.withValues(alpha: 0),
                    bottomBright,
                    bottomBright.withValues(alpha: 0),
                  ],
                  stops: const <double>[0.08, 0.5, 0.92],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagonalLiquidEdgesPainter extends CustomPainter {
  const _DiagonalLiquidEdgesPainter({
    required this.borderRadius,
    required this.topBright,
    required this.bottomBright,
    required this.hairline,
    required this.topThickness,
    required this.bottomThickness,
  });

  final BorderRadius borderRadius;
  final Color topBright;
  final Color bottomBright;
  final Color hairline;
  final double topThickness;
  final double bottomThickness;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final Rect rect = Offset.zero & size;
    final RRect clip = borderRadius.toRRect(rect);
    final RRect outline = borderRadius.toRRect(rect.deflate(0.3));

    canvas.save();
    canvas.clipRRect(clip);

    final Paint borderPaint = Paint()
      ..color = hairline.withValues(alpha: math.max(hairline.a, 0.119))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.594;
    canvas.drawRRect(outline, borderPaint);

    final double topStroke = topThickness.clamp(0.8, 2.0).toDouble();
    final double bottomStroke = bottomThickness.clamp(0.8, 2.0).toDouble();
    final double topOffset = topStroke / 2;
    final double bottomOffset = bottomStroke / 2;
    final double topLeftRadius = _cornerRadius(borderRadius.topLeft, size);
    final double topRightRadius = _cornerRadius(borderRadius.topRight, size);
    final double bottomLeftRadius = _cornerRadius(
      borderRadius.bottomLeft,
      size,
    );
    final double bottomRightRadius = _cornerRadius(
      borderRadius.bottomRight,
      size,
    );

    final Paint topHorizontal = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: <Color>[
          topBright,
          topBright.withValues(alpha: topBright.a * 0.42),
          topBright.withValues(alpha: 0),
        ],
        stops: const <double>[0.0, 0.34, 0.78],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = topStroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawLine(
      Offset(topLeftRadius, topOffset),
      Offset(size.width - topRightRadius, topOffset),
      topHorizontal,
    );

    final Paint leftVertical = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          topBright,
          topBright.withValues(alpha: topBright.a * 0.38),
          topBright.withValues(alpha: 0),
        ],
        stops: const <double>[0.0, 0.32, 0.76],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = topStroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawLine(
      Offset(topOffset, topLeftRadius),
      Offset(topOffset, size.height - bottomLeftRadius),
      leftVertical,
    );

    final Paint bottomHorizontal = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: <Color>[
          bottomBright.withValues(alpha: 0),
          bottomBright.withValues(alpha: bottomBright.a * 0.40),
          bottomBright,
        ],
        stops: const <double>[0.22, 0.66, 1.0],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = bottomStroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawLine(
      Offset(bottomLeftRadius, size.height - bottomOffset),
      Offset(size.width - bottomRightRadius, size.height - bottomOffset),
      bottomHorizontal,
    );

    final Paint rightVertical = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          bottomBright.withValues(alpha: 0),
          bottomBright.withValues(alpha: bottomBright.a * 0.38),
          bottomBright,
        ],
        stops: const <double>[0.24, 0.68, 1.0],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = bottomStroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawLine(
      Offset(size.width - bottomOffset, topRightRadius),
      Offset(size.width - bottomOffset, size.height - bottomRightRadius),
      rightVertical,
    );

    final Paint topLeftCorner = Paint()
      ..color = topBright
      ..style = PaintingStyle.stroke
      ..strokeWidth = topStroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(topLeftRadius, topLeftRadius),
        radius: math.max(0.0, topLeftRadius - topOffset),
      ),
      math.pi,
      math.pi / 2,
      false,
      topLeftCorner,
    );

    final Paint bottomRightCorner = Paint()
      ..color = bottomBright
      ..style = PaintingStyle.stroke
      ..strokeWidth = bottomStroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(
      Rect.fromCircle(
        center: Offset(
          size.width - bottomRightRadius,
          size.height - bottomRightRadius,
        ),
        radius: math.max(0.0, bottomRightRadius - bottomOffset),
      ),
      0,
      math.pi / 2,
      false,
      bottomRightCorner,
    );

    canvas.restore();
  }

  double _cornerRadius(Radius radius, Size size) {
    return math
        .min(radius.x, radius.y)
        .clamp(0.0, math.min(size.width, size.height) / 2)
        .toDouble();
  }

  @override
  bool shouldRepaint(covariant _DiagonalLiquidEdgesPainter old) =>
      old.borderRadius != borderRadius ||
      old.topBright != topBright ||
      old.bottomBright != bottomBright ||
      old.hairline != hairline ||
      old.topThickness != topThickness ||
      old.bottomThickness != bottomThickness;
}

/// Flat, uniform semi-white perimeter border used by *compact* controls
/// (icon buttons, avatars, small chips). These elements are close to a
/// 1:1 aspect ratio, so the asymmetric top/bottom recipe from
/// [LiquidEdges] reads as a bright band rather than a subtle highlight;
/// a plain outline describes the shape without visual noise.
///
/// Non-interactive (pointer events pass through) and intended to sit in
/// a [Stack] above whatever fill the parent provides.
class CompactBorder extends StatelessWidget {
  const CompactBorder({
    super.key,
    required this.borderRadius,
    this.color = GlassPalette.compactBorder,
    this.width = GlassPalette.compactBorderWidth,
  });

  final BorderRadius borderRadius;
  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border.all(color: color, width: width),
        ),
      ),
    );
  }
}

/// Standalone "liquid" container for non-blurred surfaces (tiles, rows,
/// inline buttons). Produces the same asymmetric highlight recipe as
/// [FrostedSurface] but without the backdrop blur so it's cheap to nest
/// inside scroll lists.
///
/// Use this as a drop-in replacement for
/// `Container(decoration: BoxDecoration(border: Border.all(...)))` anywhere
/// you want the floating-panel look.
class LiquidTile extends StatelessWidget {
  const LiquidTile({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = const BorderRadius.all(GlassRadii.tile),
    this.selected = false,
    this.accent,
    this.elevated = true,
    this.topColor,
    this.bottomColor,
    this.compact = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius borderRadius;
  final bool selected;
  final Color? accent;
  final bool elevated;

  /// Override the interior gradient's top stop (defaults to
  /// [GlassPalette.interiorTop]).
  final Color? topColor;

  /// Override the interior gradient's bottom stop (defaults to
  /// [GlassPalette.interiorBottom]).
  final Color? bottomColor;

  /// Dim the top/bottom highlight lines by ~30%. Use on small, roughly
  /// square controls where the regular recipe reads as a bright band.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Selected tiles keep the same dark interior as the rest — the accent
    // lives only on the edge rails (see LiquidEdges below), never in the
    // fill, so nothing reads as a lighter "silver" slab.
    final Color effectiveTop = topColor ?? GlassPalette.interiorTop;
    final Color effectiveBottom = bottomColor ?? GlassPalette.interiorBottom;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: elevated
            ? <BoxShadow>[
                BoxShadow(
                  color: GlassPalette.shadow,
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                  spreadRadius: -6,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: <Widget>[
            // Dark gradient fill.
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[effectiveTop, effectiveBottom],
                ),
              ),
              padding: padding,
              child: child,
            ),
            // Edge treatment:
            //   * compact (1:1-ish controls) -> plain semi-white
            //     perimeter border, no gradient rails.
            //   * regular -> asymmetric top/bottom highlights via
            //     [LiquidEdges], accent-blended when selected.
            Positioned.fill(
              child: compact
                  ? CompactBorder(borderRadius: borderRadius)
                  : LiquidEdges(
                      borderRadius: borderRadius,
                      topAlpha: selected
                          ? GlassPalette.topHighlightAlphaStrong
                          : GlassPalette.topHighlightAlpha,
                      bottomAlpha: selected
                          ? GlassPalette.bottomHighlightAlphaStrong
                          : GlassPalette.bottomHighlightAlpha,
                      sideAlpha: selected ? 0.14 : 0.06,
                      accent: selected ? accent : null,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Re-usable frosted-glass surface. On weak devices the real backdrop blur
/// is swapped for a flat translucent gradient so scrolling stays at 60 fps.
///
/// Rebuilt for the liquid language: the child is stacked over a dark,
/// lightly vertical gradient and finished with a [LiquidEdges] overlay so
/// the top/bottom read as lit while the sides stay whisper-thin.
class FrostedSurface extends StatelessWidget {
  const FrostedSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(GlassRadii.card),
    this.sigma = 18.0,
    this.tint,
    this.border = true,
    this.padding,
    this.clipBehavior = Clip.antiAlias,
    this.elevated = true,
    this.compact = false,
    this.edgeStyle = LiquidEdgeStyle.horizontal,
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// Backdrop blur sigma. Larger sigma = heavier frost. 12-22 is comfortable.
  final double sigma;

  /// Optional override for the interior tint. Leave null to inherit the
  /// palette's dark gradient (recommended for consistency).
  final Color? tint;

  /// When false the liquid edges overlay is skipped entirely, useful for
  /// rare cases where the parent wants raw blur without the highlight.
  final bool border;
  final EdgeInsetsGeometry? padding;
  final Clip clipBehavior;

  /// Drop a subtle shadow below the element so it floats above the base.
  final bool elevated;

  /// Dim the highlight lines by ~30% — appropriate for small square
  /// controls (icon buttons, tight avatars).
  final bool compact;
  final LiquidEdgeStyle edgeStyle;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LiteMode.instance,
      builder: (BuildContext context, _) {
        final bool useRealBlur = LiteMode.instance.isEnabled(
          RabochiyEffect.frostedGlass,
        );

        // Dark interior gradient — stays consistent whether blur is on or
        // off, so the visual identity doesn't change on lower-end devices.
        final Color top =
            tint ??
            (useRealBlur ? GlassPalette.blurredTop : GlassPalette.interiorTop);
        final Color bottom =
            tint ??
            (useRealBlur
                ? GlassPalette.blurredBottom
                : GlassPalette.interiorBottom);

        final Widget fill = Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[top, bottom],
            ),
          ),
          child: child,
        );

        final Widget stacked = Stack(
          children: <Widget>[
            fill,
            if (border)
              Positioned.fill(
                // Compact (1:1-ish) surfaces swap the asymmetric
                // highlight for a plain semi-white perimeter; regular
                // surfaces keep the full liquid recipe.
                child: compact
                    ? CompactBorder(borderRadius: borderRadius)
                    : LiquidEdges(borderRadius: borderRadius, style: edgeStyle),
              ),
          ],
        );

        final Widget clipped = ClipRRect(
          borderRadius: borderRadius,
          clipBehavior: clipBehavior,
          child: useRealBlur
              ? BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                  child: stacked,
                )
              : stacked,
        );

        if (!elevated) return clipped;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: GlassPalette.shadow,
                blurRadius: 18,
                offset: Offset(0, 8),
                spreadRadius: -6,
              ),
            ],
          ),
          child: clipped,
        );
      },
    );
  }
}

/// A capsule-shaped variant of [FrostedSurface] used for chips and status
/// badges. Shares the liquid highlight recipe but with a tighter shadow
/// and no elevation when the pill sits flush with a surrounding card.
class FrostedPill extends StatelessWidget {
  const FrostedPill({
    super.key,
    required this.child,
    this.tint,
    this.sigma = 14.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    this.borderColor,
    this.elevated = false,
    this.accent,
  });

  final Widget child;
  final Color? tint;
  final double sigma;
  final EdgeInsetsGeometry padding;

  /// Legacy hook preserved for callers that still pass an explicit border
  /// colour. Left unused by the liquid recipe but kept so existing call
  /// sites compile. Prefer [accent] for coloured highlights.
  final Color? borderColor;

  final bool elevated;

  /// Optional accent that blends into the top/bottom highlight lines
  /// (e.g. emerald for active status pills).
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LiteMode.instance,
      builder: (BuildContext context, _) {
        final bool useRealBlur = LiteMode.instance.isEnabled(
          RabochiyEffect.frostedGlass,
        );
        const BorderRadius radius = BorderRadius.all(GlassRadii.pill);

        final Color top =
            tint ??
            (useRealBlur ? GlassPalette.blurredTop : GlassPalette.interiorTop);
        final Color bottom =
            tint ??
            (useRealBlur
                ? GlassPalette.blurredBottom
                : GlassPalette.interiorBottom);

        final Widget fill = Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[top, bottom],
            ),
          ),
          child: child,
        );

        final Widget stacked = Stack(
          children: <Widget>[
            fill,
            Positioned.fill(
              child: LiquidEdges(borderRadius: radius, accent: accent),
            ),
          ],
        );

        final Widget clipped = ClipRRect(
          borderRadius: radius,
          child: useRealBlur
              ? BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                  child: stacked,
                )
              : stacked,
        );

        if (!elevated) return clipped;
        return DecoratedBox(
          decoration: const BoxDecoration(
            borderRadius: radius,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: GlassPalette.shadow,
                blurRadius: 12,
                offset: Offset(0, 4),
                spreadRadius: -4,
              ),
            ],
          ),
          child: clipped,
        );
      },
    );
  }
}
