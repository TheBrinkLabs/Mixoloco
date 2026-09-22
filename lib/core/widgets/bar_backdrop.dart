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

  /// The top-of-screen sign with the logo/HUD row on it — gameplay and
  /// the main menu both want it, but a full wood-plank list screen (Best
  /// Scores, Settings) already opens with its own title plank right at
  /// the top, so a second, emptier board above that just reads as dead
  /// space — those screens turn this off.
  final bool showHeaderBoard;

  /// Which scene photo sits behind everything — the beach bar by
  /// default; GameScreen swaps this to the rooftop bar once a run
  /// reaches level 2 (every cocktail plus the jug completed).
  final String backgroundAssetPath;

  /// Swaps the table art and header board for their Level 2
  /// counterparts (bar_table.png, and two menu_board_2.png planks in
  /// place of the single header_board.png) — see _TableGeometry and
  /// _HeaderBoard. Every screen defaults to false (the beach bar);
  /// GameScreen is the only caller that ever passes true, and only once
  /// board.level >= 2.
  final bool rooftop;

  const BarBackdrop({
    super.key,
    this.child,
    this.shakeTrigger,
    this.showTable = true,
    this.showHeaderBoard = true,
    this.backgroundAssetPath = 'assets/images/beach_background.png',
    this.rooftop = false,
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
        ),
        if (showHeaderBoard) _HeaderBoard(rooftop: rooftop),
        if (showTable) _TableImage(shakeTrigger: shakeTrigger, rooftop: rooftop),
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

/// menu_board.png, cropped tight to its own opaque content — shared by
/// the in-game Cocktail Menu overlay (one plank per recipe row).
const kMenuBoardAspect = 1967 / 459;

/// menu_board_3.png, cropped with *zero* margin (not the usual ~6%) so
/// stacked/adjacent boards can sit flush with no visible seam between
/// them — a mossier, more detailed alternative to menu_board.png, used
/// on Settings and Best Scores.
const kMenuBoard3Aspect = 1045 / 281;

/// menu_board_white.png, cropped the same zero-margin way as
/// menu_board_3.png — a whitewashed-plank alternative being trialled on
/// just the main menu's five option tiles for now. The source photo
/// this second version was replaced with was shot in portrait (a tall
/// vertical plank); cropped tight then rotated 90 degrees to the same
/// landscape orientation every other board asset uses, rather than
/// handling the rotation in code.
const kMenuBoardWhiteAspect = 1247 / 399;

/// empty_tab.png — the in-game progress-tabs row's background tile, and
/// the home screen's Credits/Level/Unlocked tab row. Cropped tight (zero
/// margin) so the wood block fills its own aspect exactly; the two
/// contexts want different amounts of breathing room around it though
/// (the small in-game row needs it edge-to-edge to read as a tile at
/// all; the bigger HUD row wants inset space) — baking one fixed margin
/// into the asset couldn't satisfy both, so each caller adds its own
/// padding instead (see _HudTab).
const kEmptyTabAspect = 1051 / 1022;

/// The on-screen rect the header board image occupies — top-anchored,
/// full width, height from its own aspect ratio (see [kHeaderBoardAspect])
/// — shared so HUD elements can be positioned precisely on top of it
/// instead of guessing independently of [_HeaderBoard]'s own layout.
Rect headerBoardRect(Size screenSize) {
  final width = screenSize.width;
  final height = width / kHeaderBoardAspect;
  return Rect.fromLTWH(0, kHeaderBoardTopInset, width, height);
}

/// A weathered wood-plank sign spanning the top of the screen, sitting
/// just shy of the true top edge (a thin sliver of the beach photo still
/// shows through above it) — a themed backdrop for the logo/HUD row that
/// screens layer on top of it. Sized off its own aspect ratio at full
/// screen width, so it never stretches.
///
/// [rooftop] swaps the asset for header_board_2.png (Level 2) — cropped
/// to nearly the same aspect ratio as header_board.png (1.966 vs 1.969),
/// so it renders the same way (BoxFit.fitWidth, own aspect) with no
/// further adjustment needed.
class _HeaderBoard extends StatelessWidget {
  final bool rooftop;
  const _HeaderBoard({required this.rooftop});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: kHeaderBoardTopInset,
      left: 0,
      right: 0,
      child: Image(
        image: AssetImage(rooftop ? 'assets/images/header_board_2.png' : 'assets/images/header_board.png'),
        fit: BoxFit.fitWidth,
        alignment: Alignment.topCenter,
      ),
    );
  }
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

_TableGeometry _tableGeometryFor(bool rooftop) => rooftop ? _barTableGeometry : _beachTableGeometry;

/// The real bar-table asset, scaled to the screen's full width (aspect
/// preserved, not stretched) and positioned so the base visible near the
/// bottom of the image lines up with kTableNearFraction of the screen —
/// matching where the tray strip below it starts. [rooftop] swaps both
/// the asset and its measurements (see [_barTableGeometry]) for Level 2.
class _TableImage extends StatefulWidget {
  final Listenable? shakeTrigger;
  final bool rooftop;
  const _TableImage({this.shakeTrigger, required this.rooftop});

  @override
  State<_TableImage> createState() => _TableImageState();
}

/// Drives the table's visual shake — a decaying wobble, in step with the
/// Shaker Maker's own duration (MixolocoGame._shakeDuration) so the table
/// looks like it's actually shaking rather than just the glasses on it.
/// Bumped 50% longer (1400ms -> 2100ms) alongside the physics shake.
class _TableImageState extends State<_TableImage> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2100));

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
        builder: (context, child) => Transform.translate(offset: _shakeOffset(_controller.value), child: child),
        child: Image.asset(geometry.assetPath, fit: BoxFit.fill),
      ),
    );
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
/// overall table stretch above (kTableScale).
const kTableFarToNearWidthRatio = 0.714;

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
double tableTopFraction(double screenWidth, double screenHeight, {bool rooftop = false}) =>
    _imageYFractionToScreenFraction(
      rooftop ? _barTableTopFraction : _beachTableTopFraction,
      screenWidth,
      screenHeight,
      _tableGeometryFor(rooftop),
    );

/// Screen-fraction where the tabletop's playing surface ends and the
/// front apron begins — the true near edge gameplay should stop at,
/// unlike [kTableNearFraction] which reaches past the apron to the
/// bottom of the whole table graphic.
double tableSurfaceNearFraction(double screenWidth, double screenHeight, {bool rooftop = false}) {
  final geometry = _tableGeometryFor(rooftop);
  return _imageYFractionToScreenFraction(geometry.surfaceNearFraction, screenWidth, screenHeight, geometry);
}
