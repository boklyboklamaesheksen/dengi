import 'package:flutter/foundation.dart';

import '../models/server_config_model.dart';

/// Live state of "Auto server pick" for the UI.
@immutable
class AutoPickProgress {
  const AutoPickProgress({this.current = 0, this.total = 0, this.server});

  /// 1-based number of the server being tried; 0 while the search prepares.
  final int current;
  final int total;
  final ServerConfig? server;
}

/// Catalogue ranking: free servers first for free accounts, then
/// recommended, lighter load, higher priority, catalogue order.
List<ServerConfig> rankServers(
  List<ServerConfig> servers, {
  required bool isPremium,
  Map<String, int> loadByAddress = const <String, int>{},
}) {
  final indexed = <(int, ServerConfig)>[
    for (var i = 0; i < servers.length; i++) (i, servers[i]),
  ];
  indexed.sort((a, b) {
    final x = a.$2;
    final y = b.$2;
    if (!isPremium && x.premium != y.premium) return x.premium ? 1 : -1;
    if (x.recommend != y.recommend) return x.recommend ? -1 : 1;
    final loadX = loadByAddress[x.address] ?? 50;
    final loadY = loadByAddress[y.address] ?? 50;
    if (loadX != loadY) return loadX.compareTo(loadY);
    final byPriority = y.priority.compareTo(x.priority);
    if (byPriority != 0) return byPriority;
    return a.$1.compareTo(b.$1);
  });
  return <ServerConfig>[for (final entry in indexed) entry.$2];
}

/// Order in which auto-pick tries servers: only servers this account can
/// connect to, the last one that worked first, then the ranking with the
/// protocols taking turns, so a protocol blocked by the network (every AWG
/// handshake timing out, say) cannot stall the search for minutes.
List<ServerConfig> autoPickOrder(
  List<ServerConfig> servers, {
  required bool isPremium,
  Map<String, int> loadByAddress = const <String, int>{},
  String? lastWorkingId,
}) {
  final usable = <ServerConfig>[
    for (final server in servers)
      if (!server.isLocked && (isPremium || !server.premium)) server,
  ];
  final ranked = rankServers(
    usable,
    isPremium: isPremium,
    loadByAddress: loadByAddress,
  );

  // Protocol queues in order of their best server.
  final queues = <ServerProtocol, List<ServerConfig>>{};
  for (final server in ranked) {
    (queues[server.protocol] ??= <ServerConfig>[]).add(server);
  }
  final ordered = <ServerConfig>[];
  final seen = <String>{};
  for (var round = 0; ordered.length < ranked.length; round++) {
    var added = false;
    for (final queue in queues.values) {
      if (round >= queue.length) continue;
      added = true;
      // Duplicate ids would be tried twice for nothing.
      if (seen.add(queue[round].id)) ordered.add(queue[round]);
    }
    if (!added) break;
  }

  if (lastWorkingId != null) {
    final index = ordered.indexWhere((s) => s.id == lastWorkingId);
    if (index > 0) ordered.insert(0, ordered.removeAt(index));
  }
  return ordered;
}
