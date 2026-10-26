import 'dart:math';
import 'package:flutter/material.dart';

/// Fraction of screen height where the table's near/wide edge (its base)
/// sits — shared with callers that need to position their own UI (e.g.
/// a Play button) exactly within the tray strip below it, and with
/// _TableImage to line the real table asset's own base up with the same
/// line, rather than guessing at a matching value independently.
const kTableNearFraction = 1.0;

/// How much bigger than "exactly screen width" the table asset renders
/// at — anchored at its base (kTableNearFraction stays fixed), so
/// scaling this up both widens the near edge until it reaches/exceeds
/// the screen edges AND pushes the table's top further up the screen,
/// in one change (a fixed-bottom-anchor scale-up moves the top edge up
/// as it grows). 1.2 was picked to land the near edge just past the
/// screen edges — see _TableImage's own measured content-width comment
/// for why the source image alone (no scale) falls just short of that.
/// Bumped 5% further (1.2 -> 1.26) per feedback that the table felt too
/// small — since the base stays anchored, that stretch shows up entirely
/// as the top edge (and the play area within it) reaching further up the
/// screen.
const kTableScale = 1.26;

/// The scene photo for [level] — beach (1), rooftop (2), safari (3),
/// piazza (4), jungle (5 and, until further levels get their own art,
/// anything beyond it too). Shared by GameScreen (the live table) and
/// LevelUpOverlay (the between-levels "ready" screen), so both always
/// agree on which photo a given level shows.
String backgroundAssetPathForLevel(int level) {
  if (level >= 5) return 'assets/images/jungle_background.png';
  if (level >= 4) return 'assets/images/piazza_background.png';
  if (level >= 3) return 'assets/images/safari_background.png';
  if (level >= 2) return 'assets/images/rooftop_background.png';
  return 'assets/images/beach_background.png';
}

/// Six colour treatments for the table art, per the gameplay redesign
/// handoff (design_handoff_game_screen/README.md, "Recolour per level")
/// — the table's own geometry/measurements never change, only how it's
/// tinted at paint time (see [colorFilterForTableFinish]).
enum TableFinish {
  natural,
  sunBleached,
  driftwood,
  darkTeak,
  turquoisePaint,
  coralPaint,
}

/// Which [TableFinish] level [level] uses. Level 1 (beach) keeps the
/// table's own natural photo colour; a placeholder one-finish-per-level
/// mapping beyond that until later levels get their own bespoke choice —
/// easy to retune without touching the tinting math itself.
TableFinish tableFinishForLevel(int level) {
  if (level >= 5) return TableFinish.driftwood;
  if (level >= 4) return TableFinish.coralPaint;
  if (level >= 3) return TableFinish.turquoisePaint;
  if (level >= 2) return TableFinish.darkTeak;
  return TableFinish.natural;
}

/// [ColorFilter.matrix] values for each [TableFinish], approximating the
/// CSS `saturate()`/`brightness()`/`sepia()`/`hue-rotate()` filter chains
/// the README specifies, composed via the standard SVG/CSS filter-matrix
/// formulas (one matrix multiplication per step in each chain, computed
/// once here rather than re-derived at runtime). "Slight sepia" is taken
/// as a 30% blend toward full sepia.
const _tableFinishMatrices = <TableFinish, List<double>>{
  // saturate(0.55), brightness(1.18)
  TableFinish.sunBleached: [
    0.762103,
    0.379665,
    0.038232,
    0,
    0,
    0.113103,
    1.028665,
    0.038232,
    0,
    0,
    0.113103,
    0.379665,
    0.687232,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ],
  // saturate(0.25), sepia(0.3), brightness(1.08)
  TableFinish.driftwood: [
    0.411528,
    0.702446,
    0.079771,
    0,
    0,
    0.211305,
    0.858987,
    0.075480,
    0,
    0,
    0.191299,
    0.611495,
    0.256828,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ],
  // saturate(1.25), sepia(0.3), brightness(0.62)
  TableFinish.darkTeak: [
    0.597378,
    0.056297,
    0.031608,
    0,
    0,
    0.046116,
    0.584425,
    0.027220,
    0,
    0,
    0.030849,
    0.015418,
    0.562008,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ],
  // sepia(1), hue-rotate(140deg), saturate(1.5)
  TableFinish.turquoisePaint: [
    0.228725,
    0.452357,
    0.110346,
    0,
    0,
    0.384355,
    0.753438,
    0.184872,
    0,
    0,
    0.407017,
    0.801451,
    0.195872,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ],
  // sepia(1), hue-rotate(-28deg), saturate(2.2)
  TableFinish.coralPaint: [
    0.514421,
    1.004864,
    0.247213,
    0,
    0,
    0.316357,
    0.622880,
    0.152371,
    0,
    0,
    0.237416,
    0.462938,
    0.114258,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ],
};

/// Null for [TableFinish.natural] (no filter — paint the table art as-is)
/// rather than an identity matrix, so the common case skips wrapping the
/// image in a [ColorFiltered] at all.
ColorFilter? colorFilterForTableFinish(TableFinish finish) {
  final matrix = _tableFinishMatrices[finish];
  return matrix == null ? null : ColorFilter.matrix(matrix);
}

/// The tropical sunset beach-bar scene behind the menu/game screens — a
/// real photo background (assets/images/beach_background.png) with the
/// real table asset layered on top, positioned so its own base lines up
/// with the true bottom of the screen (kTableNearFraction = 1.0) — no
/// separate tray strip below it; the table's own front face is the
/// bottom of the screen.
class BarBackdrop extends StatelessWidget {
  final Widget? child;

  /// Bumped (any change fires it) to play a brief shake animation on the
  /// table image — used to back the Shaker Maker purchase's physics
  /// jostle with a matching visual "the table's actually shaking" cue.
  final Listenable? shakeTrigger;

  /// The menu screen's own redesign dropped the table graphic entirely
  /// (its menu options now live on their own wooden planks instead of
  /// floating on the tabletop) — everywhere else (gameplay, high scores)
  /// still wants it, so this defaults to showing it.
  final bool showTable;

  /// Which scene photo sits behind everything — the beach bar by
  /// default; GameScreen swaps this to the rooftop bar once a run
  /// reaches level 2 (every cocktail plus the jug completed).
  final String backgroundAssetPath;

  /// Swaps the table art for its Level 2 counterpart (bar_table.png) —
  /// see _TableGeometry. Every screen defaults to false (the beach
  /// bar); GameScreen is the only caller that ever passes true, and
  /// only once board.level >= 2.
  final bool rooftop;

  /// Tints the table art per [TableFinish] — see
  /// colorFilterForTableFinish. Defaults to natural (no tint); the table's
  /// own geometry/measurements are never affected by this.
  final TableFinish tableFinish;

  const BarBackdrop({
    super.key,
    this.child,
    this.shakeTrigger,
    this.showTable = true,
    this.backgroundAssetPath = 'assets/images/beach_background.png',
    this.rooftop = false,
    this.tableFinish = TableFinish.natural,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          backgroundAssetPath,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          // Source art is shot taller than any phone's aspect ratio (so
          // BoxFit.cover always has width-constrained slack to crop off
          // vertically) — decoding at full resolution wastes several
          // times the pixels this ever actually renders. See
          // GlassVisual's matching comment.
          cacheWidth: (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).round(),
        ),
        if (showTable)
          _TableImage(
            shakeTrigger: shakeTrigger,
            rooftop: rooftop,
            finish: tableFinish,
          ),
        if (child != null) child!,
      ],
    );
  }
}

/// How far the header board's top sits from the true top of the screen —
/// a thin sliver of the beach photo still shows through above it.
const kHeaderBoardTopInset = 3.0;

/// header_board.png, cropped tight to its own opaque content (it had
/// substantial transparent padding in the original canvas — sizing
/// against the raw canvas aspect badly overestimated how tall the actual
/// visible board is) — shared so any caller sizing art against the
/// board's own aspect ratio doesn't need to hardcode it independently.
const kHeaderBoardAspect = 1130 / 574;

/// menu_board.png's own aspect ratio — the wooden-plank graphic itself
/// was removed once the in-game Cocktail Menu overlay's rows were
/// rebuilt on the gold-rimmed blue tile style (see game_screen.dart's
/// _MenuListRow), but that row's height math still derives from this
/// same ratio for its own proportions, same reasoning headerBoardRect
/// keeps [kHeaderBoardAspect] around after header_board.png's removal.
const kMenuBoardAspect = 1967 / 459;

/// empty_tab.png — the in-game progress-tabs row's background tile, and
/// the home screen's Credits/Level/Unlocked tab row. Cropped tight (zero
/// margin) so the wood block fills its own aspect exactly; the two
/// contexts want different amounts of breathing room around it though
/// (the small in-game row needs it edge-to-edge to read as a tile at
/// all; the bigger HUD row wants inset space) — baking one fixed margin
/// into the asset couldn't satisfy both, so each caller adds its own
/// padding instead (see _HudTab).
const kEmptyTabAspect = 1051 / 1022;

/// The on-screen rect the header board image *would* occupy — top-
/// anchored, full width, height from its own aspect ratio (see
/// [kHeaderBoardAspect]). The header board graphic itself was removed
/// (nothing passes `showHeaderBoard: true` anymore, every screen opens
/// with its own title instead), but GameScreen still anchors its HUD
/// row against this same rect, so the math stays as pure positioning
/// reference rather than being inlined per caller.
Rect headerBoardRect(Size screenSize) {
  final width = screenSize.width;
  final height = width / kHeaderBoardAspect;
  return Rect.fromLTWH(0, kHeaderBoardTopInset, width, height);
}

/// Per-table-asset measurements — everything [_TableImage] and the
/// screen-fraction helpers below need to position an asset whose raw
/// canvas has its own amount of transparent padding, without hardcoding
/// which asset is active.
class _TableGeometry {
  final String assetPath;
  final double imageAspect;
  final double baseFraction;
  final double surfaceNearFraction;
  const _TableGeometry({
    required this.assetPath,
    required this.imageAspect,
    required this.baseFraction,
    required this.surfaceNearFraction,
  });
}

/// assets/images/beach_table.png — 768x1365 raw canvas. Content doesn't
/// fill that canvas edge to edge — measured precisely by scanning the
/// PNG's own alpha channel (not eyeballed): opaque content runs from
/// y=480 to y=1364 (fractions 0.3516 to 0.9993 of height) and x=28 to
/// x=740 (fractions 0.0365 to 0.9635 of width).
///
/// That 0.9993 bound is the bottom of the *whole* graphic though — the
/// wood-grain playing surface itself ends well above that, at the front
/// apron block's top edge (see [surfaceNearFraction]) — found by
/// scanning for the row where the opaque width suddenly narrows (the
/// taper's widest lip, right before the apron's straight-sided block
/// begins): that happens right at y=1199, fraction 0.878.
const _beachTableGeometry = _TableGeometry(
  assetPath: 'assets/images/beach_table.png',
  imageAspect: 768 / 1365,
  baseFraction: 0.9993,
  surfaceNearFraction: 0.878,
);

/// assets/images/bar_table.png — 1080x1920 raw canvas, same measurement
/// method as [_beachTableGeometry]: opaque content runs y=650-1855
/// (fractions 0.3385-0.9661), the front-lip/apron transition (scanned
/// visually against a zoomed crop, since this asset's apron doesn't
/// narrow in width the way beach_table.png's does — the two are viewed
/// from a slightly different angle) sits at fraction 0.878 — remarkably,
/// the exact same fraction as the beach table's own.
const _barTableGeometry = _TableGeometry(
  assetPath: 'assets/images/bar_table.png',
  imageAspect: 1080 / 1920,
  baseFraction: 0.9661,
  surfaceNearFraction: 0.878,
);

_TableGeometry _tableGeometryFor(bool rooftop) =>
    rooftop ? _barTableGeometry : _beachTableGeometry;

/// The real bar-table asset, scaled to the screen's full width (aspect
/// preserved, not stretched) and positioned so the base visible near the
/// bottom of the image lines up with kTableNearFraction of the screen —
/// matching where the tray strip below it starts. [rooftop] swaps both
/// the asset and its measurements (see [_barTableGeometry]) for Level 2.
class _TableImage extends StatefulWidget {
  final Listenable? shakeTrigger;
  final bool rooftop;
  final TableFinish finish;
  const _TableImage({
    this.shakeTrigger,
    required this.rooftop,
    this.finish = TableFinish.natural,
  });

  @override
  State<_TableImage> createState() => _TableImageState();
}

/// Drives the table's visual shake — a decaying wobble, in step with the
/// Shaker Maker's own duration (MixolocoGame._shakeDuration) so the table
/// looks like it's actually shaking rather than just the glasses on it.
/// Bumped 50% longer (1400ms -> 2100ms) alongside the physics shake.
class _TableImageState extends State<_TableImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2100),
  );

  @override
  void initState() {
    super.initState();
    widget.shakeTrigger?.addListener(_onShake);
  }

  @override
  void didUpdateWidget(covariant _TableImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shakeTrigger != widget.shakeTrigger) {
      oldWidget.shakeTrigger?.removeListener(_onShake);
      widget.shakeTrigger?.addListener(_onShake);
    }
  }

  void _onShake() => _controller.forward(from: 0);

  @override
  void dispose() {
    widget.shakeTrigger?.removeListener(_onShake);
    _controller.dispose();
    super.dispose();
  }

  Offset _shakeOffset(double t) {
    final decay = 1 - t;
    final wobble = sin(t * 26) * decay;
    // Amplitude doubled ("twice as aggressive") alongside the physics shake.
    return Offset(wobble * 14, wobble * 6);
  }

  @override
  Widget build(BuildContext context) {
    final geometry = _tableGeometryFor(widget.rooftop);
    final size = MediaQuery.sizeOf(context);
    final displayWidth = size.width * kTableScale;
    final displayHeight = displayWidth / geometry.imageAspect;
    final targetBaseY = size.height * kTableNearFraction;
    final topOffset = targetBaseY - displayHeight * geometry.baseFraction;
    return Positioned(
      left: (size.width - displayWidth) / 2,
      top: topOffset,
      width: displayWidth,
      height: displayHeight,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Transform.translate(
          offset: _shakeOffset(_controller.value),
          child: child,
        ),
        child: _tintedTable(geometry.assetPath, widget.finish, displayWidth),
      ),
    );
  }

  Widget _tintedTable(String assetPath, TableFinish finish, double displayWidth) {
    final image = Image.asset(
      assetPath,
      fit: BoxFit.fill,
      // See BarBackdrop's matching comment — this table only ever
      // renders at displayWidth, well under the source art's own size.
      cacheWidth: (displayWidth * MediaQuery.devicePixelRatioOf(context)).round(),
    );
    final filter = colorFilterForTableFinish(finish);
    if (filter == null) return image;
    // The tinted table sits directly beneath the live Flame game canvas,
    // which repaints every physics frame — without a boundary here,
    // ColorFiltered's own (comparatively costly on a mid-range GPU)
    // matrix pass can get swept into that same repaint every frame even
    // though the table art/tint itself never actually changes outside
    // the brief shake animation above. Isolating it as its own
    // compositor layer lets that layer be cached and reused frame to
    // frame — the shake's Transform.translate (applied by the caller,
    // outside this widget) repositions the cached layer cheaply rather
    // than needing the tint reapplied.
    return RepaintBoundary(child: ColorFiltered(colorFilter: filter, child: image));
  }
}

/// Local (image-space) y-fraction where each table's own visible content
/// begins — the far/back edge of the playing surface — passed to
/// [tableTopFraction]. Beach: measured content starts at 0.3516, but a
/// small hand-tuned margin above that (0.3365) reads better in play;
/// bar_table.png's own measured content start (0.3385) needed no such
/// adjustment, close enough to beach's tuned value already.
const _beachTableTopFraction = 0.3365;
const _barTableTopFraction = 0.3385;

/// Width of the tabletop's playing surface at its far edge, as a fraction
/// of its width at the near edge — i.e. farWidth / nearWidth. The raw
/// pixel measurement (scanning for the near edge's widest point, the lip
/// at [_surfaceNearFraction]) came out to ~0.556, but that read as a
/// harsher taper in play than the art itself looks — items in the
/// distance felt too small and the far edge too narrow — so this is
/// deliberately softened toward the art's measured ratio rather than
/// matching it exactly. Gameplay geometry (lane grid, glass spacing/size
/// by depth) uses this so the board's perspective is dramatic without
/// crushing the far rows. Widened an extra 5% (0.68 -> 0.714) per
/// feedback that the far end specifically felt tight, on top of the
/// overall table stretch above (kTableScale), then widened again
/// (0.714 -> 0.76 -> 0.85) per feedback that visible table wood at the
/// back corners still sat outside where items could actually reach.
const kTableFarToNearWidthRatio = 0.85;

/// How strongly the aim guide/thrown-item's sideways drift converges
/// toward center as it travels to the far edge — see
/// StagingComponent._renderAimLine and IngredientBodyComponent's throw
/// steering. Deliberately its own constant, not
/// [kTableFarToNearWidthRatio]: that one governs where the actual side
/// walls sit (repeatedly widened this session, per feedback, up from an
/// original 0.714 to today's 0.85, which leaves the walls themselves
/// much closer to vertical than they started), but the *visual* "aims
/// inward with distance" cue got noticeably weaker along with it.
/// Started back at that original 0.714, then pulled in further per
/// feedback that even that read as too straight — always stronger
/// (smaller ratio) than kTableFarToNearWidthRatio, so the predicted
/// line/landing spot is always safely inside the real wall, never past
/// it.
const kAimConvergenceRatio = 0.6;

/// Maps a y-fraction in the active table PNG's own local space (0 = top
/// of image, 1 = bottom) to a fraction of the screen, using the same
/// scale/position math [_TableImage] uses to place the asset itself —
/// shared so every caller that needs a line on the table (the playing
/// surface's top or near edge) agrees with where the art actually is.
double _imageYFractionToScreenFraction(
  double imageLocalYFraction,
  double screenWidth,
  double screenHeight,
  _TableGeometry geometry,
) {
  final displayWidth = screenWidth * kTableScale;
  final displayHeight = displayWidth / geometry.imageAspect;
  final targetBaseY = screenHeight * kTableNearFraction;
  final topOffset = targetBaseY - displayHeight * geometry.baseFraction;
  return (topOffset + displayHeight * imageLocalYFraction) / screenHeight;
}

/// Screen-fraction where the table's own visible (opaque) surface begins
/// — the far/back edge — derived from the measured alpha bounds so other
/// widgets (the ingredient showcase, gameplay pieces) can stay safely
/// within the table's actual surface instead of guessing independently.
/// [rooftop] picks bar_table.png's own measurements over beach_table.png's.
double tableTopFraction(
  double screenWidth,
  double screenHeight, {
  bool rooftop = false,
}) => _imageYFractionToScreenFraction(
  rooftop ? _barTableTopFraction : _beachTableTopFraction,
  screenWidth,
  screenHeight,
  _tableGeometryFor(rooftop),
);

/// Screen-fraction where the tabletop's playing surface ends and the
/// front apron begins — the true near edge gameplay should stop at,
/// unlike [kTableNearFraction] which reaches past the apron to the
/// bottom of the whole table graphic.
double tableSurfaceNearFraction(
  double screenWidth,
  double screenHeight, {
  bool rooftop = false,
}) {
  final geometry = _tableGeometryFor(rooftop);
  return _imageYFractionToScreenFraction(
    geometry.surfaceNearFraction,
    screenWidth,
    screenHeight,
    geometry,
  );
}
