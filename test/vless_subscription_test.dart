import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rabochiy_vpn/config/secret_codec.dart';
import 'package:rabochiy_vpn/models/server_config_model.dart';
import 'package:rabochiy_vpn/providers/app_provider.dart';
import 'package:rabochiy_vpn/services/vless_subscription_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/catalog_fakes.dart';

const _uuid = '00000000-0000-4000-8000-000000000001';

String _link(String host, int port, String remark, {String query = ''}) =>
    'vless://$_uuid@$host:$port?encryption=none&security=reality&type=xhttp'
    '&sni=example.com&pbk=key&sid=ab&fp=chrome$query'
    '#${Uri.encodeComponent(remark)}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ServerConfig.fromVlessUri', () {
    test('takes name and flag from the remark', () {
      final server = ServerConfig.fromVlessUri(
        _link('203.0.113.7', 8443, '🇩🇪 Германия #3'),
      )!;
      expect(server.protocol, ServerProtocol.vless);
      expect(server.serverName, 'Германия #3');
      expect(server.country, 'Германия #3');
      expect(server.countryCode, 'DE');
      expect(server.flag, '🇩🇪');
      expect(server.address, '203.0.113.7');
      expect(server.port, 8443);
      expect(server.originalUrl, startsWith('vless://'));
      expect(server.premium, isFalse);
    });

    test('id ignores the remark so renames keep the selection', () {
      final a = ServerConfig.fromVlessUri(_link('h.example', 443, 'A'))!;
      final b = ServerConfig.fromVlessUri(_link('h.example', 443, 'B'))!;
      final c = ServerConfig.fromVlessUri(_link('h.example', 444, 'A'))!;
      expect(a.id, b.id);
      expect(a.id, isNot(c.id));
    });

    test('handles IPv6 hosts, missing remark and bad links', () {
      final v6 = ServerConfig.fromVlessUri(
        'vless://$_uuid@[2001:db8::1]:443?security=tls',
      )!;
      expect(v6.address, '2001:db8::1');
      expect(v6.serverName, '2001:db8::1');
      expect(v6.flag, '🌐');
      expect(ServerConfig.fromVlessUri('vmess://abc'), isNull);
      expect(ServerConfig.fromVlessUri('vless://host:443'), isNull);
      expect(ServerConfig.fromVlessUri('vless://$_uuid@host:99999'), isNull);
      expect(ServerConfig.fromVlessUri('vless://$_uuid@host'), isNull);
    });
  });

  group('subscription parsing', () {
    test('extracts vless links from plain and base64 bodies', () {
      final plain = [
        _link('a.example', 443, '🇷🇺 Белые списки #1'),
        'vmess://ignored',
        '',
        _link('b.example', 443, '🇷🇺 Белые списки #2'),
      ].join('\r\n');
      expect(VlessSubscriptionService.extractLinks(plain), hasLength(2));
      final encoded = base64.encode(utf8.encode(plain));
      expect(VlessSubscriptionService.extractLinks(encoded), hasLength(2));
      expect(
        VlessSubscriptionService.extractLinks('not a subscription'),
        isEmpty,
      );
    });

    test('keeps subscription order and drops duplicates', () {
      final servers = VlessSubscriptionService.toServers([
        _link('a.example', 443, '🇷🇺 Белые списки #1'),
        _link('b.example', 443, '🇷🇺 Белые списки #2'),
        _link('a.example', 443, 'duplicate'),
        'vless://broken',
        _link('c.example', 443, '🇩🇪 Германия #1'),
      ]);
      expect(servers.map((s) => s.serverName), [
        'Белые списки #1',
        'Белые списки #2',
        'Германия #1',
      ]);
    });
  });

  group('VlessSubscriptionSources', () {
    test('accepts only gwenc1 https URLs', () {
      final one = SecretCodec.encode('https://sub.example/bs');
      final two = SecretCodec.encode(
        'https://a.example/x\nhttps://b.example/y,http://plain.example',
      );
      expect(VlessSubscriptionSources.parse(one), ['https://sub.example/bs']);
      expect(
        VlessSubscriptionSources.parse('$one, $two https://plain.example'),
        [
          'https://sub.example/bs',
          'https://a.example/x',
          'https://b.example/y',
        ],
      );
      expect(VlessSubscriptionSources.parse('https://plain.example'), isEmpty);
    });

    test('built-in default decodes to a valid source', () {
      expect(VlessSubscriptionSources.instance.urls.value, isNotEmpty);
    });

    test('empty value disables, garbage is rejected', () {
      final sources = VlessSubscriptionSources.instance;
      final saved = sources.urls.value;
      addTearDown(() => sources.urls.value = saved);
      expect(sources.apply('garbage'), isFalse);
      expect(sources.urls.value, saved);
      expect(sources.apply(''), isTrue);
      expect(sources.urls.value, isEmpty);
      expect(
        sources.apply(SecretCodec.encode('https://sub.example/bs')),
        isTrue,
      );
      expect(sources.urls.value, ['https://sub.example/bs']);
    });
  });

  group('VlessSubscriptionService.fetchServers', () {
    late List<String> savedUrls;

    setUp(() {
      final sources = VlessSubscriptionSources.instance;
      savedUrls = sources.urls.value;
      sources.urls.value = ['https://sub.example/bs'];
    });
    tearDown(() => VlessSubscriptionSources.instance.urls.value = savedUrls);

    test('downloads, then falls back to the cache when offline', () async {
      final body = [
        _link('a.example', 443, '🇷🇺 Белые списки #1'),
        _link('b.example', 443, '🇩🇪 Германия #1'),
      ].join('\n');
      var online = true;
      final service = VlessSubscriptionService(
        client: MockClient((request) async {
          expect(request.url.toString(), 'https://sub.example/bs');
          return online
              ? http.Response.bytes(utf8.encode(body), 200)
              : http.Response('down', 503);
        }),
      );
      addTearDown(service.close);

      final fresh = await service.fetchServers();
      expect(fresh.map((s) => s.countryCode), ['RU', 'DE']);

      online = false;
      final cached = await service.fetchServers();
      expect(cached.map((s) => s.id), fresh.map((s) => s.id));
    });

    test('throws when offline without a cache', () async {
      final service = VlessSubscriptionService(
        client: MockClient((_) async => http.Response('down', 503)),
      );
      addTearDown(service.close);
      expect(
        service.fetchServers(),
        throwsA(isA<VlessSubscriptionException>()),
      );
    });
  });

  group('AppProvider', () {
    test('appends VLESS servers after AWG and GW', () async {
      final provider = AppProvider(
        apiService: FakeApi(fetch: () async => [awgServer]),
        gwApiService: FakeGwApi(fetch: () async => [gwServer]),
        vlessService: FakeVless(fetch: () async => [vlessServer]),
        autoInitialize: false,
      );
      addTearDown(provider.dispose);
      await provider.loadServers();
      expect(provider.servers, [awgServer, gwServer, vlessServer]);
      expect(provider.catalogError, isNull);
    });

    test('a VLESS-only failure keeps other servers and no error', () async {
      final provider = AppProvider(
        apiService: FakeApi(fetch: () async => [awgServer]),
        gwApiService: FakeGwApi(fetch: () async => [gwServer]),
        vlessService: FakeVless(
          fetch: () async => throw const VlessSubscriptionException(),
        ),
        autoInitialize: false,
      );
      addTearDown(provider.dispose);
      await provider.loadServers();
      expect(provider.servers, [awgServer, gwServer]);
      expect(provider.catalogError, isNull);
    });
  });
}
