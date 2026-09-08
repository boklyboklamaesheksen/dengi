import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../motion/glass.dart';

/// High-level card wrapper used across the app. Builds on [FrostedSurface]
/// and adds consistent padding, hairline border and optional top sheen.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.borderRadius = AppRadii.card,
    this.sigma = 18.0,
    this.tint,
    this.sheen = false,
    this.edgeStyle = LiquidEdgeStyle.horizontal,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final double sigma;
  final Color? tint;
  final bool sheen;
  final LiquidEdgeStyle edgeStyle;

  @override
  Widget build(BuildContext context) {
    return FrostedSurface(
      borderRadius: borderRadius,
      sigma: sigma,
      tint: tint ?? GlassPalette.sheet,
      padding: padding,
      edgeStyle: edgeStyle,
      child: sheen
          ? Stack(
              children: <Widget>[
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: borderRadius,
                        gradient: AppColors.sheen,
                      ),
                    ),
                  ),
                ),
                child,
              ],
            )
          : child,
    );
  }
}

/// Small utility that paints a divider inside a [GlassCard] respecting the
/// current glass tone.
class GlassDivider extends StatelessWidget {
  const GlassDivider({super.key, this.inset = 18.0});

  final double inset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: inset),
      child: const Divider(height: 1, color: AppColors.border),
    );
  }
}
