import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rabochiy_vpn/config/backend_signing.dart';
import 'package:rabochiy_vpn/models/server_config_model.dart';
import 'package:rabochiy_vpn/providers/app_provider.dart';

import 'support/catalog_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  AppProvider provider(FakeApi awg, FakeGwApi gw) {
    final value = AppProvider(
      apiService: awg,
      gwApiService: gw,
      autoInitialize: false,
    );
    addTearDown(value.dispose);
    return value;
  }

  test('AWG failure does not hide working GW servers', () async {
    final state = provider(
      FakeApi(fetch: () async => throw Exception('AWG unavailable')),
      FakeGwApi(fetch: () async => [gwServer]),
    );
    await state.loadServers();
    expect(state.servers, [gwServer]);
    expect(state.catalogError, 'load_servers_failed');
    expect(state.isLoading, isFalse);
  });

  test('GW failure does not hide working AWG servers', () async {
    final state = provider(
      FakeApi(fetch: () async => [awgServer]),
      FakeGwApi(fetch: () async => throw Exception('GW unavailable')),
    );
    await state.loadServers();
    expect(state.servers, [awgServer]);
    expect(state.catalogError, 'load_servers_failed');
  });

  test(
    'configuration error is explicit and clears on successful retry',
    () async {
      final api = FakeApi(
        fetch: () async => throw const BackendConfigurationException(),
      );
      final state = provider(api, FakeGwApi(fetch: () async => []));
      await state.loadServers();
      expect(state.catalogError, 'api_not_configured');
      api.fetch = () async => [awgServer];
      await state.loadServers();
      expect(state.catalogError, isNull);
      expect(state.servers, [awgServer]);
    },
  );

  test('concurrent refreshes share one request and do not race', () async {
    final response = Completer<List<ServerConfig>>();
    final api = FakeApi(fetch: () => response.future);
    final state = provider(api, FakeGwApi(fetch: () async => []));
    final first = state.loadServers();
    final second = state.loadServers();
    expect(identical(first, second), isTrue);
    expect(api.fetchCount, 1);
    response.complete([awgServer]);
    await Future.wait([first, second]);
    expect(state.servers, [awgServer]);
  });

  test('late catalogue response cannot restore a logged-out session', () async {
    final response = Completer<List<ServerConfig>>();
    final state = provider(
      FakeApi(fetch: () => response.future),
      FakeGwApi(fetch: () async => []),
    );
    final loading = state.loadServers();
    await state.resetSession();
    response.complete([awgServer]);
    await loading;
    expect(state.servers, isEmpty);
    expect(state.selectedServer, isNull);
    expect(state.isLoading, isFalse);
  });

  test('removed selected server is not kept with stale credentials', () async {
    final api = FakeApi(fetch: () async => [awgServer]);
    final state = provider(api, FakeGwApi(fetch: () async => []));
    await state.loadServers();
    state.selectServer(awgServer);
    api.fetch = () async => [];
    await state.loadServers();
    expect(state.selectedServer, isNull);
  });

  test(
    'automatic selection prefers accessible servers for free users',
    () async {
      final premium = awgServer.copyWith(
        id: 'paid',
        premium: true,
        recommend: true,
        priority: 100,
      );
      final state = provider(
        FakeApi(fetch: () async => [premium, awgServer]),
        FakeGwApi(fetch: () async => []),
      );
      await state.loadServers();
      expect(state.selectedServer, awgServer);
    },
  );

  test('copying a GW server preserves its decrypted configuration', () {
    expect(gwServer.copyWith(ping: 25).gwRawConfig, gwServer.gwRawConfig);
  });
}
