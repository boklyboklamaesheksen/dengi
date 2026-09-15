import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rabochiy_vpn/services/traffic_stats_service.dart';
import 'package:rabochiy_vpn/services/vpn_service.dart';

void main() {
  test('engine counters retain values larger than signed 32-bit integers', () {
    final status = EngineStatus.fromMap({
      'download': 4294967296,
      'upload': '3221225472',
      'downloadSpeed': double.nan,
      'uploadSpeed': null,
    });
    expect(status.download, 4294967296);
    expect(status.upload, 3221225472);
    expect(status.downloadSpeed, 0);
    expect(status.uploadSpeed, 0);
  });

  testWidgets('continuous traffic is saved without waiting for a quiet interval', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final stats = TrafficStatsService();
    await stats.load();
    stats.recordSessionStart();
    for (var second = 1; second <= 12; second++) {
      stats.recordSample(totalRxBytes: second * 100, totalTxBytes: second * 50);
      await tester.pump(const Duration(seconds: 1));
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('rabochiy_traffic_buckets_v1');
    expect(raw, isNotNull);
    expect(jsonDecode(raw!) as List<dynamic>, isNotEmpty);
    stats.dispose();
    await tester.pump();
  });
}
