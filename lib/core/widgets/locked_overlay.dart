import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Wraps [child] with a heavy blur plus a centered lock icon when
/// [locked] — used on the Info screens' Ingredients/Cocktails/Songs rows
/// so a level the player hasn't reached yet reads as "it's there, you
/// just haven't unlocked it" (worth swiping on to) without actually
/// revealing its ingredients/cocktails/songs ahead of time. Purely
/// visual — a locked row's own tap/playback handling is each caller's
/// responsibility to disable separately (see _CocktailRow/_SongRow's
/// own `locked` handling).
class LockedContent extends StatelessWidget {
  final bool locked;
  final Widget child;
  const LockedContent({super.key, required this.locked, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!locked) return child;
    return Stack(
      alignment: Alignment.center,
      children: [
        ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8), child: child),
        const Icon(Icons.lock_rounded, color: Colors.white, size: 26, shadows: [Shadow(color: Colors.black54, blurRadius: 6)]),
      ],
    );
  }
}
