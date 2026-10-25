import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rabochiy_vpn/models/server_config_model.dart';
import 'package:rabochiy_vpn/providers/app_provider.dart';
import 'package:rabochiy_vpn/services/api_service.dart';
import 'package:rabochiy_vpn/services/traffic_stats_service.dart';
import 'package:rabochiy_vpn/services/vpn_service.dart';

import 'support/catalog_fakes.dart';

const freeA = ServerConfig(
  id: 'free-a',
  serverName: 'Free A',
  address: '192.0.2.10',
  port: 51820,
  recommend: true,
);
const freeB = ServerConfig(
  id: 'free-b',
  serverName: 'Free B',
  address: '192.0.2.11',
  port: 51820,
);
const proC = ServerConfig(
  id: 'pro-c',
  serverName: 'PRO C',
  address: '192.0.2.12',
  port: 51820,
  premium: true,
);

/// Engine double: records calls, statuses are driven by the test.
class RecordingVpn extends VpnService {
  RecordingVpn({this.restored}) : super(platformSupported: false);

  final ServerProtocol? restored;
  final List<String> calls = <String>[];
  VpnStatus _current = VpnStatus.disconnected;
  final StreamController<VpnStatus> _statuses =
      StreamController<VpnStatus>.broadcast();
  final StreamController<EngineStatus> _engine =
      StreamController<EngineStatus>.broadcast();

  @override
  ServerProtocol? get restoredEngine => restored;
  @override
  Stream<VpnStatus> get statusStream => _statuses.stream;
  @override
  Stream<EngineStatus> get engineStatusStream => _engine.stream;
  @override
  VpnStatus get status => _current;
  @override
  Future<bool> initialize() async => true;

  void emit(VpnStatus status) {
    _current = status;
    _statuses.add(status);
  }

  void traffic(int totalBytes) => _engine.add(
    EngineStatus(
      state: 'CONNECTED',
      duration: 0,
      downloadSpeed: 0,
      uploadSpeed: 0,
      download: totalBytes,
      upload: 0,
    ),
  );

  final List<ServerConfig> connected = <ServerConfig>[];

  @override
  Future<bool> connect(
    ServerConfig config, {
    List<String>? blockedApps,
    List<String>? excludedApps,
    List<String>? allowedApps,
  }) async {
    calls.add('connect:${config.id}');
    connected.add(config);
    emit(VpnStatus.connected);
    return true;
  }

  @override
  Future<bool> disconnect() async {
    calls.add('disconnect');
    emit(VpnStatus.disconnected);
    return true;
  }

  @override
  Future<void> cancelConnect() async {
    calls.add('cancel');
    emit(VpnStatus.disconnected);
  }

  @override
  void dispose() {
    _statuses.close();
    _engine.close();
    super.dispose();
  }
}

class PremiumApi extends FakeApi {
  PremiumApi({required super.fetch, this.premium = false});
  bool premium;

  @override
  Future<UserState?> refreshUserState() async =>
      UserState(userId: 'u1', isPremium: premium);
}

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<(AppProvider, RecordingVpn, PremiumApi)> started({
    List<ServerConfig> servers = const <ServerConfig>[freeA, freeB, proC],
    ServerProtocol? restored,
    bool premium = false,
  }) async {
    final api = PremiumApi(fetch: () async => servers, premium: premium);
    final vpn = RecordingVpn(restored: restored);
    final provider = AppProvider(
      apiService: api,
      gwApiService: FakeGwApi(fetch: () async => const <ServerConfig>[]),
      vlessService: FakeVless(),
      vpnService: vpn,
    );
    addTearDown(provider.dispose);
    await settle();
    await provider.loadServers();
    await provider.refreshUserState();
    await settle();
    return (provider, vpn, api);
  }

  test(
    'a free account picking a PRO server keeps its working tunnel',
    () async {
      final (provider, vpn, _) = await started();
      provider.selectServer(freeB);
      await provider.connectVpn();
      expect(vpn.calls, <String>['connect:free-b']);

      provider.selectServer(proC);
      await settle();
      expect(provider.isLockedForUser(proC), isTrue);
      expect(vpn.calls, <String>['connect:free-b']);
      expect(provider.selectedServer?.id, 'free-b');
      expect(provider.vpnStatus, VpnStatus.connected);
    },
  );

  test('a PRO account switches to the PRO server', () async {
    final (provider, vpn, _) = await started(premium: true);
    expect(provider.isPremium, isTrue);
    provider.selectServer(freeB);
    await provider.connectVpn();
    provider.selectServer(proC);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(vpn.calls, <String>[
      'connect:free-b',
      'disconnect',
      'connect:pro-c',
    ]);
  });

  test(
    'reloading the catalogue never re-points a connected auto pick',
    () async {
      var servers = const <ServerConfig>[freeA, freeB];
      final api = PremiumApi(fetch: () async => servers);
      final vpn = RecordingVpn();
      final provider = AppProvider(
        apiService: api,
        gwApiService: FakeGwApi(fetch: () async => const <ServerConfig>[]),
        vlessService: FakeVless(),
        vpnService: vpn,
      );
      addTearDown(provider.dispose);
      await settle();
      await provider.loadServers();
      expect(provider.selectedServer?.id, 'free-a');
      await provider.connectVpn();

      servers = <ServerConfig>[
        freeA.copyWith(recommend: false),
        freeB.copyWith(recommend: true),
      ];
      await provider.loadServers();
      expect(provider.selectedServer?.id, 'free-a', reason: 'tunnel uses A');

      await provider.disconnectVpn();
      await provider.loadServers();
      expect(
        provider.selectedServer?.id,
        'free-a',
        reason: 'auto-pick starts with the last server that worked',
      );
    },
  );

  test('a tunnel kept running while the UI was gone is restored', () async {
    final since = DateTime.now().subtract(const Duration(minutes: 3));
    SharedPreferences.setMockInitialValues({
      'rabochiy_vpn_session_v1': jsonEncode(<String, Object>{
        'server': 'free-b',
        'auto': false,
        'since': since.millisecondsSinceEpoch,
      }),
    });
    final (provider, vpn, _) = await started(restored: ServerProtocol.awg);
    expect(provider.selectedServer?.id, 'free-a');

    vpn.emit(VpnStatus.connected);
    await settle();
    expect(provider.vpnStatus, VpnStatus.connected);
    expect(provider.selectedServer?.id, 'free-b');
    expect(provider.isAutoSelect, isFalse);
    expect(provider.connectionDuration.inSeconds, greaterThanOrEqualTo(179));

    // The first sample is the whole session, already counted before.
    vpn.traffic(5 * 1024 * 1024);
    await settle();
    expect(provider.sessionRxBytes, 5 * 1024 * 1024);
    expect(provider.trafficStats.summaryFor(TrafficPeriod.all).totalBytes, 0);
    vpn.traffic(6 * 1024 * 1024);
    await settle();
    expect(
      provider.trafficStats.summaryFor(TrafficPeriod.all).totalBytes,
      1024 * 1024,
    );
    expect(vpn.calls, isEmpty, reason: 'nothing was reconnected');
  });

  test(
    'a fresh connect stores the session and a disconnect clears it',
    () async {
      final (provider, vpn, _) = await started();
      provider.selectServer(freeB);
      await provider.connectVpn();
      await settle();
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(
        prefs.getString('rabochiy_vpn_session_v1')!,
      ) as Map<String, dynamic>;
      expect(saved['server'], 'free-b');
      expect(saved['auto'], isFalse);
      await provider.disconnectVpn();
      await settle();
      expect(prefs.getString('rabochiy_vpn_session_v1'), isNull);
    },
  );

  test('a locked PRO VLESS entry is refreshed before connecting', () async {
    const link =
        'vless://00000000-0000-4000-8000-000000000042@192.0.2.40:443'
        '?security=tls&type=ws#%F0%9F%87%A9%F0%9F%87%AA%20Germany%20%231';
    final unlocked = ServerConfig.fromVlessUri(link)!.copyWith(premium: true);
    final locked = ServerConfig.lockedVless(
      digest: unlocked.id.substring('vless_'.length),
      remark: '🇩🇪 Germany #1',
    )!;
    expect(locked.id, unlocked.id);
    expect(locked.isLocked, isTrue);

    var vless = <ServerConfig>[locked];
    final api = PremiumApi(fetch: () async => const <ServerConfig>[]);
    final vpn = RecordingVpn();
    final provider = AppProvider(
      apiService: api,
      gwApiService: FakeGwApi(fetch: () async => const <ServerConfig>[]),
      vlessService: FakeVless(fetch: () async => vless),
      vpnService: vpn,
    );
    addTearDown(provider.dispose);
    await settle();
    await provider.loadServers();
    // The account just turned PRO; the reload still saw the locked entry.
    api.premium = true;
    await provider.refreshUserState();
    await settle();
    expect(provider.isPremium, isTrue);
    provider.selectServer(locked);
    expect(provider.selectedServer?.isLocked, isTrue);
    vless = <ServerConfig>[unlocked];
    await provider.connectVpn();
    expect(vpn.connected.single.originalUrl, link);
  });
}
