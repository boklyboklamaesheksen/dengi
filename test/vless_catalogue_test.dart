import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rabochiy_vpn/config/secret_codec.dart';
import 'package:rabochiy_vpn/models/server_config_model.dart';
import 'package:rabochiy_vpn/services/vless_catalogue_client.dart';
import 'package:rabochiy_vpn/services/vless_subscription_service.dart';

String link(int n, String remark) =>
    'vless://00000000-0000-4000-8000-00000000000$n@192.0.2.$n:443'
    '?security=reality&type=raw&sni=example.com&pbk=key&sid=ab'
    '#${Uri.encodeComponent(remark)}';

String digest(String vless) => sha1
    .convert(utf8.encode(vless.split('#').first))
    .toString()
    .substring(0, 16);

class FakeCatalogue extends VlessCatalogueClient {
  FakeCatalogue({required this.user, this.servers, this.fail = false})
    : super(client: MockClient((_) async => http.Response('', 500)));

  String user;
  List<dynamic>? servers;
  bool fail;
  final List<String> requestedFor = <String>[];

  @override
  Future<String> currentUserId() async => user;

  @override
  Future<List<dynamic>> fetchRaw(String userId) async {
    requestedFor.add(userId);
    if (fail) throw Exception('offline');
    return servers!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => VlessSubscriptionSources.instance.apply(''));

  final free1 = link(1, '🇷🇺 Белые списки #1');
  final pro2 = link(2, '🇩🇪 Германия #1');
  final other = link(3, '🇳🇱 Нидерланды #1');

  List<dynamic> catalogue({required bool premiumUser}) => <dynamic>[
    <String, dynamic>{
      'id': digest(free1),
      'name': '🇷🇺 Белые списки #1',
      'premium': false,
      'link': free1,
    },
    <String, dynamic>{
      'id': digest(pro2),
      'name': '🇩🇪 Германия #1',
      'premium': true,
      if (premiumUser) 'link': pro2 else 'locked': true,
    },
  ];

  test('locked and unlocked entries share the id of the real link', () {
    final locked = VlessCatalogueClient.parse(catalogue(premiumUser: false));
    final unlocked = VlessCatalogueClient.parse(catalogue(premiumUser: true));
    expect(locked.map((s) => s.id), unlocked.map((s) => s.id));
    expect(locked[1].isLocked, isTrue);
    expect(locked[1].premium, isTrue);
    expect(locked[1].serverName, 'Германия #1');
    expect(locked[1].flag, '🇩🇪');
    expect(unlocked[1].isLocked, isFalse);
    expect(unlocked[1].premium, isTrue);
    expect(unlocked[1].originalUrl, pro2);
    expect(unlocked[0].premium, isFalse);
    expect(locked[1].id, ServerConfig.fromVlessUri(pro2)!.id);
  });

  test('malformed catalogue entries are skipped', () {
    final servers = VlessCatalogueClient.parse(<dynamic>[
      'junk',
      <String, dynamic>{'id': 'zz', 'name': 'X', 'premium': true},
      <String, dynamic>{'id': digest(pro2), 'name': '', 'premium': true},
      <String, dynamic>{'premium': false, 'link': 'vmess://nope'},
    ]);
    expect(servers, isEmpty);
  });

  test(
    'our /bs is replaced by the catalogue, other subscriptions stay',
    () async {
      VlessSubscriptionSources.instance.apply(
        SecretCodec.encode(
          'https://sub.example/bs\nhttps://other.example/list',
        ),
      );
      final requested = <String>[];
      final service = VlessSubscriptionService(
        client: MockClient((request) async {
          requested.add(request.url.toString());
          return http.Response.bytes(utf8.encode('$other\n$free1\n'), 200);
        }),
        catalogue: FakeCatalogue(
          user: 'u1',
          servers: catalogue(premiumUser: false),
        ),
      );
      final servers = await service.fetchServers();
      expect(requested, <String>['https://other.example/list']);
      expect(servers.map((s) => s.serverName), <String>[
        'Белые списки #1',
        'Германия #1',
        'Нидерланды #1',
      ]);
      expect(servers[1].isLocked, isTrue);
    },
  );

  test(
    'without the API the public free list is used, then the cache',
    () async {
      VlessSubscriptionSources.instance.apply(
        SecretCodec.encode('https://sub.example/bs'),
      );
      var online = true;
      final catalogueClient = FakeCatalogue(user: 'u1', fail: true);
      final service = VlessSubscriptionService(
        client: MockClient((request) async {
          if (!online) throw Exception('offline');
          return http.Response.bytes(utf8.encode('$free1\n'), 200);
        }),
        catalogue: catalogueClient,
      );
      expect((await service.fetchServers()).single.originalUrl, free1);

      catalogueClient
        ..fail = false
        ..servers = catalogue(premiumUser: true);
      expect((await service.fetchServers()).length, 2);

      online = false;
      catalogueClient.fail = true;
      final cached = await service.fetchServers();
      expect(cached.map((s) => s.originalUrl), <String>[free1, pro2]);
    },
  );

  test('cached PRO links belong to the account that fetched them', () async {
    VlessSubscriptionSources.instance.apply(
      SecretCodec.encode('https://sub.example/bs'),
    );
    final catalogueClient = FakeCatalogue(
      user: 'pro-user',
      servers: catalogue(premiumUser: true),
    );
    final service = VlessSubscriptionService(
      client: MockClient((_) async => http.Response('', 500)),
      catalogue: catalogueClient,
    );
    await service.fetchServers();
    expect(
      (await service.readCachedServers()).map((s) => s.originalUrl),
      contains(pro2),
    );
    catalogueClient.user = 'other-user';
    expect(await service.readCachedServers(), isEmpty);
  });
}
