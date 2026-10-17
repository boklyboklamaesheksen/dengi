import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rabochiy_vpn/services/in_app_review_service.dart';
import 'package:rabochiy_vpn/services/in_app_update_service.dart';
import 'package:rabochiy_vpn/services/play_store_bridge.dart';
import 'package:rabochiy_vpn/services/vpn_service.dart';

import 'support/play_store_fakes.dart';

const int mb = 1024 * 1024;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InAppReviewService', () {
    late FakePlayStoreBridge bridge;
    late DateTime now;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      bridge = FakePlayStoreBridge();
      now = DateTime.utc(2026, 10, 17, 12);
    });

    Future<InAppReviewService> loaded() async {
      final service = InAppReviewService(bridge: bridge, now: () => now);
      await service.load();
      return service;
    }

    void session(InAppReviewService service, int bytes) {
      service.onVpnStatus(VpnStatus.connecting);
      service.onVpnStatus(VpnStatus.connected);
      service.onSessionTraffic(bytes);
    }

    test(
      'needs two sessions with real traffic, the live one included',
      () async {
        final service = await loaded();
        session(service, 9 * mb);
        expect(service.shouldRequestReview(VpnStatus.connected), isFalse);
        service.onSessionTraffic(10 * mb);
        expect(service.goodSessions, 1);
        expect(service.shouldRequestReview(VpnStatus.connected), isFalse);
        service.onVpnStatus(VpnStatus.disconnecting);
        service.onVpnStatus(VpnStatus.disconnected);

        session(service, 2 * mb);
        expect(
          service.shouldRequestReview(VpnStatus.connected),
          isFalse,
          reason: 'the current session has not proven itself yet',
        );
        service.onSessionTraffic(12 * mb);
        expect(service.goodSessions, 2);
        expect(service.shouldRequestReview(VpnStatus.connected), isTrue);
        expect(service.shouldRequestReview(VpnStatus.connecting), isFalse);
        expect(service.shouldRequestReview(VpnStatus.error), isFalse);
      },
    );

    test('one heavy session is enough on its own', () async {
      final service = await loaded();
      session(service, 49 * mb);
      expect(service.shouldRequestReview(VpnStatus.connected), isFalse);
      service.onSessionTraffic(50 * mb);
      expect(service.shouldRequestReview(VpnStatus.connected), isTrue);
    });

    test(
      'right after a good session ends, but not later or after a failure',
      () async {
        SharedPreferences.setMockInitialValues({
          'rabochiy_review_good_sessions_v1': 1,
        });
        final service = await loaded();
        session(service, 20 * mb);
        service.onVpnStatus(VpnStatus.disconnecting);
        service.onVpnStatus(VpnStatus.disconnected);
        expect(service.shouldRequestReview(VpnStatus.disconnected), isTrue);
        now = now.add(const Duration(seconds: 61));
        expect(service.shouldRequestReview(VpnStatus.disconnected), isFalse);

        session(service, 20 * mb);
        service.onVpnStatus(VpnStatus.disconnected);
        service.onVpnStatus(VpnStatus.connecting);
        service.onVpnStatus(VpnStatus.error);
        service.onVpnStatus(VpnStatus.disconnected);
        expect(
          service.shouldRequestReview(VpnStatus.disconnected),
          isFalse,
          reason: 'a new attempt failed after the good session',
        );

        session(service, 20 * mb);
        service.onVpnStatus(VpnStatus.error);
        service.onVpnStatus(VpnStatus.disconnected);
        expect(
          service.shouldRequestReview(VpnStatus.disconnected),
          isFalse,
          reason: 'the session itself ended with an error',
        );
      },
    );

    test('logout forgets the live session', () async {
      final service = await loaded();
      session(service, 60 * mb);
      service.forgetSession();
      expect(service.shouldRequestReview(VpnStatus.connected), isFalse);
      service.onVpnStatus(VpnStatus.disconnected);
      expect(service.shouldRequestReview(VpnStatus.disconnected), isFalse);
    });

    test(
      'traffic seen before storage loads is counted on the next sample',
      () async {
        SharedPreferences.setMockInitialValues({
          'rabochiy_review_good_sessions_v1': 4,
        });
        final service = InAppReviewService(bridge: bridge, now: () => now);
        session(service, 15 * mb);
        await service.load();
        expect(service.goodSessions, 4);
        service.onSessionTraffic(16 * mb);
        expect(service.goodSessions, 5);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt('rabochiy_review_good_sessions_v1'), 5);
      },
    );

    test(
      'asks once per run, then honours the retry gap and attempt cap',
      () async {
        var service = await loaded();
        session(service, 60 * mb);
        await service.requestReview();
        expect(bridge.reviewRequests, 1);
        expect(service.attempts, 1);
        expect(service.shouldRequestReview(VpnStatus.connected), isFalse);
        await service.requestReview();
        expect(bridge.reviewRequests, 1);

        for (var attempt = 2; attempt <= 3; attempt++) {
          now = now.add(const Duration(days: 59));
          service = await loaded();
          session(service, 60 * mb);
          expect(service.shouldRequestReview(VpnStatus.connected), isFalse);
          now = now.add(const Duration(days: 1));
          expect(service.shouldRequestReview(VpnStatus.connected), isTrue);
          await service.requestReview();
          expect(service.attempts, attempt);
        }

        now = now.add(const Duration(days: 365));
        service = await loaded();
        session(service, 60 * mb);
        expect(service.shouldRequestReview(VpnStatus.connected), isFalse);
      },
    );

    test('an attempt is not spent when Play cannot run the flow', () async {
      bridge.reviewResult = false;
      var service = await loaded();
      session(service, 60 * mb);
      await service.requestReview();
      expect(bridge.reviewRequests, 1);
      expect(service.attempts, 0);
      expect(
        service.shouldRequestReview(VpnStatus.connected),
        isFalse,
        reason: 'not again in the same run',
      );

      bridge.reviewResult = true;
      service = await loaded();
      session(service, 60 * mb);
      expect(service.shouldRequestReview(VpnStatus.connected), isTrue);
    });
  });

  group('InAppUpdateService', () {
    late FakePlayStoreBridge bridge;
    late DateTime now;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      bridge = FakePlayStoreBridge();
      now = DateTime.utc(2026, 10, 17, 12);
    });

    InAppUpdateService service() =>
        InAppUpdateService(bridge: bridge, now: () => now);

    test('a regular release is offered as a flexible update', () async {
      bridge.updateInfo = const PlayUpdateInfo(
        updateAvailability: PlayUpdateAvailability.available,
        installStatus: PlayInstallStatus.unknown,
        flexibleAllowed: true,
        immediateAllowed: true,
      );
      final updates = service();
      await updates.refresh();
      expect(updates.pendingOffer, UpdateOffer.flexible);
      expect(updates.blocksReview, isTrue);
      await updates.showPendingOffer();
      expect(bridge.startedFlows, [PlayUpdateType.flexible]);
      expect(updates.pendingOffer, UpdateOffer.none);
      expect(
        bridge.installStatusListeners,
        1,
        reason: 'progress listener is registered before the flow',
      );
    });

    test('priority 4+ releases use the immediate flow', () async {
      bridge.updateInfo = const PlayUpdateInfo(
        updateAvailability: PlayUpdateAvailability.available,
        installStatus: PlayInstallStatus.unknown,
        updatePriority: 4,
        flexibleAllowed: true,
        immediateAllowed: true,
      );
      final updates = service();
      await updates.refresh();
      expect(updates.pendingOffer, UpdateOffer.immediate);
      await updates.showPendingOffer();
      expect(bridge.startedFlows, [PlayUpdateType.immediate]);
    });

    test('"No thanks" keeps the flexible dialog away for three days', () async {
      bridge.updateInfo = const PlayUpdateInfo(
        updateAvailability: PlayUpdateAvailability.available,
        installStatus: PlayInstallStatus.unknown,
        flexibleAllowed: true,
      );
      bridge.flowResult = PlayUpdateFlowResult.canceled;
      var updates = service();
      await updates.refresh();
      await updates.showPendingOffer();
      expect(bridge.startedFlows, [PlayUpdateType.flexible]);

      updates = service();
      await updates.refresh();
      expect(updates.pendingOffer, UpdateOffer.none);
      await updates.showPendingOffer();
      expect(bridge.startedFlows, [PlayUpdateType.flexible]);

      now = now.add(const Duration(days: 2, hours: 23));
      updates = service();
      await updates.refresh();
      expect(updates.pendingOffer, UpdateOffer.none);
      expect(updates.blocksReview, isFalse);
      now = now.add(const Duration(hours: 1));
      updates = service();
      await updates.refresh();
      expect(updates.pendingOffer, UpdateOffer.flexible);
    });

    test(
      'a finished download asks for a restart and completes on demand',
      () async {
        bridge.updateInfo = const PlayUpdateInfo(
          updateAvailability:
              PlayUpdateAvailability.developerTriggeredInProgress,
          installStatus: PlayInstallStatus.downloading,
        );
        final updates = service();
        await updates.refresh();
        expect(updates.readyToInstall.value, isFalse);
        expect(updates.blocksReview, isTrue);
        bridge.emitInstallStatus(PlayInstallStatus.downloaded);
        await Future<void>.delayed(Duration.zero);
        expect(updates.readyToInstall.value, isTrue);
        await updates.completeUpdate();
        expect(bridge.completeCalls, 1);
      },
    );

    test(
      'an accepted immediate update is resumed when the app returns',
      () async {
        SharedPreferences.setMockInitialValues({
          'rabochiy_update_flow_type_v1': 'immediate',
        });
        bridge.updateInfo = const PlayUpdateInfo(
          updateAvailability:
              PlayUpdateAvailability.developerTriggeredInProgress,
          installStatus: PlayInstallStatus.downloading,
        );
        final updates = service();
        await updates.refresh();
        expect(bridge.startedFlows, [PlayUpdateType.immediate]);
      },
    );

    test('builds that Play cannot update stay silent', () async {
      bridge.updateInfo = null;
      final updates = service();
      await updates.refresh();
      expect(updates.pendingOffer, UpdateOffer.none);
      expect(updates.blocksReview, isFalse);
      expect(updates.readyToInstall.value, isFalse);

      final offPlay = InAppUpdateService(
        bridge: PlayStoreBridge(platformSupported: false),
      );
      await offPlay.refresh();
      expect(offPlay.pendingOffer, UpdateOffer.none);
    });
  });

  group('PlayStoreBridge channel contract', () {
    const channel = MethodChannel('app.rabochiy.vpn/play_store');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('maps native answers and failures', () async {
      final calls = <MethodCall>[];
      var updateAnswer = 'accepted';
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'requestReview':
            return 'completed';
          case 'getUpdateInfo':
            return <String, Object?>{
              'updateAvailability': 2,
              'installStatus': 0,
              'availableVersionCode': 10,
              'updatePriority': 5,
              'clientVersionStalenessDays': null,
              'flexibleAllowed': true,
              'immediateAllowed': false,
            };
          case 'startUpdate':
            return updateAnswer;
          case 'completeUpdate':
            throw PlatformException(code: 'COMPLETE_UPDATE_FAILED');
        }
        return null;
      });
      final bridge = PlayStoreBridge(platformSupported: true);

      expect(await bridge.requestReview(), isTrue);
      final info = (await bridge.getUpdateInfo())!;
      expect(info.isUpdateAvailable, isTrue);
      expect(info.updatePriority, 5);
      expect(info.availableVersionCode, 10);
      expect(info.stalenessDays, isNull);
      expect(info.flexibleAllowed, isTrue);
      expect(info.immediateAllowed, isFalse);
      expect(
        await bridge.startUpdate(PlayUpdateType.flexible),
        PlayUpdateFlowResult.accepted,
      );
      expect(calls.last.arguments, {'type': 'flexible'});
      for (final entry in {
        'canceled': PlayUpdateFlowResult.canceled,
        'not_allowed': PlayUpdateFlowResult.notAllowed,
        'unavailable': PlayUpdateFlowResult.unavailable,
        'failed': PlayUpdateFlowResult.failed,
        'busy': PlayUpdateFlowResult.failed,
      }.entries) {
        updateAnswer = entry.key;
        expect(await bridge.startUpdate(PlayUpdateType.immediate), entry.value);
      }
      expect(calls.last.arguments, {'type': 'immediate'});
      expect(await bridge.completeUpdate(), isFalse);
    });

    test('a missing native side is not an error', () async {
      final bridge = PlayStoreBridge(platformSupported: true);
      expect(await bridge.requestReview(), isFalse);
      expect(await bridge.getUpdateInfo(), isNull);
      expect(
        await bridge.startUpdate(PlayUpdateType.flexible),
        PlayUpdateFlowResult.unavailable,
      );
      expect(await bridge.completeUpdate(), isFalse);
    });
  });
}
