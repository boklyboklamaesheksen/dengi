import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../motion/glass.dart';
import '../motion/motion_curves.dart';
import '../motion/press_feedback.dart';

/// Horizontal segmented tab bar with a sliding capsule indicator, wrapped in
/// a frosted-glass pill. The indicator animation uses the app's "premiumOut"
/// curve so switches feel decisive but not jarring.
class GlassTabBar extends StatelessWidget {
  const GlassTabBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double tabWidth = constraints.maxWidth / tabs.length;
        return FrostedSurface(
          borderRadius: const BorderRadius.all(GlassRadii.pill),
          sigma: 14,
          padding: const EdgeInsets.all(4),
          child: SizedBox(
            height: 42,
            child: Stack(
              children: <Widget>[
                AnimatedPositioned(
                  duration: RabochiyDurations.tabSwitch,
                  curve: RabochiyCurves.premiumOut,
                  left: tabWidth * selectedIndex,
                  top: 0,
                  bottom: 0,
                  width: tabWidth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.all(GlassRadii.pill),
                      color: AppColors.surfaceElevated,
                      border: Border.all(color: AppColors.borderStrong),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: GlassPalette.shadow,
                          blurRadius: 14,
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: <Widget>[
                    for (int i = 0; i < tabs.length; i++)
                      Expanded(
                        child: PressScale(
                          pressedScale: 0.95,
                          onTap: () => onChanged(i),
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: RabochiyDurations.tabSwitch,
                              curve: RabochiyCurves.brisk,
                              style: TextStyle(
                                color: i == selectedIndex
                                    ? Colors.white
                                    : AppColors.textSecondary,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                                letterSpacing: 1.1,
                              ),
                              child: Text(tabs[i]),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
