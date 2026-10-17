import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/backend_signing.dart';
import '../models/server_config_model.dart';
import 'api_host_service.dart';
import 'api_service.dart';

/// Our VLESS catalogue with PRO flags (`POST /vpn/api/v1/user/server_bs`).
///
/// The public `/bs` subscription carries only free servers. This endpoint
/// lists every server; PRO links are delivered to PRO accounts only, free
/// accounts get the name so the list can show it with a star and open the
/// paywall.
class VlessCatalogueClient {
  VlessCatalogueClient({
    http.Client? client,
    this._signing = const BackendSigning(),
    this._baseUrl,
    this._timeout = const Duration(seconds: 6),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  static const String path = '/vpn/api/v1/user/server_bs';

  final http.Client _client;
  final bool _ownsClient;
  final BackendSigning _signing;
  final String? _baseUrl;
  final Duration _timeout;

  /// Account the catalogue is fetched for ('' before signup); the cache is
  /// bound to it so PRO links never outlive a logout.
  Future<String> currentUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(ApiService.userIdPrefsKey) ?? '';
      return id == 'pending' ? '' : id;
    } catch (_) {
      return '';
    }
  }

  /// Raw `servers` array of the response; throws when unavailable.
  Future<List<dynamic>> fetchRaw(String userId) async {
    final body = _signing.sign(<String, String>{'userId': userId});

    Future<http.Response> send(String base) => _client
        .post(
          Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}$path'),
          headers: const <String, String>{
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: body,
        )
        .timeout(_timeout);

    final override = _baseUrl;
    final response = override != null
        ? await send(override)
        : await ApiHostService.instance.withFailover(send);
    if (response.statusCode != 200) {
      throw Exception('VLESS catalogue HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map ||
        (decoded['success'] != 1 && decoded['success'] != true)) {
      throw const FormatException('Invalid VLESS catalogue response');
    }
    final data = decoded['data'];
    final servers = data is Map ? data['servers'] : null;
    if (servers is! List) {
      throw const FormatException('Invalid VLESS catalogue response');
    }
    return servers;
  }

  /// Entries in backend order; malformed ones are skipped.
  static List<ServerConfig> parse(List<dynamic> servers) {
    final out = <ServerConfig>[];
    for (final entry in servers) {
      if (entry is! Map) continue;
      final premium = entry['premium'] == true;
      final link = entry['link'];
      ServerConfig? server;
      if (link is String && link.isNotEmpty) {
        server = ServerConfig.fromVlessUri(link)?.copyWith(premium: premium);
      } else if (premium) {
        final id = entry['id'];
        final name = entry['name'];
        if (id is String && name is String) {
          server = ServerConfig.lockedVless(digest: id, remark: name);
        }
      }
      if (server != null) out.add(server);
    }
    return out;
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
