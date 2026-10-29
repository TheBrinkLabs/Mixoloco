import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../theme/outlined_label.dart';

/// Shared design tokens from the main-menu redesign handoff
/// (design_handoff_main_menu/README.md) — colours that don't already have
/// a home in [AppColors] because nothing outside the redesigned menu/game
/// HUDs uses them. Shared (not screen-private) because the gameplay HUD
/// redesign reuses the exact same pill/coin/badge look — see
/// design_handoff_game_screen/README.md: "It uses the same visual
/// language as the main menu... Reuse that package's OutlinedLabel, pill
/// and coin widgets."
abstract class HudColors {
  static const hudNavyTop = Color(0xFF235A8A);
  static const hudNavyBottom = Color(0xFF163A5F);
  static const hudBorder = Color(0xFF0B2238);
  static const labelStroke = Color(0xFF173A5E);
  static const goldTop = Color(0xFFFFE680);
  static const goldMid = Color(0xFFF7A617);
  static const goldBottom = Color(0xFFD9780A);
  static const goldNumberStroke = Color(0xFF8A4300);
  static const coinTop = Color(0xFFFFF3A8);
  static const coinMid = Color(0xFFFFC928);
  static const coinBottom = Color(0xFFE08A00);
  static const coinRim = Color(0xFF8A4B00);
  static const coinMark = Color(0xFFFFF6C4);
  static const coinMarkBorder = Color(0xFFC87500);
  static const greenTop = Color(0xFF9CF06A);
  static const greenMid = Color(0xFF56C83A);
  static const greenBottom = Color(0xFF2F9E27);
  static const greenEdge = Color(0xFF155A17);
  static const plusTop = Color(0xFF8FE35A);
  static const plusBottom = Color(0xFF3EAA2C);
  static const plusBorder = Color(0xFF17501A);
  static const playSubLabel = Color(0xFFEAFFD8);
  static const creamTop = Color(0xFFFFFFFF);
  static const creamBottom = Color(0xFFFFE1A1);
  static const creamInnerTop = Color(0xFFFFFBEA);
  static const creamInnerBottom = Color(0xFFFFD88A);
  static const aboutStroke = Color(0xFF2B1A14);

  // v3 main-menu tile row / settings button (design_handoff_main_menu_v3).
  static const goldRim = Color(0xFFFFC94A);
  static const plateTop = Color(0xFF2F72AA);
  static const plateMid = Color(0xFF1A4670);
  static const plateBottom = Color(0xFF143A5E);
  static const settingsPlateTop = Color(0xFF2B6AA0);
  static const ribbonTop = Color(0xFFFFD95E);
  static const ribbonBottom = Color(0xFFF39A12);
  static const ribbonStroke = Color(0xFF7A3A00);
  static const badgeRed = Color(0xFFE8332F);
  static const badgeRedEdge = Color(0xFF7A1010);
}

/// One drop-shadow/highlight pass behind a [ShadowedAsset] — a tinted,
/// optionally blurred silhouette of the same art, offset underneath it.
class SpriteShadow {
  final Offset offset;
  final Color color;
  final double blur;
  const SpriteShadow({required this.offset, required this.color, this.blur = 0});
}

/// An image with one or more [SpriteShadow] passes painted behind it —
/// used throughout the redesign for the "white edge + soft drop" look on
/// icon art, since a plain PNG's alpha shape doesn't get a BoxShadow for
/// free the way a rectangular Container does.
class ShadowedAsset extends StatefulWidget {
  final String path;
  final double width;
  final double? height;
  final List<SpriteShadow> shadows;
  final double rotation;
  final VoidCallback? onTap;

  const ShadowedAsset({
    super.key,
    required this.path,
    required this.width,
    this.height,
    this.shadows = const [],
    this.rotation = 0,
    this.onTap,
  });

  @override
  State<ShadowedAsset> createState() => _ShadowedAssetState();
}

/// The live composition (a ColorFiltered layer per shadow, plus an
/// ImageFiltered blur) costs an offscreen render pass per layer on every
/// frame anything on screen repaints — and the game table repaints every
/// frame. So each distinct icon/size/shadow combination is rendered once
/// into a single image, cached app-wide, and drawn as a plain texture from
/// then on; the live version only shows for the first frame or two.
class _ShadowedAssetState extends State<ShadowedAsset> {
  static final Map<String, ui.Image> _baked = {};
  static final Map<String, Future<ui.Image?>> _baking = {};

  String? _key;
  ui.Image? _image;
  double _margin = 0;

  double get _h => widget.height ?? widget.width;

  double _marginFor(List<SpriteShadow> shadows) {
    var m = 0.0;
    for (final s in shadows) {
      final reach = (s.offset.dx.abs() > s.offset.dy.abs() ? s.offset.dx.abs() : s.offset.dy.abs()) + s.blur * 3;
      if (reach > m) m = reach;
    }
    return m + 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureBaked();
  }

  @override
  void didUpdateWidget(covariant ShadowedAsset oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureBaked();
  }

  void _ensureBaked() {
    if (widget.shadows.isEmpty) return;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final key = [
      widget.path,
      widget.width,
      _h,
      dpr,
      for (final s in widget.shadows) '${s.offset.dx},${s.offset.dy},${s.blur},${s.color.toARGB32()}',
    ].join('|');
    if (key == _key) return;
    _key = key;
    _margin = _marginFor(widget.shadows);
    _image = _baked[key];
    if (_image != null) return;
    final future = _baking[key] ??= _bake(widget.path, widget.width, _h, dpr, widget.shadows, _margin);
    future.then((img) {
      _baking.remove(key);
      if (img == null) return;
      _baked[key] = img;
      if (mounted && _key == key) setState(() => _image = img);
    });
  }

  static Future<ui.Image?> _bake(
    String path,
    double w,
    double h,
    double dpr,
    List<SpriteShadow> shadows,
    double margin,
  ) async {
    try {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: (w * dpr).round(),
      );
      final src = (await codec.getNextFrame()).image;
      final outW = ((w + margin * 2) * dpr).ceil();
      final outH = ((h + margin * 2) * dpr).ceil();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final srcRect = Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble());
      final fitted = applyBoxFit(BoxFit.contain, srcRect.size, Size(w * dpr, h * dpr));
      final dest = Alignment.center.inscribe(
        fitted.destination,
        Rect.fromLTWH(margin * dpr, margin * dpr, w * dpr, h * dpr),
      );
      final bounds = Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble());
      for (final s in shadows) {
        final layerPaint = Paint()..colorFilter = ColorFilter.mode(s.color, BlendMode.srcIn);
        if (s.blur > 0) {
          layerPaint.imageFilter = ui.ImageFilter.blur(sigmaX: s.blur * dpr, sigmaY: s.blur * dpr);
        }
        canvas.saveLayer(bounds, layerPaint);
        canvas.drawImageRect(src, srcRect, dest.shift(s.offset * dpr), Paint()..filterQuality = FilterQuality.medium);
        canvas.restore();
      }
      canvas.drawImageRect(src, srcRect, dest, Paint()..filterQuality = FilterQuality.medium);
      final picture = recorder.endRecording();
      final image = await picture.toImage(outW, outH);
      picture.dispose();
      src.dispose();
      return image;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    Widget content;
    if (image != null) {
      content = SizedBox(
        width: widget.width,
        height: _h,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -_margin,
              top: -_margin,
              width: widget.width + _margin * 2,
              height: _h + _margin * 2,
              child: RawImage(image: image, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
            ),
          ],
        ),
      );
    } else {
      content = _buildLive(context);
    }
    if (widget.rotation != 0) {
      content = Transform.rotate(angle: widget.rotation, child: content);
    }
    if (widget.onTap != null) content = GestureDetector(onTap: widget.onTap, child: content);
    return content;
  }

  Widget _buildLive(BuildContext context) {
    final path = widget.path;
    final width = widget.width;
    final shadows = widget.shadows;
    final h = _h;
    // See GlassVisual's matching comment — these sprites render far
    // smaller on screen than their source art's own resolution.
    final cw = (width * MediaQuery.devicePixelRatioOf(context)).round();
    // A missing/failed-to-load asset shouldn't render Flutter's default
    // red error box — doubly so here, where that box would otherwise
    // appear once per shadow layer plus once more for the real image on
    // top of it. Shadow layers just disappear (a missing drop-shadow is
    // invisible, not broken-looking); the real image falls back to a
    // plain icon so there's still *something* recognizable on screen.
    Widget missingShadowLayer(BuildContext _, Object _, StackTrace? _) => const SizedBox.shrink();
    Widget missingImage(BuildContext _, Object _, StackTrace? _) =>
        Icon(Icons.image_not_supported_outlined, size: width * 0.6, color: Colors.white54);

    Widget layer(SpriteShadow shadow) {
      final tinted = ColorFiltered(
        colorFilter: ColorFilter.mode(shadow.color, BlendMode.srcIn),
        child: Image.asset(path, width: width, height: h, fit: BoxFit.contain, cacheWidth: cw, errorBuilder: missingShadowLayer),
      );
      final blurred = shadow.blur > 0
          ? ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: shadow.blur, sigmaY: shadow.blur),
              child: tinted,
            )
          : tinted;
      return Transform.translate(offset: shadow.offset, child: blurred);
    }

    Widget content = SizedBox(
      width: width,
      height: h,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final shadow in shadows) layer(shadow),
          Image.asset(path, width: width, height: h, fit: BoxFit.contain, cacheWidth: cw, errorBuilder: missingImage),
        ],
      ),
    );
    return content;
  }
}

/// One ring in a [layeredCircle] — a solid colour or gradient band of
/// [width] wrapping whatever's nested inside it.
class HudRing {
  final double width;
  final Color? color;
  final Gradient? gradient;
  const HudRing({required this.width, this.color, this.gradient});
}

/// Builds a circle of exactly [size] diameter out of concentric rings
/// (outermost first) wrapping a [fill] — the badge style used throughout
/// the menu and gameplay HUDs (level/credits/unlocked/score/next), where a
/// plain `Border.all` can't express a *gradient* ring the way some of
/// these badges want.
Widget layeredCircle({
  required double size,
  required List<HudRing> rings,
  required Widget fill,
  List<BoxShadow>? shadow,
}) {
  final totalRingWidth = rings.fold<double>(0, (sum, r) => sum + r.width);
  final innerSize = (size - totalRingWidth * 2).clamp(0.0, size);
  Widget current = SizedBox(width: innerSize, height: innerSize, child: fill);
  for (final ring in rings.reversed) {
    current = Container(
      padding: EdgeInsets.all(ring.width),
      decoration: BoxDecoration(shape: BoxShape.circle, color: ring.color, gradient: ring.gradient),
      child: current,
    );
  }
  return Container(
    decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: shadow),
    child: current,
  );
}

/// The "wood board → blue tile" reskin's row background — replaces
/// [WoodPlank] on Settings/Shop/Guide/Rankings only (see each screen's
/// own call sites), matching gameplay's own `_NextCard` "NEXT" pill
/// exactly: a fully-rounded navy pill rather than the wood-grain plank
/// art. Same width/height/child shape as WoodPlank so call sites barely
/// change.
class BlueTile extends StatelessWidget {
  final double width;
  final double height;
  final Widget? child;
  const BlueTile({super.key, required this.width, required this.height, this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(color: HudColors.hudBorder, width: 2),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [HudColors.hudNavyTop, HudColors.hudNavyBottom],
        ),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), offset: const Offset(0, 4))],
      ),
      child: child,
    );
  }
}

/// [BlueTile]'s title-row variant — replaces [WoodTitlePlank] on the
/// same 4 screens, same icon/title/mirrored-icon layout, just white
/// outlined text on the new navy pill instead of the wood plank's
/// gradient-fill text.
class BlueTitleTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? iconAsset;
  final double width;
  final double height;
  final double fontScale;
  final double iconScale;
  const BlueTitleTile({
    super.key,
    required this.title,
    required this.icon,
    required this.width,
    required this.height,
    this.iconAsset,
    this.fontScale = 1.0,
    this.iconScale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final iconSize = height * 0.32;
    final imageIconSize = height * 0.48 * iconScale;
    final iconWidget = iconAsset != null
        ? Image.asset(
            iconAsset!,
            width: imageIconSize,
            height: imageIconSize,
            fit: BoxFit.contain,
            // See GlassVisual's matching comment.
            cacheWidth: (imageIconSize * MediaQuery.devicePixelRatioOf(context)).round(),
          )
        : Icon(icon, size: iconSize, color: Colors.white);
    return BlueTile(
      width: width,
      height: height,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconWidget,
            const SizedBox(width: 10),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: OutlinedLabel(
                  text: title,
                  fontSize: height * 0.26 * fontScale,
                  fill: Colors.white,
                  stroke: HudColors.hudBorder,
                  strokeWidth: 3,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Transform.flip(flipX: true, child: iconWidget),
          ],
        ),
      ),
    );
  }
}
