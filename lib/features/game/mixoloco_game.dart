import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Root Flame game — the bar surface where ingredients get thrown to
/// assemble the current order. Deliberately minimal for now (just a
/// background) — the throw/drag mechanic, ingredient components, and
/// order-matching logic land as their own components under
/// features/game/components/ once the core loop is being built out.
class MixolocoGame extends FlameGame {
  @override
  Color backgroundColor() => AppColors.bg;
}
