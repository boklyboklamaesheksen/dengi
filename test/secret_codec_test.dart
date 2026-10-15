import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rabochiy_vpn/config/api_config.dart';
import 'package:rabochiy_vpn/config/secret_codec.dart';
import 'package:rabochiy_vpn/services/api_host_service.dart';

void main() {
  group('SecretCodec (gwenc1)', () {
    test('matches the reference Python encoder byte for byte', () {
      // Vectors produced by the reference script from the GW/VLESS apps.
      expect(
        SecretCodec.encode('https://новый-урл.example.com/путь/'),
        'gwenc1:oyUdVUpCO0RQn4Geb9KvxnaGzV+2pRHlABknXLk/ROsVUx4hSTg81Gm0l7tijLw=',
      );
      expect(
        SecretCodec.encode('https://api.example.com'),
        'gwenc1:q1+HXXGUpMVlmdGxsnPL1Gm0l7tijLw=',
      );
      expect(
        SecretCodec.decode('gwenc1:t8dnx9FzqWjLfaOgfbtt0no='),
        '*.api.example.com',
      );
    });

    test('round-trips arbitrary text', () {
      for (final plain in [
        'https://a.example.com',
        'https://*.example.com/prefix',
        'https://пример.рф/путь',
        'x' * 100,
      ]) {
        final encoded = SecretCodec.encode(plain);
        expect(encoded, startsWith(SecretCodec.prefix));
        expect(encoded, isNot(contains('example')));
        expect(SecretCodec.decode(encoded), plain);
      }
    });

    test('tolerates console copy/paste artefacts', () {
      const encoded = 'gwenc1:q1+HXXGUpMVlmdGxsnPL1Gm0l7tijLw=';
      for (final raw in [
        '  $encoded\n',
        '"$encoded"',
        "'$encoded'",
        'gwenc1:q1+HXXGUpMVl mdGxsnPL1Gm0l7tijLw=',
        'gwenc1:q1+HXXGUpMVlmdGxsnPL1Gm0l7tijLw',
      ]) {
        expect(
          SecretCodec.tryDecode(raw),
          'https://api.example.com',
          reason: raw,
        );
      }
    });

    test('broken payloads are reported, plain text passes through', () {
      expect(SecretCodec.tryDecode('gwenc1:%%%not-base64%%%'), isNull);
      expect(SecretCodec.tryDecode('gwenc1:'), isNull);
      expect(SecretCodec.tryDecode('gwenc1:/w=='), isNull);
      expect(
        SecretCodec.tryDecode('https://plain.example.com'),
        'https://plain.example.com',
      );
      expect(SecretCodec.decode('gwenc1:%%%'), 'gwenc1:%%%');
      expect(SecretCodec.isEncoded(' gwenc1:abc'), isTrue);
      expect(SecretCodec.isEncoded('https://x.example.com'), isFalse);
    });
  });

  group('baked-in default', () {
    test('is encoded and decodes to a valid HTTPS endpoint', () {
      expect(SecretCodec.isEncoded(ApiConfig.defaultBaseUrlEncrypted), isTrue);
      final decoded = SecretCodec.tryDecode(ApiConfig.defaultBaseUrlEncrypted);
      final endpoint = ApiEndpoint.tryParse(decoded);
      expect(endpoint, isNotNull);
      expect(endpoint!.isTemplate, isFalse);
      expect(SecretCodec.encode(decoded!), ApiConfig.defaultBaseUrlEncrypted);
    });

    test('the API host never appears in plain text in lib/', () {
      final host = Uri.parse(ApiConfig.defaultBaseUrl).host;
      expect(host, isNotEmpty);
      final offenders = <String>[
        for (final entity in Directory('lib').listSync(recursive: true))
          if (entity is File &&
              entity.path.endsWith('.dart') &&
              entity.readAsStringSync().toLowerCase().contains(host))
            entity.path,
      ];
      expect(offenders, isEmpty);
    });
  });
}
