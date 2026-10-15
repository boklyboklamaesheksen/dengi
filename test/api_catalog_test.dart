import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rabochiy_vpn/config/api_config.dart';
import 'package:rabochiy_vpn/config/backend_signing.dart';
import 'package:rabochiy_vpn/services/api_host_service.dart';
import 'package:rabochiy_vpn/services/api_service.dart';
import 'package:rabochiy_vpn/services/gw_api_service.dart';

const signing = BackendSigning(secret: 'test-only-signing-value');
const record = {
  '_id': 'qa-awg',
  'country': 'QA',
  'ip_address': '192.0.2.1',
  'config': 'fixture',
};
http.Response catalogue([List<Object> data = const [record]]) =>
    http.Response(jsonEncode({'success': 1, 'data': data}), 200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ApiHostService.instance.resetForTest();
    ApiConfig.baseUrl = 'https://example.test';
    SharedPreferences.setMockInitialValues({
      ApiService.userIdPrefsKey: 'qa-account',
      ApiService.mnemonicPrefsKey: 'test-only recovery phrase',
    });
  });

  test('missing signing configuration fails before any HTTP request', () async {
    var requests = 0;
    final api = ApiService(
      signing: const BackendSigning(secret: ''),
      client: MockClient((_) async {
        requests++;
        return catalogue();
      }),
    );
    addTearDown(api.close);
    await expectLater(
      api.fetchServerConfigs(),
      throwsA(isA<BackendConfigurationException>()),
    );
    expect(requests, 0);
  });

  test(
    'AWG catalogue uses the backend signing contract and decodes servers',
    () async {
      final api = ApiService(
        signing: signing,
        client: MockClient((request) async {
          expect(request.url.path, '/vpn/api/v1/user/server_awg');
          final form = Uri.splitQueryString(request.body);
          expect(form['userId'], 'qa-account');
          expect(form['bundleId'], 'app.rabochiy.vpn');
          expect(
            form['hash'],
            sha256
                .convert(utf8.encode('${form['time']}|test-only-signing-value'))
                .toString(),
          );
          return catalogue();
        }),
      );
      addTearDown(api.close);
      final servers = await api.fetchServerConfigs();
      expect(servers.single.id, 'qa-awg');
      expect(servers.single.awgConfig, 'fixture');
    },
  );

  test(
    'Remote Config changes affect clients that were already created',
    () async {
      final hosts = <String>[];
      final api = ApiService(
        signing: signing,
        client: MockClient((request) async {
          hosts.add(request.url.host);
          return catalogue();
        }),
      );
      addTearDown(api.close);
      await api.fetchServerConfigs();
      expect(
        ApiHostService.instance.apply('https://backup.example.test/'),
        isTrue,
      );
      await api.fetchServerConfigs();
      expect(hosts, ['example.test', 'backup.example.test']);
    },
  );

  test(
    'explicit client base URL is not overwritten by Remote Config',
    () async {
      final api = ApiService(
        baseUrl: 'http://localhost:9999/',
        signing: signing,
        client: MockClient((request) async {
          expect(
            request.url.toString(),
            'http://localhost:9999/vpn/api/v1/user/server_awg',
          );
          return catalogue();
        }),
      );
      addTearDown(api.close);
      ApiHostService.instance.apply('https://backup.example.test');
      await api.fetchServerConfigs();
    },
  );

  test(
    'invalid Remote Config cannot downgrade HTTPS or insert credentials',
    () {
      for (final value in [
        '',
        'https://',
        'http://example.test',
        'https://user:pass@example.test',
        'https://example.test?token=bad',
        'https://example.test#fragment',
      ]) {
        expect(ApiHostService.instance.apply(value), isFalse, reason: value);
      }
      expect(ApiConfig.baseUrl, 'https://example.test');
    },
  );

  test('catalogue fetch never silently creates an account', () async {
    SharedPreferences.setMockInitialValues({});
    var requests = 0;
    final api = ApiService(
      signing: signing,
      client: MockClient((_) async {
        requests++;
        return catalogue();
      }),
    );
    addTearDown(api.close);
    expect(await api.fetchServerConfigs(), isEmpty);
    expect(requests, 0);
  });

  test('HTTP 200 with success=0 is an error, not an empty catalogue', () async {
    final api = ApiService(
      signing: signing,
      client: MockClient(
        (_) async => http.Response('{"success":0,"data":{}}', 200),
      ),
    );
    addTearDown(api.close);
    await expectLater(api.fetchServerConfigs(), throwsFormatException);
  });

  test('failed response does not destroy the last valid cache', () async {
    var failing = false;
    final api = ApiService(
      signing: signing,
      client: MockClient(
        (_) async => failing
            ? http.Response('{"success":0,"data":{}}', 200)
            : catalogue(),
      ),
    );
    addTearDown(api.close);
    await api.fetchServerConfigs();
    failing = true;
    expect((await api.fetchServerConfigs()).single.id, 'qa-awg');
  });

  test(
    'a successful empty catalogue clears servers instead of reviving cache',
    () async {
      var empty = false;
      final api = ApiService(
        signing: signing,
        client: MockClient((_) async => catalogue(empty ? [] : [record])),
      );
      addTearDown(api.close);
      await api.fetchServerConfigs();
      empty = true;
      expect(await api.fetchServerConfigs(), isEmpty);
    },
  );

  test(
    'cached credentials never cross account or backend boundaries',
    () async {
      var failing = false;
      final api = ApiService(
        signing: signing,
        client: MockClient((_) async {
          if (failing) throw http.ClientException('offline');
          return catalogue();
        }),
      );
      addTearDown(api.close);
      await api.fetchServerConfigs();
      failing = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(ApiService.userIdPrefsKey, 'other-qa-account');
      await expectLater(
        api.fetchServerConfigs(),
        throwsA(isA<http.ClientException>()),
      );
      await prefs.setString(ApiService.userIdPrefsKey, 'qa-account');
      ApiConfig.baseUrl = 'https://other.example.test';
      await expectLater(
        api.fetchServerConfigs(),
        throwsA(isA<http.ClientException>()),
      );
    },
  );

  test('server cache never stores the API address in plain text', () async {
    final api = ApiService(
      signing: signing,
      client: MockClient((_) async => catalogue()),
    );
    addTearDown(api.close);
    await api.fetchServerConfigs();
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('rabochiy_servers_cache_awg_v1')!;
    expect(cached, isNot(contains('example.test')));
  });

  test('legacy plain-text cache is dropped instead of reused', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'rabochiy_servers_cache_awg_v1',
      jsonEncode({
        'userId': 'qa-account',
        'baseUrl': 'https://example.test',
        'data': [record],
      }),
    );
    final api = ApiService(
      signing: signing,
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    addTearDown(api.close);
    await expectLater(
      api.fetchServerConfigs(),
      throwsA(isA<http.ClientException>()),
    );
    expect(prefs.getString('rabochiy_servers_cache_awg_v1'), isNull);
  });

  test('catalogue request fails over to the next backend', () async {
    ApiHostService.instance.apply('https://primary.example.test');
    final hosts = <String>[];
    final api = ApiService(
      signing: signing,
      client: MockClient((request) async {
        hosts.add(request.url.host);
        if (hosts.length == 1) throw http.ClientException('Failed host lookup');
        return catalogue();
      }),
    );
    addTearDown(api.close);
    expect((await api.fetchServerConfigs()).single.id, 'qa-awg');
    expect(hosts.first, 'primary.example.test');
    expect(hosts, hasLength(2));
    expect(hosts.last, isNot('primary.example.test'));
  });

  test(
    'a response completing after logout cannot repopulate the cache',
    () async {
      final response = Completer<http.Response>();
      final requested = Completer<void>();
      final api = ApiService(
        signing: signing,
        client: MockClient((_) {
          requested.complete();
          return response.future;
        }),
      );
      addTearDown(api.close);
      final loading = api.fetchServerConfigs();
      await requested.future;
      await api.logout();
      response.complete(catalogue());
      await loading;
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('rabochiy_servers_cache_awg_v1'), isNull);
    },
  );

  test('GW missing configuration and failed responses are surfaced', () async {
    final api = GwApiService(
      signing: const BackendSigning(secret: ''),
      client: MockClient((_) async => catalogue([])),
    );
    addTearDown(api.close);
    await expectLater(
      api.fetchServers(),
      throwsA(isA<BackendConfigurationException>()),
    );
    final rejected = GwApiService(
      signing: signing,
      client: MockClient(
        (_) async => http.Response('{"success":0,"data":[]}', 200),
      ),
    );
    addTearDown(rejected.close);
    await expectLater(rejected.fetchServers(), throwsFormatException);
  });

  test('GW catalogue signs and encodes the account and device key', () async {
    final api = GwApiService(
      signing: signing,
      client: MockClient((request) async {
        final form = Uri.splitQueryString(request.body);
        expect(form['userId'], 'qa-account');
        expect(form['pubkey']!.length, 128);
        expect(
          form['hash'],
          sha256
              .convert(utf8.encode('${form['time']}|test-only-signing-value'))
              .toString(),
        );
        return catalogue([]);
      }),
    );
    addTearDown(api.close);
    expect(await api.fetchServers(), isEmpty);
  });
}
