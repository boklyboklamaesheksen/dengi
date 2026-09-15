import 'package:flutter/material.dart';


/// Large monospaced hh:mm:ss readout for the home screen.
///
/// When the tunnel is active the digits are painted with the primary signal
/// gradient via [ShaderMask]; when idle, they fade to a low-contrast
/// neutral so they don't fight for attention.
class OrbitTimer extends StatelessWidget {
  const OrbitTimer({
    super.key,
    required this.elapsed,
    required this.active,
  });

  final Duration elapsed;
  final bool active;

  String _two(int n) => n.toString().padLeft(2, '0');

  String _format(Duration d) =>
      '${_two(d.inHours)}:${_two(d.inMinutes.remainder(60))}:${_two(d.inSeconds.remainder(60))}';

  @override
  Widget build(BuildContext context) {
    final String value = active ? _format(elapsed) : '--:--:--';
    return Text(
      value,
      style: const TextStyle(
        color: Colors.white,
        fontFamily: 'Inter',
        fontSize: 60,
        fontWeight: FontWeight.w300,
        letterSpacing: -2.4,
        fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
  }
}
