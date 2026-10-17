library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The class deliberately keeps the **same public API** as the previous
/// version (`id`, `serverName`, `address`, `port`, `country`, `flag`,
/// `ping`, `cleanName`, `originalUrl`, `copyWith`) so existing screens
/// (`server_list_screen.dart`, `home_screen.dart`, providers) keep
/// compiling without changes. Protocol-specific data lives in
/// `protocol`, `username`, `password`, `caFile`, `awgConfig`, `gwRawConfig`,
/// `originalUrl` (the `vless://` link for VLESS servers).

/// Supported VPN protocols. Driven by the backend `protocol` field.
enum ServerProtocol {
  awg,
  gw,
  vless;

  static ServerProtocol fromString(String? raw) {
    switch ((raw ?? '').toLowerCase().trim()) {
      case 'gw':
      case 'vlee':
        return ServerProtocol.gw;
      case 'vless':
        return ServerProtocol.vless;
      default:
        // awg / amneziawg / wireguard / wg and any legacy value
        // (ikev2 etc.) fall back to the primary AWG protocol.
        return ServerProtocol.awg;
    }
  }

  String get apiName => switch (this) {
    ServerProtocol.awg => 'awg',
    ServerProtocol.gw => 'gw',
    ServerProtocol.vless => 'vless',
  };

  /// Human-readable label for the UI badge.
  String get displayName => switch (this) {
    ServerProtocol.awg => 'AmneziaWG 3.1',
    ServerProtocol.gw => 'GW',
    ServerProtocol.vless => 'VLESS',
  };
}

/// Server configuration as returned by the Zapret VPN backend.
class ServerConfig {
  // ── Identity / display ────────────────────────────────────────────
  final String id;
  final String serverName;
  final String address;
  final int port;
  final String country;
  final String countryCode;
  final String flag;
  final int ping;
  final bool isActive;

  // Kept for backward compatibility with old call-sites that read it.
  final String originalUrl;

  // ── Protocol routing ──────────────────────────────────────────────
  final ServerProtocol protocol;

  // ── Metadata ──────────────────────────────────────────────────────
  final String state;
  final bool premium;
  final bool recommend;
  final int priority;

  // ── Legacy credentials (IKEv2 removed; fields kept because the
  // native method channel still receives them) ───────────────────────
  final String username;
  final String password;

  /// Base64-encoded CA certificate (PEM). Unused since IKEv2 removal.
  final String caFile;

  // ── AmneziaWG configuration ───────────────────────────────────────
  /// Base64 of the full `awg-quick`-style config (Interface + Peer).
  /// Decoded by the native [AmneziaWG] backend before tunnel setup.
  final String awgConfig;

  // ── GW (SSH-tunnel) configuration ─────────────────────────────────
  /// Plaintext server envelope (the k0..ka JSON) handed to the native
  /// GW engine verbatim. Empty for non-GW servers.
  final String gwRawConfig;

  const ServerConfig({
    required this.id,
    required this.serverName,
    required this.address,
    required this.port,
    this.country = 'Unknown',
    this.countryCode = '',
    this.flag = '🏳️',
    this.ping = 0,
    this.isActive = false,
    this.originalUrl = '',
    this.protocol = ServerProtocol.awg,
    this.state = '',
    this.premium = false,
    this.recommend = false,
    this.priority = 0,
    this.username = '',
    this.password = '',
    this.caFile = '',
    this.awgConfig = '',
    this.gwRawConfig = '',
  });

  /// Friendly name without the trailing `| tag`. Matches the previous
  /// implementation so server tiles render identically.
  String get cleanName {
    if (serverName.contains('|')) {
      return serverName.split('|').first.trim();
    }
    return serverName;
  }

  /// Convenience synonyms exposed for callers that prefer the more
  /// descriptive names; both pairs return the same underlying value.
  String get ipAddress => address;
  bool get isPremium => premium;

  /// A PRO VLESS server listed for a free account: the backend withholds
  /// its link, so it can only lead to the paywall.
  bool get isLocked => protocol == ServerProtocol.vless && originalUrl.isEmpty;

  /// Default port when the backend doesn't supply one. Reflects the
  /// canonical port for each transport.
  static int defaultPortFor(ServerProtocol p) => switch (p) {
    ServerProtocol.awg => 51820,
    ServerProtocol.gw => 22,
    ServerProtocol.vless => 443,
  };

  /// Builds a VLESS server from a subscription `vless://` link, or returns
  /// null when the link is malformed. The display name is the link remark
  /// without its leading flag (the flag becomes [flag]); the id is derived
  /// from the link minus the remark, so renames keep the selection.
  static ServerConfig? fromVlessUri(String raw) {
    final link = raw.trim();
    if (!link.toLowerCase().startsWith('vless://')) return null;
    final hashAt = link.indexOf('#');
    final body = hashAt >= 0 ? link.substring(0, hashAt) : link;
    final remark = hashAt >= 0
        ? _decodeComponent(link.substring(hashAt + 1))
        : '';

    final rest = body.substring('vless://'.length);
    final authority = rest.split('?').first.replaceAll(RegExp(r'/+$'), '');
    final at = authority.lastIndexOf('@');
    if (at <= 0) return null;
    final hostPort = authority.substring(at + 1);
    String host;
    String portText;
    if (hostPort.startsWith('[')) {
      final end = hostPort.indexOf(']');
      if (end <= 1) return null;
      host = hostPort.substring(1, end);
      portText = hostPort.substring(end + 1).replaceFirst(':', '');
    } else {
      final colon = hostPort.lastIndexOf(':');
      if (colon <= 0) return null;
      host = hostPort.substring(0, colon);
      portText = hostPort.substring(colon + 1);
    }
    final port = int.tryParse(portText);
    if (host.isEmpty || port == null || port < 1 || port > 65535) return null;

    final (:countryCode, :name) = _splitRemark(remark);
    final display = name.isNotEmpty ? name : host;

    return ServerConfig(
      id: 'vless_${_shortDigest(body)}',
      serverName: display,
      address: host,
      port: port,
      // Tiles render `country`; for VLESS it carries the remark.
      country: display,
      countryCode: countryCode,
      flag: countryCode.isEmpty ? '🌐' : _flagFromCountryCode(countryCode),
      originalUrl: link,
      protocol: ServerProtocol.vless,
    );
  }

  /// Locked PRO entry of the VLESS catalogue. [digest] is the backend's
  /// sha1 prefix of the link body, so the id equals the one [fromVlessUri]
  /// gives the same server once its link is delivered.
  static ServerConfig? lockedVless({
    required String digest,
    required String remark,
  }) {
    if (!RegExp(r'^[0-9a-f]{16}$').hasMatch(digest)) return null;
    final (:countryCode, :name) = _splitRemark(remark);
    if (name.isEmpty) return null;
    return ServerConfig(
      id: 'vless_$digest',
      serverName: name,
      address: '',
      port: defaultPortFor(ServerProtocol.vless),
      country: name,
      countryCode: countryCode,
      flag: countryCode.isEmpty ? '🌐' : _flagFromCountryCode(countryCode),
      protocol: ServerProtocol.vless,
      premium: true,
    );
  }

  static ({String countryCode, String name}) _splitRemark(String remark) {
    final flagMatch = _flagPattern.firstMatch(remark);
    final countryCode = flagMatch == null
        ? ''
        : String.fromCharCodes(
            flagMatch.group(0)!.runes.map((r) => r - 0x1F1E6 + 0x41),
          );
    final name = remark
        .replaceAll(_flagPattern, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return (countryCode: countryCode, name: name);
  }

  static final RegExp _flagPattern = RegExp(
    '[\u{1F1E6}-\u{1F1FF}]{2}',
    unicode: true,
  );

  static String _decodeComponent(String value) {
    try {
      return Uri.decodeComponent(value);
    } catch (_) {
      return value;
    }
  }

  static String _shortDigest(String input) =>
      sha1.convert(utf8.encode(input)).toString().substring(0, 16);

  /// Builds a [ServerConfig] from a decrypted GW server envelope.
  ///
  /// `meta` is the public server view (id/name/country/...), `config` is
  /// the decrypted node credentials (compact `k0..ka` keys or legacy
  /// names, both accepted — the native engine understands either).
  factory ServerConfig.fromGw({
    required Map<String, dynamic> meta,
    required Map<String, dynamic> config,
  }) {
    String pick(String compact, String legacy, [String fallback = '']) =>
        config.containsKey(compact)
        ? config[compact]?.toString() ?? fallback
        : (config[legacy]?.toString() ?? fallback);

    int pickInt(String compact, String legacy, int fallback) {
      final raw = config.containsKey(compact)
          ? config[compact]
          : config[legacy];
      return (raw is num) ? raw.toInt() : int.tryParse('$raw') ?? fallback;
    }

    final nodeId = pick('k0', 'id');
    final ipAddress = pick('k1', 'ip_address');
    final sshPort = pickInt('k2', 'ssh_port', 22);
    final proxyHost = pick('k5', 'proxy_host');
    final proxyPort = pickInt('k6', 'proxy_port', 80);
    final viaProxy = proxyHost.isNotEmpty;
    // Display endpoint: the front the user actually reaches.
    final address = viaProxy ? proxyHost : ipAddress;
    final port = viaProxy ? proxyPort : sshPort;

    final country = (meta['country'] as String?) ?? '';
    final state = (meta['state'] as String?) ?? '';
    final countryCode = ((meta['country_code'] as String?) ?? '')
        .trim()
        .toUpperCase();
    final nodeName = (meta['name'] as String?) ?? '';

    var display = country.isNotEmpty && country != '0'
        ? country
        : (nodeName.isNotEmpty ? nodeName : ipAddress);
    if (state.isNotEmpty && state != '0') display = '$display • $state';

    return ServerConfig(
      id: 'gw_$nodeId',
      serverName: display,
      address: address,
      port: port,
      country: country.isNotEmpty && country != '0' ? country : 'Unknown',
      countryCode: countryCode,
      flag: _flagFromCountryCode(countryCode),
      protocol: ServerProtocol.gw,
      state: (meta['state'] as String?) ?? '',
      premium: meta['premium'] == true || config['locked'] == true,
      recommend: meta['recommend'] == true,
      priority: _parseInt(meta['priority']) ?? 0,
      // The whole plaintext envelope goes to the native engine as-is.
      gwRawConfig: jsonEncode(config),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  //  Serialization
  // ──────────────────────────────────────────────────────────────────

  /// Builds a [ServerConfig] from a backend server document.
  ///
  /// Two sources feed into this:
  ///   * **`/vpn/api/v3/client/servers/get`** for legacy records — the body is
  ///     `{country, ip_address, recommend, priority, user, password,
  ///     ca_file, created_at, premium, state, status}` (no
  ///     `country_code`, no `id`).
  ///   * **`/vpn/api/v1/user/server_awg`** for AmneziaWG — adds
  ///     `country_code`, `config`, `_id`.
  ///
  /// The protocol is inferred from `json['protocol']` when present and
  /// otherwise patched in by `ApiService._parseList`. Empty / `"0"`
  /// placeholder strings (the backend's default sentinel value) are
  /// normalised to the empty string so the UI doesn't surface them.
  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    final protocol = ServerProtocol.fromString(json['protocol'] as String?);
    final ip = _stripSentinel(
      (json['ip_address'] ?? json['address'] ?? '').toString(),
    );
    final country = _stripSentinel((json['country'] ?? '').toString());
    final state = _stripSentinel((json['state'] ?? '').toString());
    var countryCode = _stripSentinel(
      (json['country_code'] ?? json['countryCode'] ?? '').toString(),
    ).toUpperCase();

    // Legacy records ship without a country_code — derive a best-effort
    // ISO-3166 code from the country / state name so the UI can still
    // render a real flag instead of the generic white one.
    if (countryCode.isEmpty) {
      countryCode = _inferCountryCode(country, state);
    }

    final rawId = _stripSentinel((json['id'] ?? json['_id'] ?? '').toString());
    final id = rawId.isNotEmpty ? rawId : '${protocol.apiName}_$ip';

    final port = _parsePort(json['port']) ?? defaultPortFor(protocol);

    final serverName = _stripSentinel(
      (json['name'] ?? json['serverName'] ?? '').toString(),
    );
    final displayName = serverName.isNotEmpty
        ? serverName
        : _composeDisplayName(country, state, countryCode);

    return ServerConfig(
      id: id,
      serverName: displayName,
      address: ip,
      port: port,
      country: country.isEmpty ? 'Unknown' : country,
      countryCode: countryCode,
      flag: _flagFromCountryCode(countryCode),
      protocol: protocol,
      state: state,
      premium: json['premium'] == true,
      recommend: json['recommend'] == true,
      priority: _parseInt(json['priority']) ?? 0,
      username: _stripSentinel(
        (json['user'] ?? json['username'] ?? '').toString(),
      ),
      password: _stripSentinel((json['password'] ?? '').toString()),
      caFile: _stripSentinel(
        (json['ca_file'] ?? json['caFile'] ?? '').toString(),
      ),
      awgConfig: _stripSentinel(
        (json['config'] ?? json['awgConfig'] ?? '').toString(),
      ),
    );
  }

  /// Reverse of [fromJson] — useful for caching the latest catalogue
  /// to disk so the UI is never empty on cold start.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': serverName,
    'ip_address': address,
    'port': port,
    'country': country,
    'country_code': countryCode,
    'state': state,
    'protocol': protocol.apiName,
    'premium': premium,
    'recommend': recommend,
    'priority': priority,
    'user': username,
    'password': password,
    'ca_file': caFile,
    'config': awgConfig,
  };

  ServerConfig copyWith({
    String? id,
    String? serverName,
    String? address,
    int? port,
    String? country,
    String? countryCode,
    String? flag,
    int? ping,
    bool? isActive,
    String? originalUrl,
    ServerProtocol? protocol,
    String? state,
    bool? premium,
    bool? recommend,
    int? priority,
    String? username,
    String? password,
    String? caFile,
    String? awgConfig,
    String? gwRawConfig,
  }) {
    return ServerConfig(
      id: id ?? this.id,
      serverName: serverName ?? this.serverName,
      address: address ?? this.address,
      port: port ?? this.port,
      country: country ?? this.country,
      countryCode: countryCode ?? this.countryCode,
      flag: flag ?? this.flag,
      ping: ping ?? this.ping,
      isActive: isActive ?? this.isActive,
      originalUrl: originalUrl ?? this.originalUrl,
      protocol: protocol ?? this.protocol,
      state: state ?? this.state,
      premium: premium ?? this.premium,
      recommend: recommend ?? this.recommend,
      priority: priority ?? this.priority,
      username: username ?? this.username,
      password: password ?? this.password,
      caFile: caFile ?? this.caFile,
      awgConfig: awgConfig ?? this.awgConfig,
      gwRawConfig: gwRawConfig ?? this.gwRawConfig,
    );
  }

  // ──────────────────────────────────────────────────────────────────
  //  Helpers
  // ──────────────────────────────────────────────────────────────────

  /// Replaces the backend sentinel value `"0"` (used as the default
  /// for unset string fields server-side) with an empty string so the
  /// UI can rely on the usual "is the string empty" check instead of
  /// having to special-case the literal `"0"`.
  static String _stripSentinel(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == '0') return '';
    return trimmed;
  }

  /// Best-effort ISO-3166 alpha-2 code lookup from a country / state
  /// name. Returns the empty string when no entry matches; the flag
  /// helper falls back to the white-flag emoji in that case.
  static String _inferCountryCode(String country, String state) {
    final hay = ('$country $state').toLowerCase();
    for (final entry in _countryCodeFallback.entries) {
      if (hay.contains(entry.key)) return entry.value;
    }
    return '';
  }

  /// Lightweight country-name → ISO-3166-alpha-2 lookup. Only the
  /// regions actually present in the active server fleet need entries
  /// here; new entries can be added as the catalogue expands.
  static const Map<String, String> _countryCodeFallback = <String, String>{
    'russia': 'RU',
    'россия': 'RU',
    'germany': 'DE',
    'deutschland': 'DE',
    'netherlands': 'NL',
    'нидерланды': 'NL',
    'finland': 'FI',
    'финляндия': 'FI',
    'estonia': 'EE',
    'эстония': 'EE',
    'sweden': 'SE',
    'швеция': 'SE',
    'norway': 'NO',
    'norge': 'NO',
    'denmark': 'DK',
    'данія': 'DK',
    'poland': 'PL',
    'польша': 'PL',
    'france': 'FR',
    'франция': 'FR',
    'spain': 'ES',
    'испания': 'ES',
    'italy': 'IT',
    'италия': 'IT',
    'switzerland': 'CH',
    'швейцария': 'CH',
    'austria': 'AT',
    'австрия': 'AT',
    'czech': 'CZ',
    'чехия': 'CZ',
    'turkey': 'TR',
    'türkiye': 'TR',
    'турция': 'TR',
    'united kingdom': 'GB',
    'great britain': 'GB',
    'england': 'GB',
    'британия': 'GB',
    'united states': 'US',
    'usa': 'US',
    'сша': 'US',
    'canada': 'CA',
    'канада': 'CA',
    'japan': 'JP',
    'япония': 'JP',
    'singapore': 'SG',
    'сингапур': 'SG',
    'hong kong': 'HK',
    'гонконг': 'HK',
    'kazakhstan': 'KZ',
    'казахстан': 'KZ',
    'belarus': 'BY',
    'беларусь': 'BY',
    'ukraine': 'UA',
    'украина': 'UA',
    'latvia': 'LV',
    'латвия': 'LV',
    'lithuania': 'LT',
    'литва': 'LT',
    'romania': 'RO',
    'румыния': 'RO',
    'bulgaria': 'BG',
    'болгария': 'BG',
    'serbia': 'RS',
    'сербия': 'RS',
    'moldova': 'MD',
    'молдова': 'MD',
  };

  static int? _parsePort(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  static int? _parseInt(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  static String _composeDisplayName(String country, String state, String code) {
    final parts = <String>[];
    if (country.isNotEmpty) parts.add(country);
    if (state.isNotEmpty && state != country) parts.add(state);
    final base = parts.join(' • ');
    if (base.isNotEmpty) return base;
    if (code.isNotEmpty) return code;
    return 'Server';
  }

  /// Converts a two-letter ISO country code to its emoji flag.
  /// Returns the white-flag emoji as a graceful fallback.
  static String _flagFromCountryCode(String code) {
    if (code.length != 2) return '🏳️';
    final upper = code.toUpperCase();
    final first = upper.codeUnitAt(0);
    final second = upper.codeUnitAt(1);
    const aChar = 0x41; // 'A'
    if (first < aChar || first > 0x5A || second < aChar || second > 0x5A) {
      return '🏳️';
    }
    final base = 0x1F1E6;
    return String.fromCharCodes([
      base + (first - aChar),
      base + (second - aChar),
    ]);
  }
}
