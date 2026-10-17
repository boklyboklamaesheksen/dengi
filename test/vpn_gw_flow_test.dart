import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rabochiy_vpn/models/server_config_model.dart';
import 'package:rabochiy_vpn/services/vpn_service.dart';

import 'support/catalog_fakes.dart';

Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// GW engine lifecycle against scripted native channels. The GW engine
/// reports its states from worker threads, after the method call returned.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const engine = MethodChannel('rabochiy_vpn/engine');
  const engineEvents = EventChannel('rabochiy_vpn/engine/status');
  const vlee = MethodChannel('app.rabochiy.vpn/vlee');
  const vleeEvents = EventChannel('app.rabochiy.vpn/vlee/status');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  MockStreamHandlerEventSink? sink;
  late List<String> vleeCalls;
  late bool permission;
  late Object? initializeResult;
  late String replay;

  setUp(() {
    sink = null;
    vleeCalls = <String>[];
    permission = true;
    initializeResult = true;
    replay = 'DISCONNECTED';
    messenger.setMockMethodCallHandler(engine, (call) async {
      switch (call.method) {
        case 'initialize':
          return initializeResult;
        case 'requestPermission':
          return permission;
        case 'disconnect':
          return true;
      }
      return null;
    });
    messenger.setMockStreamHandler(
      engineEvents,
      MockStreamHandler.inline(onListen: (_, _) {}),
    );
    messenger.setMockMethodCallHandler(vlee, (call) async {
      vleeCalls.add(call.method);
      return true;
    });
    messenger.setMockStreamHandler(
      vleeEvents,
      MockStreamHandler.inline(
        onListen: (_, events) {
          sink = events;
          // The native side replays its current state to a new listener.
          events.success('STATE:$replay');
        },
      ),
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(engine, null);
    messenger.setMockStreamHandler(engineEvents, null);
    messenger.setMockMethodCallHandler(vlee, null);
    messenger.setMockStreamHandler(vleeEvents, null);
  });

  Future<VpnService> connected({
    Duration gwStopTimeout = const Duration(seconds: 5),
  }) async {
    final service = VpnService(
      platformSupported: true,
      gwStopTimeout: gwStopTimeout,
    );
    addTearDown(service.dispose);
    final attempt = service.connect(gwServer);
    await settle();
    expect(service.status, VpnStatus.connecting);
    sink!.success('STATE:CONNECTING');
    sink!.success('STATE:CONNECTED');
    expect(await attempt, isTrue);
    expect(service.status, VpnStatus.connected);
    return service;
  }

  test(
    'a DISCONNECTED arriving after disconnect returned ends the stop',
    () async {
      final service = await connected();
      final stopping = service.disconnect();
      await settle();
      expect(vleeCalls, contains('disconnect'));
      expect(service.status, VpnStatus.disconnecting);
      sink!.success('STATE:DISCONNECTED');
      expect(await stopping, isTrue);
      expect(service.status, VpnStatus.disconnected);
    },
  );

  test('disconnect still finishes when the engine never confirms', () async {
    final service = await connected(
      gwStopTimeout: const Duration(milliseconds: 50),
    );
    await service.disconnect();
    expect(service.status, VpnStatus.disconnected);
  });

  test(
    'a GW node that fails after CONNECTING is reported unreachable',
    () async {
      final service = VpnService(platformSupported: true);
      addTearDown(service.dispose);
      final statuses = <VpnStatus>[];
      service.statusStream.listen(statuses.add);
      final attempt = service.connect(gwServer);
      await settle();
      sink!.success('STATE:CONNECTING');
      sink!.success('STATE:DISCONNECTED');
      expect(await attempt, isFalse);
      await settle();
      expect(service.errorMessage, 'awg_handshake_timeout');
      expect(service.status, VpnStatus.error);
      expect(statuses, <VpnStatus>[VpnStatus.connecting, VpnStatus.error]);
    },
  );

  test('a refused VPN permission never starts the GW engine', () async {
    permission = false;
    final service = VpnService(platformSupported: true);
    addTearDown(service.dispose);
    expect(await service.connect(gwServer), isFalse);
    expect(service.errorMessage, 'vpn_permission_denied');
    expect(service.status, VpnStatus.disconnected);
    expect(vleeCalls, isNot(contains('connect')));
  });

  test('cancel answers at once and ignores the engine afterwards', () async {
    final service = VpnService(platformSupported: true);
    addTearDown(service.dispose);
    final attempt = service.connect(gwServer);
    await settle();
    sink!.success('STATE:CONNECTING');
    await settle();
    final cancelling = service.cancelConnect();
    expect(service.status, VpnStatus.disconnecting);
    await cancelling;
    expect(await attempt, isFalse);
    expect(service.status, VpnStatus.disconnected);
    sink!.success('STATE:DISCONNECTED');
    sink!.success('STATE:CONNECTED');
    await settle();
    expect(service.status, VpnStatus.disconnected);
    expect(service.errorMessage, isNull);
  });

  test('a connect that never resolves is stopped by the limit', () async {
    final service = VpnService(
      platformSupported: true,
      gwConnectTimeout: const Duration(milliseconds: 50),
    );
    addTearDown(service.dispose);
    final attempt = service.connect(gwServer);
    await settle();
    sink!.success('STATE:CONNECTING');
    expect(await attempt, isFalse);
    await settle();
    expect(service.errorMessage, 'awg_handshake_timeout');
    expect(vleeCalls, contains('disconnect'));
  });

  test('a tunnel that kept running is restored on initialize', () async {
    initializeResult = <String, String>{
      'protocol': 'vless',
      'state': 'CONNECTED',
    };
    final service = VpnService(platformSupported: true);
    addTearDown(service.dispose);
    expect(await service.initialize(), isTrue);
    expect(service.status, VpnStatus.connected);
    expect(service.restoredEngine, ServerProtocol.vless);
  });

  test('a restored GW tunnel follows the engine again', () async {
    initializeResult = <String, String>{'protocol': 'gw', 'state': 'CONNECTED'};
    replay = 'CONNECTED';
    final service = VpnService(platformSupported: true);
    addTearDown(service.dispose);
    await service.initialize();
    await settle();
    expect(service.status, VpnStatus.connected);
    sink!.success('STATE:DISCONNECTED');
    await settle();
    expect(service.status, VpnStatus.disconnected);
  });

  test('an old native side without a snapshot starts disconnected', () async {
    final service = VpnService(platformSupported: true);
    addTearDown(service.dispose);
    expect(await service.initialize(), isTrue);
    expect(service.status, VpnStatus.disconnected);
    expect(service.restoredEngine, isNull);
  });
}
