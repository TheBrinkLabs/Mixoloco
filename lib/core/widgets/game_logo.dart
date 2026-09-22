import 'package:flutter/material.dart';

/// The "Mixoloco" wordmark — the real logo art (assets/images/mixoloco.jpg,
/// trimmed and background-stripped by tools/process_logo.dart into
/// mixoloco_logo.png), sized by [height] with width following its own
/// aspect ratio.
class GameLogo extends StatelessWidget {
  final double height;
  const GameLogo({super.key, this.height = 60});

  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/images/mixoloco_logo.png', height: height, fit: BoxFit.contain);
  }
}
