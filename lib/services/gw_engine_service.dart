import 'dart:async';

import 'package:flutter/services.dart';

import '../models/server_config_model.dart';
import 'vpn_service.dart' show VpnStatus;

/// Dart bridge to the native GW engine (SSH-tunnel protocol, ported from
/// the GW VPN app's gw-tunnel module).
///
/// Channels:
///   - MethodChannel `app.rabochiy.vpn/vlee`  — connect / disconnect / isConnected
///   - EventChannel  `app.rabochiy.vpn/vlee/status` — STATE: / TRAFFIC:up:down /
///     RECONNECTING: broadcast events.
class GwEngineService {
  GwEngineService._();
  static final GwEngineService instance = GwEngineService._();

  static const MethodChannel _channel = MethodChannel('app.rabochiy.vpn/vlee');
  static const EventChannel _statusChannel =
      EventChannel('app.rabochiy.vpn/vlee/status');

  Stream<String>? _rawStream;
  StreamSubscription<dynamic>? _rawSub;

  final _statusController = StreamController<String>.broadcast();

  /// Raw status events: `STATE:CONNECTED`, `TRAFFIC:up:down`, `RECONNECTING:true`.
  Stream<String> get statusStream => _statusController.stream;

  void bind() {
    _rawSub ??= _events.listen(
      _statusController.add,
      onError: (Object error) => _statusController.add('STATE:ERROR'),
    );
  }

  void unbind() {
    _rawSub?.cancel();
    _rawSub = null;
  }

  Stream<String> get _events {
    _rawStream ??= _statusChannel
        .receiveBroadcastStream()
        .map((event) => event?.toString() ?? '');
    return _rawStream!;
  }

  /// Starts the GW tunnel for the given decrypted server envelope
  /// (the k0..ka JSON as produced by [GwApiService]). The native side
  /// handles VpnService.prepare() itself when needed.
  ///
  /// [excludedApps] — packages that bypass the tunnel (exclude mode);
  /// [allowedApps] — the only packages routed through the tunnel
  /// (include mode). The native side always excludes the VPN app itself
  /// in exclude mode, so the engine's own sockets stay outside.
  Future<bool> connect(
    ServerConfig config, {
    List<String>? excludedApps,
    List<String>? allowedApps,
  }) async {
    try {
      return await _channel.invokeMethod<bool>(
            'connect',
            <String, dynamic>{
              'config': config.gwRawConfig,
              'excludedApps': excludedApps ?? const <String>[],
              'allowedApps': allowedApps ?? const <String>[],
            },
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Stops the GW tunnel.
  Future<void> disconnect() async {
    try {
      await _channel.invokeMethod('disconnect');
    } on PlatformException {
      // Engine already stopped — nothing to do.
    }
  }

  Future<bool> isConnected() async {
    try {
      return await _channel.invokeMethod<bool>('isConnected') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Parses a `STATE:<name>` event into our shared status enum.
  static VpnStatus? statusFromEvent(String event) {
    if (!event.startsWith('STATE:')) return null;
    switch (event.substring('STATE:'.length).toUpperCase()) {
      case 'CONNECTING':
        return VpnStatus.connecting;
      case 'CONNECTED':
        return VpnStatus.connected;
      case 'DISCONNECTING':
        return VpnStatus.disconnecting;
      case 'DISCONNECTED':
        return VpnStatus.disconnected;
      case 'ERROR':
        return VpnStatus.error;
      default:
        return null;
    }
  }
}
