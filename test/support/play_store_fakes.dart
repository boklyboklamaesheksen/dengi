import 'dart:async';

import 'package:rabochiy_vpn/services/play_store_bridge.dart';
import 'package:rabochiy_vpn/services/vpn_service.dart';

/// Scripted Google Play bridge: no platform channel involved.
class FakePlayStoreBridge extends PlayStoreBridge {
  FakePlayStoreBridge() : super(platformSupported: true);

  bool reviewResult = true;
  int reviewRequests = 0;
  PlayUpdateInfo? updateInfo;
  PlayUpdateFlowResult flowResult = PlayUpdateFlowResult.accepted;
  final List<PlayUpdateType> startedFlows = <PlayUpdateType>[];
  int completeCalls = 0;
  int installStatusListeners = 0;

  late final StreamController<int> _installStatuses =
      StreamController<int>.broadcast(onListen: () => installStatusListeners++);

  void emitInstallStatus(int status) => _installStatuses.add(status);

  @override
  Future<bool> requestReview() async {
    reviewRequests++;
    return reviewResult;
  }

  @override
  Future<PlayUpdateInfo?> getUpdateInfo() async => updateInfo;

  @override
  Future<PlayUpdateFlowResult> startUpdate(PlayUpdateType type) async {
    startedFlows.add(type);
    return flowResult;
  }

  @override
  Future<bool> completeUpdate() async {
    completeCalls++;
    return true;
  }

  @override
  Stream<int> get installStatuses => _installStatuses.stream;
}

/// VPN engine whose status and traffic are driven by the test.
class FakeVpnService extends VpnService {
  FakeVpnService() : super(platformSupported: false);

  final StreamController<VpnStatus> _statuses =
      StreamController<VpnStatus>.broadcast();
  final StreamController<EngineStatus> _engine =
      StreamController<EngineStatus>.broadcast();

  @override
  Stream<VpnStatus> get statusStream => _statuses.stream;

  @override
  Stream<EngineStatus> get engineStatusStream => _engine.stream;

  @override
  Future<bool> initialize() async => true;

  void emitStatus(VpnStatus status) => _statuses.add(status);

  /// Cumulative bytes of the live session, as the native engine reports them.
  void emitTraffic(int totalBytes) => _engine.add(
    EngineStatus(
      state: 'CONNECTED',
      duration: 0,
      downloadSpeed: 0,
      uploadSpeed: 0,
      download: totalBytes,
      upload: 0,
    ),
  );

  @override
  void dispose() {
    _statuses.close();
    _engine.close();
    super.dispose();
  }
}
