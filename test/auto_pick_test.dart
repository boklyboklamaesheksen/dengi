import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rabochiy_vpn/models/server_config_model.dart';
import 'package:rabochiy_vpn/providers/app_provider.dart';
import 'package:rabochiy_vpn/services/auto_pick.dart';
import 'package:rabochiy_vpn/services/vpn_service.dart';

import 'support/catalog_fakes.dart';

const awgA = ServerConfig(
  id: 'awg-a',
  serverName: 'AWG A',
  address: '192.0.2.21',
  port: 51820,
  recommend: true,
);
const awgB = ServerConfig(
  id: 'awg-b',
  serverName: 'AWG B',
  address: '192.0.2.22',
  port: 51820,
);
const proAwg = ServerConfig(
  id: 'awg-pro',
  serverName: 'AWG PRO',
  address: '192.0.2.23',
  port: 51820,
  premium: true,
);
const gwC = ServerConfig(
  id: 'gw-c',
  serverName: 'GW C',
  address: '192.0.2.24',
  port: 443,
  protocol: ServerProtocol.gw,
  gwRawConfig: '{"test":true}',
);
final vlessD = vlessServer;

enum Outcome { ok, fail, hang }

/// Engine double: each connect ends as scripted per server, statuses are
/// published like the real bridge (only on change).
class ScriptedVpn extends VpnService {
  ScriptedVpn(this.script) : super(platformSupported: false);

  final Map<String, List<Outcome>> script;
  bool permission = true;
  final List<String> calls = <String>[];
  final List<VpnStatus> published = <VpnStatus>[];
  VpnStatus _current = VpnStatus.disconnected;
  String? _error;
  Completer<bool>? _hanging;
  final StreamController<VpnStatus> _statuses =
      StreamController<VpnStatus>.broadcast();

  @override
  Stream<VpnStatus> get statusStream => _statuses.stream;
  @override
  Stream<EngineStatus> get engineStatusStream => const Stream.empty();
  @override
  VpnStatus get status => _current;
  @override
  String? get errorMessage => _error;
  @override
  Future<bool> initialize() async => true;

  void _emit(VpnStatus status) {
    if (_current == status) return;
    _current = status;
    published.add(status);
    _statuses.add(status);
  }

  void _releaseHanging() {
    final hanging = _hanging;
    _hanging = null;
    if (hanging != null && !hanging.isCompleted) hanging.complete(false);
  }

  @override
  Future<bool> ensurePermission() async {
    calls.add('permission');
    return permission;
  }

  @override
  Future<bool> connect(
    ServerConfig config, {
    List<String>? blockedApps,
    List<String>? excludedApps,
    List<String>? allowedApps,
  }) async {
    calls.add('connect:${config.id}');
    _error = null;
    _emit(VpnStatus.connecting);
    final steps = script[config.id];
    final outcome = steps == null || steps.isEmpty
        ? Outcome.fail
        : steps.removeAt(0);
    switch (outcome) {
      case Outcome.ok:
        _emit(VpnStatus.connected);
        return true;
      case Outcome.fail:
        _error = 'awg_handshake_timeout';
        _emit(VpnStatus.error);
        return false;
      case Outcome.hang:
        _hanging = Completer<bool>();
        return _hanging!.future;
    }
  }

  @override
  Future<void> cancelConnect() async {
    calls.add('cancel');
    _releaseHanging();
    _error = null;
    _emit(VpnStatus.disconnecting);
    _emit(VpnStatus.disconnected);
  }

  @override
  Future<bool> disconnect() async {
    calls.add('disconnect');
    _releaseHanging();
    _emit(VpnStatus.disconnecting);
    _emit(VpnStatus.disconnected);
    return true;
  }

  @override
  void dispose() {
    _statuses.close();
    super.dispose();
  }
}

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('autoPickOrder', () {
    test('skips servers the account cannot use and alternates protocols', () {
      final order = autoPickOrder(<ServerConfig>[
        awgA,
        awgB,
        proAwg,
        gwC,
        vlessD,
      ], isPremium: false);
      expect(order.map((s) => s.id), <String>[
        'awg-a',
        'gw-c',
        vlessD.id,
        'awg-b',
      ]);
    });

    test('PRO accounts get PRO servers; the last working one goes first', () {
      final order = autoPickOrder(
        <ServerConfig>[awgA, awgB, proAwg, gwC],
        isPremium: true,
        lastWorkingId: 'awg-b',
      );
      expect(order.map((s) => s.id), <String>[
        'awg-b',
        'awg-a',
        'gw-c',
        'awg-pro',
      ]);
    });

    test('locked PRO VLESS entries without a link are never tried', () {
      final locked = ServerConfig.lockedVless(
        digest: '0123456789abcdef',
        remark: '🇩🇪 Germany',
      )!;
      final order = autoPickOrder(<ServerConfig>[
        locked.copyWith(premium: true),
        awgA,
      ], isPremium: true);
      expect(order.map((s) => s.id), <String>['awg-a']);
    });
  });

  group('auto server pick', () {
    Future<(AppProvider, ScriptedVpn)> started(
      Map<String, List<Outcome>> script, {
      bool online = true,
      Duration budget = const Duration(seconds: 35),
    }) async {
      final vpn = ScriptedVpn(script);
      final provider = AppProvider(
        apiService: FakeApi(fetch: () async => [awgA, awgB, proAwg]),
        gwApiService: FakeGwApi(fetch: () async => [gwC]),
        vlessService: FakeVless(fetch: () async => [vlessD]),
        vpnService: vpn,
        autoPickAttemptTimeout: budget,
        autoPickSettle: Duration.zero,
        internetProbe: () async => online,
      );
      addTearDown(provider.dispose);
      await settle();
      await provider.loadServers();
      await settle();
      return (provider, vpn);
    }

    test(
      'tries servers until one works, stays on it and remembers it',
      () async {
        final (provider, vpn) = await started({
          'awg-a': [Outcome.fail, Outcome.fail],
          'gw-c': [Outcome.fail, Outcome.fail],
          vlessD.id: [Outcome.ok],
        });
        expect(provider.isAutoSelect, isTrue);
        final seen = <VpnStatus>[];
        provider.addListener(() => seen.add(provider.vpnStatus));

        await provider.connectVpn();

        expect(vpn.calls, <String>[
          'permission',
          'connect:awg-a',
          'connect:awg-a',
          'connect:gw-c',
          'connect:gw-c',
          'connect:${vlessD.id}',
        ]);
        expect(vpn.published, contains(VpnStatus.error));
        expect(
          seen,
          everyElement(
            isIn(<VpnStatus>[VpnStatus.connecting, VpnStatus.connected]),
          ),
          reason: 'per-server failures never reach the UI',
        );
        expect(provider.vpnStatus, VpnStatus.connected);
        expect(provider.errorMessage, isNull);
        expect(provider.autoPick, isNull);
        expect(provider.isAutoSelect, isTrue);
        expect(provider.selectedServer?.id, vlessD.id);
        expect(provider.lastWorkingServerId, vlessD.id);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('rabochiy_auto_last_working_v1'), vlessD.id);
      },
    );

    test('reports progress while it searches', () async {
      final (provider, _) = await started({
        'awg-a': [Outcome.hang],
      });
      unawaited(provider.connectVpn());
      await until(() => provider.autoPick?.current == 1);
      expect(provider.autoPick?.total, 4);
      expect(provider.autoPick?.server?.id, 'awg-a');
      expect(provider.selectedServer?.id, 'awg-a');
      expect(provider.vpnStatus, VpnStatus.connecting);
      await provider.cancelConnect();
    });

    test('next time the last working server goes first; a dead one hands '
        'over to the search', () async {
      SharedPreferences.setMockInitialValues({
        'rabochiy_auto_last_working_v1': 'gw-c',
      });
      final (provider, vpn) = await started({
        'gw-c': [Outcome.fail, Outcome.fail],
        'awg-a': [Outcome.ok],
      });
      expect(
        provider.selectedServer?.id,
        'gw-c',
        reason: 'shown before connect',
      );

      await provider.connectVpn();

      expect(vpn.calls, <String>[
        'permission',
        'connect:gw-c',
        'connect:gw-c',
        'connect:awg-a',
      ]);
      expect(provider.vpnStatus, VpnStatus.connected);
      expect(provider.lastWorkingServerId, 'awg-a');
    });

    test('a working last server connects at once', () async {
      SharedPreferences.setMockInitialValues({
        'rabochiy_auto_last_working_v1': 'awg-b',
      });
      final (provider, vpn) = await started({
        'awg-b': [Outcome.ok],
      });
      await provider.connectVpn();
      expect(vpn.calls, <String>['permission', 'connect:awg-b']);
      expect(provider.selectedServer?.id, 'awg-b');
    });

    test('when every server fails the user gets one clear error', () async {
      final (provider, vpn) = await started({});
      await provider.connectVpn();
      expect(vpn.calls.where((c) => c.startsWith('connect:')).toSet(), <String>{
        'connect:awg-a',
        'connect:gw-c',
        'connect:${vlessD.id}',
        'connect:awg-b',
      }, reason: 'the free account never tries the PRO server');
      expect(provider.vpnStatus, VpnStatus.error);
      expect(provider.errorMessage, 'auto_pick_failed');
      expect(provider.autoPick, isNull);
      expect(provider.lastWorkingServerId, isNull);
    });

    test('without a network nothing is tried', () async {
      final (provider, vpn) = await started({}, online: false);
      await provider.connectVpn();
      expect(vpn.calls, isEmpty);
      expect(provider.errorMessage, 'no_internet');
      expect(provider.vpnStatus, VpnStatus.disconnected);
    });

    test('refused VPN consent stops the search before any server', () async {
      final (provider, vpn) = await started({});
      vpn.permission = false;
      await provider.connectVpn();
      expect(vpn.calls, <String>['permission']);
      expect(provider.errorMessage, 'vpn_permission_denied');
      expect(provider.vpnStatus, VpnStatus.disconnected);
    });

    test('cancel ends the search for good', () async {
      final (provider, vpn) = await started({
        'awg-a': [Outcome.hang],
      });
      final search = provider.connectVpn();
      await until(() => vpn.calls.contains('connect:awg-a'));

      await provider.cancelConnect();
      await search;
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(vpn.calls, <String>['permission', 'connect:awg-a', 'cancel']);
      expect(provider.vpnStatus, VpnStatus.disconnected);
      expect(provider.errorMessage, isNull);
      expect(provider.autoPick, isNull);
    });

    test('a server that hangs is dropped after its budget', () async {
      final (provider, vpn) = await started({
        'awg-a': [Outcome.hang],
        'gw-c': [Outcome.ok],
      }, budget: const Duration(milliseconds: 100));
      await provider.connectVpn();
      expect(vpn.calls, <String>[
        'permission',
        'connect:awg-a',
        'cancel',
        'connect:gw-c',
      ]);
      expect(provider.vpnStatus, VpnStatus.connected);
      expect(provider.selectedServer?.id, 'gw-c');
    });

    test('picking a server by hand ends the search', () async {
      final (provider, vpn) = await started({
        'awg-a': [Outcome.hang],
        'awg-b': [Outcome.ok],
      });
      final search = provider.connectVpn();
      await until(() => vpn.calls.contains('connect:awg-a'));

      provider.selectServer(awgB);
      await search;
      await until(() => provider.vpnStatus == VpnStatus.connected);

      expect(vpn.calls, <String>[
        'permission',
        'connect:awg-a',
        'disconnect',
        'connect:awg-b',
      ]);
      expect(provider.isAutoSelect, isFalse);
      expect(provider.selectedServer?.id, 'awg-b');
      expect(provider.autoPick, isNull);
    });

    test(
      'a manual attempt handed over to auto-pick is searched once',
      () async {
        final (provider, vpn) = await started({
          'awg-b': [Outcome.hang],
        });
        provider.selectServer(awgB);
        final manual = provider.connectVpn();
        await until(() => vpn.calls.contains('connect:awg-b'));

        provider.toggleAutoSelect();
        await manual;
        await until(() => provider.errorMessage == 'auto_pick_failed');
        // The reconnect's own quick-failure retry would start over after 1.5 s.
        await Future<void>.delayed(const Duration(seconds: 2));

        final connects = vpn.calls.where((c) => c.startsWith('connect:'));
        expect(connects.length, 1 + 4 * 2, reason: 'each server tried twice');
        expect(provider.vpnStatus, VpnStatus.error);
        expect(provider.autoPick, isNull);
      },
    );

    test('switching to auto keeps a working manual tunnel', () async {
      final (provider, vpn) = await started({
        'awg-b': [Outcome.ok],
      });
      provider.selectServer(awgB);
      await provider.connectVpn();
      await settle();
      expect(provider.vpnStatus, VpnStatus.connected);
      vpn.calls.clear();

      provider.toggleAutoSelect();
      await settle();

      expect(vpn.calls, isEmpty);
      expect(provider.isAutoSelect, isTrue);
      expect(provider.vpnStatus, VpnStatus.connected);
      expect(provider.lastWorkingServerId, 'awg-b');
    });

    test('logging out forgets the working server', () async {
      final (provider, _) = await started({
        'awg-a': [Outcome.ok],
      });
      await provider.connectVpn();
      expect(provider.lastWorkingServerId, 'awg-a');
      await provider.resetSession();
      await settle();
      expect(provider.lastWorkingServerId, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('rabochiy_auto_last_working_v1'), isNull);
    });
  });
}
