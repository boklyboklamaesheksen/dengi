import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rabochiy_vpn/services/split_tunnel_service.dart';
import 'package:rabochiy_vpn/services/traffic_stats_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('split-tunnel load can finish after disposal', () async {
    final service = SplitTunnelService();
    final loading = service.load();
    service.dispose();
    await loading;
    expect(service.isLoaded, isFalse);
  });

  test('traffic load can finish after disposal', () async {
    final service = TrafficStatsService();
    final loading = service.load();
    service.dispose();
    await loading;
    expect(service.isLoaded, isFalse);
  });

  test('traffic reset can finish after disposal', () async {
    final service = TrafficStatsService();
    await service.load();
    final resetting = service.reset();
    service.dispose();
    await resetting;
  });
}
