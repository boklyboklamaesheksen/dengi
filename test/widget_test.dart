// Smoke test for Rabochiy VPN. Verifies the app boots and lands on the
// splash / home screen. Full integration tests (VPN connect / API
// fetch) live in a separate harness that is not part of `flutter test`.

import 'package:flutter_test/flutter_test.dart';

import 'package:rabochiy_vpn/main.dart';

void main() {
  testWidgets('App boots and renders the Rabochiy wordmark', (tester) async {
    await tester.pumpWidget(const RabochiyVpnApp(initialRoute: '/welcome'));
    // First pump kicks the splash; one more lets any post-frame
    // callbacks settle so we don't race the wordmark animation.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Rabochiy VPN'), findsWidgets);
  });
}
