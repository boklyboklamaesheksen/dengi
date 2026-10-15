import 'package:rabochiy_vpn/models/server_config_model.dart';
import 'package:rabochiy_vpn/services/api_service.dart';
import 'package:rabochiy_vpn/services/gw_api_service.dart';
import 'package:rabochiy_vpn/services/vless_subscription_service.dart';

const awgServer = ServerConfig(
  id: 'qa-awg',
  serverName: 'QA AWG',
  address: '192.0.2.1',
  port: 51820,
);
const gwServer = ServerConfig(
  id: 'qa-gw',
  serverName: 'QA GW',
  address: '192.0.2.2',
  port: 443,
  protocol: ServerProtocol.gw,
  country: 'QA — Finland',
  countryCode: 'FI',
  flag: '🇫🇮',
  gwRawConfig: '{"test":true}',
);

class FakeApi extends ApiService {
  FakeApi({required this.fetch});
  Future<List<ServerConfig>> Function() fetch;
  int fetchCount = 0;

  @override
  Future<List<ServerConfig>> fetchServerConfigs() {
    fetchCount++;
    return fetch();
  }

  @override
  Future<Map<String, int>> fetchServerLoads() async => {};
}

class FakeGwApi extends GwApiService {
  FakeGwApi({required this.fetch});
  Future<List<ServerConfig>> Function() fetch;

  @override
  Future<List<ServerConfig>> fetchServers() => fetch();
}

final vlessServer = ServerConfig.fromVlessUri(
  'vless://00000000-0000-4000-8000-000000000001@192.0.2.3:443'
  '?encryption=none&security=tls&type=ws&path=%2F'
  '#%F0%9F%87%B7%F0%9F%87%BA%20%D0%91%D0%B5%D0%BB%D1%8B%D0%B5%20%D1%81%D0%BF%D0%B8%D1%81%D0%BA%D0%B8%20%231',
)!;

class FakeVless extends VlessSubscriptionService {
  FakeVless({Future<List<ServerConfig>> Function()? fetch})
    : fetch = fetch ?? (() async => const <ServerConfig>[]);
  Future<List<ServerConfig>> Function() fetch;

  @override
  Future<List<ServerConfig>> fetchServers() => fetch();
}
