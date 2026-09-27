import 'package:flame_forge2d/flame_forge2d.dart';
import '../../../core/widgets/bar_backdrop.dart' show kTableFarToNearWidthRatio;
import '../mixoloco_game.dart';

/// How far the floor sits from the true far edge (y = 0). An item's
/// physics circle always rests fully inside this line, but the art is
/// drawn a bit bigger than its circle (see kIngredientVisualPad, for
/// the touching-items gap) — this needs to be generous enough that
/// even the largest tier's oversized art doesn't hang more than about
/// half off the true table edge. Shared (not private) so StagingComponent
/// can trace the same funnel shape for its aim line. Pulled in from an
/// original 0.34, first to 0.26 then further to 0.19, per feedback that
/// visible table wood sat unused behind where items could actually rest.
const kTableFarInset = 0.19;

/// How far down from the near edge the side walls' outward bulge sits,
/// as a fraction of the near-to-far depth (0 = near edge, 1 = far
/// corner) — see [kTableBulgeOutwardFactor].
const kTableBulgeDepthFraction = 0.35;

/// A straight taper from the near corners to the far corners can only
/// widen the near-to-middle region by also moving the far corners —
/// which were separately tuned already (see kTableFarToNearWidthRatio)
/// and shouldn't shift again just to fix the middle. Instead, each side
/// wall bends outward at [kTableBulgeDepthFraction] depth before
/// continuing on to the same far corner as before: this is how much
/// further out that bend point sits than a straight line would put it,
/// as a ratio (1.0 = no bulge/straight line; smaller = further out).
/// Added per feedback that the near-to-middle area still felt tight even
/// after the far corners' own position was separately widened, then
/// pulled back in slightly (0.82 -> 0.88) per feedback that it went a
/// little too far — items were going off-screen at the throwing end.
const kTableBulgeOutwardFactor = 0.88;

/// The static table surface. The table art itself is drawn in perspective
/// — a trapezoid, full width at the near/staging edge and only
/// [kTableFarToNearWidthRatio] as wide at the far edge — so the physics
/// boundary matches that shape with slanted side walls rather than a
/// plain rectangle; a straight-sided physics world let items rest
/// visibly outside the actual wood surface near the far edge, where the
/// art has already tapered in. The slant alone is what funnels a drop
/// toward the middle as it nears the back, same as the real table would
/// — no separate sideways-pulling floor needed. Each side wall is bent
/// outward partway down (see kTableBulgeOutwardFactor) rather than a
/// single straight segment, giving the near-to-middle region some extra
/// width a plain taper couldn't without also moving the far corners.
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
    final center = worldWidth / 2;

    // Distance from center a straight taper would put the wall at, at
    // the bulge's depth — then pushed further out by kTableBulgeOutwardFactor.
    final straightDistAtBulge = center * (1 - kTableBulgeDepthFraction) + (farWidth / 2) * kTableBulgeDepthFraction;
    final bulgeDist = straightDistAtBulge / kTableBulgeOutwardFactor;
    final bulgeY = worldHeight - (worldHeight - kTableFarInset) * kTableBulgeDepthFraction;
    final bulgeLeft = Vector2(center - bulgeDist, bulgeY);
    final bulgeRight = Vector2(center + bulgeDist, bulgeY);

    body.createShape(Segment(point1: Vector2(farLeft, kTableFarInset), point2: Vector2(farRight, kTableFarInset)), shapeDef);
    // Side walls: near corner -> outward bulge -> far corner, matching
    // the table art's own perspective while giving the near-to-middle
    // region some extra room a single straight taper couldn't.
    body.createShape(Segment(point1: Vector2(0, worldHeight), point2: bulgeLeft), shapeDef);
    body.createShape(Segment(point1: bulgeLeft, point2: Vector2(farLeft, kTableFarInset)), shapeDef);
    body.createShape(Segment(point1: Vector2(worldWidth, worldHeight), point2: bulgeRight), shapeDef);
    body.createShape(Segment(point1: bulgeRight, point2: Vector2(farRight, kTableFarInset)), shapeDef);
    // Near/staging edge — keeps a jostled pile (or a drop aimed right at
    // the edge) from ever leaving the visible play area at the bottom.
    body.createShape(Segment(point1: Vector2(0, worldHeight), point2: Vector2(worldWidth, worldHeight)), shapeDef);

    return body;
  }
}
