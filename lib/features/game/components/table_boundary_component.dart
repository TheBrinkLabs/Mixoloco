import 'package:flame_forge2d/flame_forge2d.dart';
import '../../../core/widgets/bar_backdrop.dart' show kTableFarToNearWidthRatio;
import '../mixoloco_game.dart';

/// How far the floor sits from the true far edge (y = 0). An item's
/// physics circle always rests fully inside this line, but the art is
/// drawn a bit bigger than its circle (see kIngredientVisualPad, for
/// the touching-items gap) — this needs to be generous enough that
/// even the largest tier's oversized art doesn't hang more than about
/// half off the true table edge. Shared (not private) so StagingComponent
/// can trace the same funnel shape for its aim line.
const kTableFarInset = 0.34;

/// The static table surface. The table art itself is drawn in perspective
/// — a trapezoid, full width at the near/staging edge and only
/// [kTableFarToNearWidthRatio] as wide at the far edge — so the physics
/// boundary matches that shape with slanted side walls rather than a
/// plain rectangle; a straight-sided physics world let items rest
/// visibly outside the actual wood surface near the far edge, where the
/// art has already tapered in. The slant alone is what funnels a drop
/// toward the middle as it nears the back, same as the real table would
/// — no separate sideways-pulling floor needed.
///
/// Invisible (renderBody: false) — the table art itself is the visual,
/// this is only the physics shape sitting on top of it.
class TableBoundaryComponent extends BodyComponent<MixolocoGame> {
  TableBoundaryComponent({required this.worldWidth, required this.worldHeight}) : super(renderBody: false);

  final double worldWidth;
  final double worldHeight;

  @override
  Body createBody() {
    final bodyDef = BodyDef(position: Vector2.zero());
    final body = world.createBody(bodyDef);
    final shapeDef = ShapeDef(material: SurfaceMaterial(friction: 0.55));

    final farWidth = worldWidth * kTableFarToNearWidthRatio;
    final farLeft = (worldWidth - farWidth) / 2;
    final farRight = farLeft + farWidth;

    body.createShape(Segment(point1: Vector2(farLeft, kTableFarInset), point2: Vector2(farRight, kTableFarInset)), shapeDef);
    // Side walls slant inward from the full-width near edge to the
    // narrower far edge, matching the table art's own perspective.
    body.createShape(Segment(point1: Vector2(0, worldHeight), point2: Vector2(farLeft, kTableFarInset)), shapeDef);
    body.createShape(Segment(point1: Vector2(worldWidth, worldHeight), point2: Vector2(farRight, kTableFarInset)), shapeDef);
    // Near/staging edge — keeps a jostled pile (or a drop aimed right at
    // the edge) from ever leaving the visible play area at the bottom.
    body.createShape(Segment(point1: Vector2(0, worldHeight), point2: Vector2(worldWidth, worldHeight)), shapeDef);

    return body;
  }
}
