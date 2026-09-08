import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// Optimized solid backdrop for Rabochiy VPN.
///
/// Replaced the heavy blur math with a highly optimized solid color
/// filling. Eliminates GPU strain, prevents device heating, and saves
/// battery life, while preserving the premium dark minimal look.
class HaloField extends StatelessWidget {
  const HaloField({
    super.key,
    this.active = false,
    this.child,
  });

  final bool active;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.base,
      child: child ?? const SizedBox.shrink(),
    );
  }
}
