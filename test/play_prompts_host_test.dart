import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rabochiy_vpn/l10n/app_localizations.dart';
import 'package:rabochiy_vpn/providers/app_provider.dart';
import 'package:rabochiy_vpn/services/in_app_review_service.dart';
import 'package:rabochiy_vpn/services/in_app_update_service.dart';
import 'package:rabochiy_vpn/services/play_store_bridge.dart';
import 'package:rabochiy_vpn/services/vpn_service.dart';
import 'package:rabochiy_vpn/widgets/play_prompts_host.dart';

import 'support/catalog_fakes.dart';
import 'support/play_store_fakes.dart';

const int mb = 1024 * 1024;

void main() {
  late FakePlayStoreBridge bridge;
  late FakeVpnService vpn;
  late AppProvider provider;
  late InAppUpdateService updates;

  setUp(() {
    // One good session already happened in an earlier run.
    SharedPreferences.setMockInitialValues({
      'rabochiy_review_good_sessions_v1': 1,
    });
    bridge = FakePlayStoreBridge();
    updates = InAppUpdateService(bridge: bridge);
  });

  Future<void> pumpHost(WidgetTester tester, {bool homeTab = true}) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: provider,
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: PlayPromptsHost(
            homeTabActive: homeTab,
            updates: updates,
            child: const Scaffold(body: Center(child: Text('home'))),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  void createProvider() {
    vpn = FakeVpnService();
    provider = AppProvider(
      apiService: FakeApi(fetch: () async => []),
      gwApiService: FakeGwApi(fetch: () async => []),
      vlessService: FakeVless(),
      vpnService: vpn,
      reviewService: InAppReviewService(bridge: bridge),
    );
  }

  Future<void> startGoodSession(WidgetTester tester) async {
    vpn.emitStatus(VpnStatus.connecting);
    await tester.pump();
    vpn.emitStatus(VpnStatus.connected);
    await tester.pump();
    vpn.emitTraffic(12 * mb);
    await tester.pump();
  }

  Future<void> tearDownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  }

  testWidgets('review is requested once the user idles on the VPN tab', (
    tester,
  ) async {
    createProvider();
    await pumpHost(tester);
    await startGoodSession(tester);
    expect(provider.reviewPrompt.goodSessions, 2);

    await tester.pump(const Duration(seconds: 2));
    expect(bridge.reviewRequests, 0);
    await tester.pump(const Duration(milliseconds: 600));
    expect(bridge.reviewRequests, 1);

    await tester.pump(const Duration(seconds: 10));
    expect(bridge.reviewRequests, 1, reason: 'once per app run');
    await tearDownTree(tester);
  });

  testWidgets('touching the screen restarts the calm window', (tester) async {
    createProvider();
    await pumpHost(tester);
    await startGoodSession(tester);
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('home'));
    await tester.pump(const Duration(seconds: 2));
    expect(bridge.reviewRequests, 0);
    await tester.pump(const Duration(milliseconds: 600));
    expect(bridge.reviewRequests, 1);
    await tearDownTree(tester);
  });

  testWidgets(
    'nothing is shown on other tabs, under dialogs or in background',
    (tester) async {
      createProvider();
      await pumpHost(tester, homeTab: false);
      await startGoodSession(tester);
      await tester.pump(const Duration(seconds: 5));
      expect(bridge.reviewRequests, 0);

      await pumpHost(tester);
      final BuildContext context = tester.element(find.text('home'));
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('dialog')),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      expect(bridge.reviewRequests, 0);

      Navigator.of(tester.element(find.text('dialog'))).pop();
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 5));
      expect(bridge.reviewRequests, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 3));
      expect(bridge.reviewRequests, 1);
      await tearDownTree(tester);
    },
  );

  testWidgets('a downloaded update shows the restart snackbar, not a review', (
    tester,
  ) async {
    createProvider();
    await pumpHost(tester);
    await startGoodSession(tester);
    updates.readyToInstall.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
    expect(
      find.text(
        'Update downloaded. Restarting to install it will disconnect the VPN.',
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    expect(bridge.reviewRequests, 0);

    await tester.tap(find.text('Restart'));
    await tester.pump();
    expect(bridge.completeCalls, 1);
    await tearDownTree(tester);
  });

  testWidgets(
    'a flexible update offer waits for calm and replaces the review',
    (tester) async {
      bridge.updateInfo = const PlayUpdateInfo(
        updateAvailability: PlayUpdateAvailability.available,
        installStatus: PlayInstallStatus.unknown,
        flexibleAllowed: true,
      );
      createProvider();
      await pumpHost(tester);
      await startGoodSession(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(bridge.startedFlows, isEmpty);
      await tester.pump(const Duration(milliseconds: 600));
      expect(bridge.startedFlows, [PlayUpdateType.flexible]);
      await tester.pump(const Duration(seconds: 10));
      expect(bridge.reviewRequests, 0);
      await tearDownTree(tester);
    },
  );

  testWidgets('a critical update opens immediately', (tester) async {
    bridge.updateInfo = const PlayUpdateInfo(
      updateAvailability: PlayUpdateAvailability.available,
      installStatus: PlayInstallStatus.unknown,
      updatePriority: 5,
      flexibleAllowed: true,
      immediateAllowed: true,
    );
    createProvider();
    await pumpHost(tester);
    await tester.pump();
    expect(bridge.startedFlows, [PlayUpdateType.immediate]);
    await tearDownTree(tester);
  });
}
