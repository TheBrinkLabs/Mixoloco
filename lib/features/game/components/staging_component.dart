import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart' show BlurStyle, Canvas, Color, MaskFilter, Paint, PaintingStyle, Path, StrokeCap;
import '../../../core/widgets/bar_backdrop.dart' show kTableFarToNearWidthRatio;
import '../../../data/models/ingredient.dart';
import 'ingredient_sprite.dart';
import 'table_boundary_component.dart' show kTableFarInset;

/// The draggable glass waiting to be dropped, hovering near the table's
/// near/staging edge (see MixolocoGame — gravity pulls the other way,
/// toward the far edge, so releasing here just lets a fresh item join
/// the fall). Drag anywhere on the table to aim left/right, release to
/// drop — releasing with no movement drops straight down from wherever
/// the glass currently sits, so a plain tap works too.
///
/// Deliberately drag-only (no TapCallbacks): Flutter's gesture arena
/// resolves a drag recognizer as the winner for a stationary press just
/// as readily as for a moving one, so a component mixing in both ends up
/// with its drag recognizer permanently starving the tap recognizer —
/// committing on [onDragEnd] instead sidesteps the arena conflict
/// entirely, since there's only one recognizer competing for the
/// pointer.
///
/// Hit-tests across the whole table (size = the full world), not just
/// the glass sprite, so aiming feels the same wherever you first touch
/// down.
class StagingComponent extends PositionComponent with DragCallbacks {
  StagingComponent({required double worldWidth, required double worldHeight, required this.spawnY, required this.onDrop}) {
    size = Vector2(worldWidth, worldHeight);
    position = Vector2.zero();
    _aimX = worldWidth / 2;
  }

  /// The y (world/meters) the staged glass hovers at and drops from.
  final double spawnY;

  /// Commits a drop at the current aim x.
  final void Function(double aimX) onDrop;

  Ingredient? _ingredient;
  double _radius = 0.2;
  double _aimX = 0;
  bool _visible = true;

  /// A short slide-up-and-pop-in for each newly staged glass — sells the
  /// throw cooldown (see MixolocoGame.kThrowCooldown) as the next item
  /// arriving into position, rather than just instantly appearing.
  static const _revealDuration = 0.22;
  double _revealElapsed = _revealDuration;

  Ingredient? get ingredient => _ingredient;

  set ingredient(Ingredient? value) {
    if (value != _ingredient) _revealElapsed = 0;
    _ingredient = value;
    _visible = true;
  }

  set radius(double value) => _radius = value;

  void hide() => _visible = false;

  double _clampAim(double x) => x.clamp(_radius, size.x - _radius);

  @override
  void update(double dt) {
    super.update(dt);
    if (_revealElapsed < _revealDuration) {
      _revealElapsed = (_revealElapsed + dt).clamp(0.0, _revealDuration);
    }
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (!_visible) return;
    _aimX = _clampAim(event.localPosition.x);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (!_visible) return;
    _aimX = _clampAim(_aimX + event.localDelta.x);
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (!_visible || _ingredient == null) return;
    onDrop(_aimX);
    hide();
  }

  @override
  void render(Canvas canvas) {
    if (!_visible) return;
    final glass = _ingredient;
    if (glass == null) return;
    _renderAimLine(canvas);
    final size = physicsVisualSize(_radius);

    final t = _revealDuration <= 0 ? 1.0 : (_revealElapsed / _revealDuration).clamp(0.0, 1.0);
    final eased = 1 - (1 - t) * (1 - t);
    // Rises from lower down (larger y, toward the near/staging edge) up
    // into its resting spawn position, popping up to full size as it
    // arrives rather than just appearing.
    final riseOffset = (1 - eased) * _radius * 1.6;
    final scale = 0.6 + 0.4 * eased;

    canvas.save();
    canvas.translate(_aimX, spawnY + riseOffset);
    canvas.scale(scale);
    canvas.translate(-size.width / 2, -size.height / 2);
    paintIngredient(canvas, glass, size);
    canvas.restore();
  }

  /// A soft guide from the staged glass to the far edge — always one
  /// straight line, never a bend. The table's side walls taper in to
  /// [kTableFarToNearWidthRatio] of the near width by the far edge (see
  /// TableBoundaryComponent), so "straight ahead" isn't vertical except
  /// exactly down the middle — off-center it's a straight line angled by
  /// that same taper, converging toward center by the far edge. A drop's
  /// actual flight matches this exactly (see
  /// MixolocoGame._laneAccelXFor), rather than traveling vertically and
  /// only deflecting once it happens to hit the angled wall.
  void _renderAimLine(Canvas canvas) {
    final worldWidth = size.x;
    final startY = spawnY - _radius * 1.3;
    if (startY <= kTableFarInset) return;

    final center = worldWidth / 2;
    final farX = center + (_aimX - center) * kTableFarToNearWidthRatio;

    final path = Path()
      ..moveTo(_aimX, startY)
      ..lineTo(farX, kTableFarInset);

    // Deliberately subtle — reads as a shadow cast on the table, not a
    // bright targeting reticle.
    final paint = Paint()
      ..color = const Color(0x2A000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.03
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.01);
    canvas.drawPath(path, paint);
  }
}
