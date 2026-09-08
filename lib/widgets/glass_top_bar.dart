import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../motion/glass.dart';
import '../motion/press_feedback.dart';

/// Top-of-screen bar used by the home & settings screens. Renders a brand
/// capsule on the left, trailing action icons on the right, and leaves the
/// frosted backdrop intact beneath.
class GlassTopBar extends StatelessWidget {
  const GlassTopBar({
    super.key,
    required this.brandLabel,
    this.leading,
    this.trailing = const <Widget>[],
  });

  final String brandLabel;
  final Widget? leading;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[leading!, const SizedBox(width: 10)],
          FrostedPill(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              brandLabel,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const Spacer(),
          for (final Widget w in trailing) ...<Widget>[
            w,
            const SizedBox(width: 8),
          ],
          if (trailing.isNotEmpty) const SizedBox(width: 0),
        ],
      ),
    );
  }
}

/// Square glass icon button used for top-bar actions.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 42,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: FrostedSurface(
        borderRadius: AppRadii.tile,
        sigma: 14,
        compact: true,
        padding: EdgeInsets.all((size - 20) / 2),
        child: SizedBox(
          width: 20,
          height: 20,
          child: Icon(icon, size: 20, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}
