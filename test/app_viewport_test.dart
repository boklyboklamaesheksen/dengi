import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rabochiy_vpn/widgets/app_viewport.dart';

void main() {
  for (final width in [320.0, 450.5, 800.5, 1920.5, 2560.0]) {
    testWidgets('viewport accepts width $width without a nullable breakpoint', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => AppViewport(child: child),
        home: const Scaffold(body: Text('ready')),
      ));
      expect(find.text('ready'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('viewport tolerates a missing navigator child', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AppViewport()));
    expect(tester.takeException(), isNull);
  });
}
