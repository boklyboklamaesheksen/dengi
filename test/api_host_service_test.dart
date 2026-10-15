import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rabochiy_vpn/config/api_config.dart';
import 'package:rabochiy_vpn/config/secret_codec.dart';
import 'package:rabochiy_vpn/services/api_host_service.dart';

String? canonical(String raw) => ApiEndpoint.tryParse(raw)?.canonical;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiEndpoint.tryParse', () {
    test('normalises plain URLs', () {
      expect(canonical('https://API.Example.com/'), 'https://api.example.com');
      expect(
        canonical(' https://api.example.com:443// '),
        'https://api.example.com',
      );
      expect(
        canonical('https://api.example.com:8443'),
        'https://api.example.com:8443',
      );
      expect(canonical('api.example.com'), 'https://api.example.com');
      expect(canonical('https://203.0.113.7'), 'https://203.0.113.7');
    });

    test(
      'keeps a path prefix and cuts the API suffix the client adds itself',
      () {
        expect(
          canonical('https://h.example.com/prefix/'),
          'https://h.example.com/prefix',
        );
        expect(
          canonical('https://h.example.com/gw/vpn/api/v1/'),
          'https://h.example.com/gw',
        );
        expect(
          canonical('https://h.example.com/vpn/api/v3'),
          'https://h.example.com',
        );
        expect(
          canonical('https://h.example.com/VPN/API/v1/'),
          'https://h.example.com',
        );
      },
    );

    test('converts internationalised domains to punycode', () {
      expect(canonical('https://пример.рф'), 'https://xn--e1afmkfd.xn--p1ai');
      expect(
        canonical('https://Bücher.example'),
        'https://xn--bcher-kva.example',
      );
      expect(
        canonical('https://пример.рф/путь/'),
        'https://xn--e1afmkfd.xn--p1ai/%D0%BF%D1%83%D1%82%D1%8C',
      );
      expect(Punycode.encode('пример'), 'e1afmkfd');
    });

    test('accepts wildcard templates', () {
      final t = ApiEndpoint.tryParse('*.api.example.com')!;
      expect(t.isTemplate, isTrue);
      expect(t.canonical, 'https://*.api.example.com');
      expect(t.build('k3x9'), 'https://k3x9.api.example.com');
      expect(t.owns('https://k3x9.api.example.com'), isTrue);
      expect(t.owns('https://a.b.api.example.com'), isFalse);
      expect(t.owns('https://k3x9.other.example.com'), isFalse);
      expect(
        canonical('https://*.api.example.com:8443/gw/vpn/api/v1/'),
        'https://*.api.example.com:8443/gw',
      );
    });

    test('rejects unsafe or malformed values', () {
      for (final value in [
        '',
        '   ',
        'https://',
        'http://example.test',
        'ftp://example.test',
        'https://user:pass@example.test',
        'https://example.test?token=bad',
        'https://example.test#fragment',
        'https://exa mple.test',
        'https://*.com',
        'https://a*.example.com',
        'https://api.*.example.com',
        'https://example.test:0',
        'https://example.test:99999',
        'https://-bad-.example.test',
        'https://[::1]',
      ]) {
        expect(ApiEndpoint.tryParse(value), isNull, reason: value);
      }
    });
  });

  group('ApiHostService', () {
    late ApiHostService service;
    late String defaultBase;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = ApiHostService(random: Random(7));
      defaultBase = ApiEndpoint.tryParse(ApiConfig.defaultBaseUrl)!.canonical;
      ApiConfig.baseUrl = defaultBase;
    });

    Future<Map<String, Object>> storedPrefs() async {
      await pumpEventQueue();
      final prefs = await SharedPreferences.getInstance();
      return {for (final k in prefs.getKeys()) k: prefs.get(k)!};
    }

    test('restore without saved state uses the encoded default', () async {
      ApiConfig.baseUrl = 'https://stale.example.com';
      await service.restore();
      expect(ApiConfig.baseUrl, defaultBase);
      expect(service.hasRemoteSource, isFalse);
    });

    test('applied address is persisted only in gwenc1 form', () async {
      expect(service.apply('https://new.example.com/'), isTrue);
      expect(ApiConfig.baseUrl, 'https://new.example.com');
      expect(service.hasRemoteSource, isTrue);

      final prefs = await storedPrefs();
      expect(prefs.values.join(' '), isNot(contains('example')));
      expect(prefs['api_host_source_enc'], startsWith(SecretCodec.prefix));

      final restored = ApiHostService(random: Random(1));
      ApiConfig.baseUrl = defaultBase;
      await restored.restore();
      expect(ApiConfig.baseUrl, 'https://new.example.com');
      expect(restored.hasRemoteSource, isTrue);
    });

    test('invalid values do not change the current address', () {
      expect(service.apply('http://downgrade.example.com'), isFalse);
      expect(service.apply('gwenc1:%%%'), isFalse);
      expect(ApiConfig.baseUrl, defaultBase);
    });

    test('wildcard template gets a stable random label', () async {
      expect(service.apply('*.api.example.com'), isTrue);
      final first = ApiConfig.baseUrl;
      expect(
        first,
        matches(RegExp(r'^https://[a-z][a-z0-9]{11}\.api\.example\.com$')),
      );
      await pumpEventQueue();

      final restored = ApiHostService(random: Random(99));
      await restored.restore();
      expect(ApiConfig.baseUrl, first);
    });

    test(
      'connection failure on a plain URL fails over to the default',
      () async {
        service.apply('https://new.example.com');
        final hosts = <String>[];
        final response = await service.withFailover((base) async {
          hosts.add(base);
          if (hosts.length == 1) {
            throw const SocketException('Failed host lookup');
          }
          return http.Response('ok', 200);
        });
        expect(response.statusCode, 200);
        expect(hosts, ['https://new.example.com', defaultBase]);
        expect(ApiConfig.baseUrl, defaultBase);
      },
    );

    test('failover cycles primary → default → reserve → primary', () {
      service.apply('https://primary.example.com');
      service.applyReserve('https://reserve.example.com');
      expect(service.switchHost('https://primary.example.com'), isTrue);
      expect(ApiConfig.baseUrl, defaultBase);
      expect(service.switchHost(defaultBase), isTrue);
      expect(ApiConfig.baseUrl, 'https://reserve.example.com');
      expect(service.switchHost('https://reserve.example.com'), isTrue);
      expect(ApiConfig.baseUrl, 'https://primary.example.com');
    });

    test('a concurrent switch is not repeated', () {
      service.apply('https://primary.example.com');
      expect(service.switchHost('https://primary.example.com'), isTrue);
      expect(service.switchHost('https://primary.example.com'), isTrue);
      expect(ApiConfig.baseUrl, defaultBase);
    });

    test('re-applying the same value keeps an active failover', () {
      service.apply('https://primary.example.com');
      service.switchHost('https://primary.example.com');
      service.apply('https://primary.example.com');
      expect(ApiConfig.baseUrl, defaultBase);
      service.apply('https://changed.example.com');
      expect(ApiConfig.baseUrl, 'https://changed.example.com');
    });

    test('template failures rotate the label, then move on', () {
      service.apply('*.api.example.com');
      final template = ApiEndpoint.tryParse('*.api.example.com')!;
      final first = ApiConfig.baseUrl;
      expect(service.switchHost(first), isTrue);
      final second = ApiConfig.baseUrl;
      expect(second, isNot(first));
      expect(template.owns(second), isTrue);
      expect(service.switchHost(second), isTrue);
      expect(template.owns(ApiConfig.baseUrl), isTrue);
      expect(service.switchHost(ApiConfig.baseUrl), isTrue);
      expect(ApiConfig.baseUrl, defaultBase);
    });

    test('non-idempotent requests are retried only if never sent', () async {
      service.apply('https://primary.example.com');
      var calls = 0;
      await expectLater(
        service.withFailover((base) async {
          calls++;
          throw TimeoutException('slow');
        }, idempotent: false),
        throwsA(isA<TimeoutException>()),
      );
      expect(calls, 1);
      // The next request still goes to the other host.
      expect(ApiConfig.baseUrl, defaultBase);

      calls = 0;
      final response = await service.withFailover((base) async {
        calls++;
        if (calls == 1) {
          throw http.ClientException('Connection refused');
        }
        return http.Response('ok', 200);
      }, idempotent: false);
      expect(response.statusCode, 200);
      expect(calls, 2);
    });

    test(
      'business errors stay with the caller, gateway errors fail over',
      () async {
        service.apply('https://primary.example.com');
        var calls = 0;
        final notFound = await service.withFailover((_) async {
          calls++;
          return http.Response('', 404);
        });
        expect(notFound.statusCode, 404);
        expect(calls, 1);
        expect(ApiConfig.baseUrl, 'https://primary.example.com');

        final hosts = <String>[];
        final ok = await service.withFailover((base) async {
          hosts.add(base);
          return http.Response('', hosts.length == 1 ? 502 : 200);
        });
        expect(ok.statusCode, 200);
        expect(hosts, ['https://primary.example.com', defaultBase]);
      },
    );

    test('non-network errors are not swallowed', () async {
      await expectLater(
        service.withFailover((_) async => throw const FormatException('bad')),
        throwsFormatException,
      );
      expect(ApiConfig.baseUrl, defaultBase);
    });

    test('backend key ignores wildcard labels', () {
      service.apply('*.api.example.com');
      final key = service.backendKey(ApiConfig.baseUrl);
      service.switchHost(ApiConfig.baseUrl);
      expect(service.backendKey('${ApiConfig.baseUrl}/'), key);
      expect(
        service.backendKey('https://elsewhere.example.com'),
        'https://elsewhere.example.com',
      );
    });

    test('reserve is persisted encoded and can be cleared', () async {
      expect(service.applyReserve('https://reserve.example.com'), isTrue);
      var prefs = await storedPrefs();
      expect(prefs['api_host_reserve_enc'], startsWith(SecretCodec.prefix));
      expect(service.applyReserve('not a url'), isFalse);
      expect(service.applyReserve(''), isTrue);
      prefs = await storedPrefs();
      expect(prefs.containsKey('api_host_reserve_enc'), isFalse);
    });
  });
}
