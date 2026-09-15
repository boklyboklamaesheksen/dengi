import 'package:flutter/material.dart';
import 'package:responsive_framework/responsive_framework.dart';

class AppViewport extends StatelessWidget {
  const AppViewport({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return MediaQuery(
      data: mediaQuery.copyWith(
        textScaler: mediaQuery.textScaler.clamp(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.15,
        ),
      ),
      // Every former breakpoint used 424; no nullable lookup is needed.
      child: ResponsiveScaledBox(
        width: 424,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
