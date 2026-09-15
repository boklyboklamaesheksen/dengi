import 'package:rabochiy_vpn/models/server_config_model.dart';
import 'package:rabochiy_vpn/services/api_service.dart';
import 'package:rabochiy_vpn/services/gw_api_service.dart';

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
