import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rabochiy_vpn/widgets/primary_action.dart';

void main() {
  Future<int> pumpAndTap(
    WidgetTester tester, {
    required bool isConnected,
    required bool isBusy,
    required bool isConnecting,
    required String expectedLabel,
  }) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrimaryAction(
            isConnected: isConnected,
            isBusy: isBusy,
            isConnecting: isConnecting,
            onTap: () => taps++,
            connectLabel: 'CONNECT',
            disconnectLabel: 'DISCONNECT',
            busyConnectLabel: 'CONNECTING',
            busyDisconnectLabel: 'DISCONNECTING',
            cancelLabel: 'TAP TO CANCEL',
          ),
        ),
      ),
    );
    expect(find.text(expectedLabel), findsOneWidget);
    await tester.tap(find.text(expectedLabel));
    await tester.pump(const Duration(milliseconds: 300));
    return taps;
  }

  testWidgets('disconnecting shows its label and ignores taps', (tester) async {
    final taps = await pumpAndTap(
      tester,
      isConnected: false,
      isBusy: true,
      isConnecting: false,
      expectedLabel: 'DISCONNECTING',
    );
    expect(taps, 0);
  });

  testWidgets('connecting offers cancel', (tester) async {
    final taps = await pumpAndTap(
      tester,
      isConnected: false,
      isBusy: true,
      isConnecting: true,
      expectedLabel: 'TAP TO CANCEL',
    );
    expect(taps, 1);
  });

  testWidgets('idle and connected take taps', (tester) async {
    expect(
      await pumpAndTap(
        tester,
        isConnected: false,
        isBusy: false,
        isConnecting: false,
        expectedLabel: 'CONNECT',
      ),
      1,
    );
    expect(
      await pumpAndTap(
        tester,
        isConnected: true,
        isBusy: false,
        isConnecting: false,
        expectedLabel: 'DISCONNECT',
      ),
      1,
    );
  });
}
