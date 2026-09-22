import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/colorful_plank_text.dart';
import 'bar_backdrop.dart' show kMenuBoardAspect;

/// The single confirmed style every wood-plank label in the app now
/// uses (see colorful_plank_text.dart) — Luckiest Guy, the logo's own
/// blue->gold->orange gradient, no outline, a stepped "long cast"
/// shadow. Kept as one shared constant tuple rather than repeating
/// these four values at every call site.
const kPlankTextFont = PlankFont.luckiestGuy;
const kPlankTextVariant = PlankTextVariant.logoGradient;
const kPlankShadowStyle = PlankShadowStyle.longCast;
final kPlankIconColor = plankAccentColor(kPlankTextVariant);
const kPlankIconShadows = [Shadow(color: Colors.black38, blurRadius: 3, offset: Offset(1, 1.5))];

/// The shared wood-plank row background — every wood-plank row across
/// the app (main menu options, the in-game Cocktail Menu, Best Scores,
/// Settings) sits on one of these, sized to [width]/[height] (see
/// [kMenuBoardAspect]/[kMenuBoard3Aspect] for the aspect ratio that
/// keeps whichever [assetPath] is in use unstretched). Defaults to
/// menu_board.png (still what the in-game Cocktail Menu uses); Best
/// Scores and Settings pass menu_board_3.png instead, matching the main
/// menu's own option planks.
class WoodPlank extends StatelessWidget {
  final double width;
  final double height;
  final String assetPath;
  final Widget? child;
  const WoodPlank({super.key, required this.width, required this.height, this.assetPath = 'assets/images/menu_board.png', this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(assetPath, fit: BoxFit.fill),
          if (child != null) child!,
        ],
      ),
    );
  }
}

/// A title plank — centered text with a small mirrored icon flourish
/// either side — shared by every wood-plank list screen/overlay
/// (Cocktail Menu, Best Scores, Settings) so they read as the same
/// family of page rather than one-off layouts.
/// The circular "back to previous screen" button every pushed
/// wood-plank screen (Settings, Best Scores) shows top-left — shared
/// here rather than duplicated per screen since both copies were
/// pixel-identical. The glyph itself is our sunset gold->orange->coral
/// gradient (the same "orange combo" every plank label uses) via a
/// ShaderMask, in place of the old flat off-white icon.
class PlankBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const PlankBackButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: const Center(child: SizedBox(width: 19, height: 19, child: CustomPaint(painter: _PlankArrowPainter()))),
        ),
      ),
    );
  }
}

/// A thick, rounded back-arrow glyph — outline + gradient fill + soft
/// shadow, the exact same three layers [ColorfulPlankText] paints every
/// letter with — instead of Material's thin [Icons.arrow_back_rounded],
/// which read as a mismatched foreign font next to the chunky plank
/// lettering once just tinted orange.
class _PlankArrowPainter extends CustomPainter {
  const _PlankArrowPainter();

  Path _arrowPath(Size size) {
    final w = size.width;
    final h = size.height;
    final head = Path()
      ..moveTo(w * 0.04, h * 0.5)
      ..lineTo(w * 0.48, h * 0.14)
      ..lineTo(w * 0.48, h * 0.86)
      ..close();
    final shaft = Path()..addRRect(RRect.fromLTRBR(w * 0.4, h * 0.34, w * 0.98, h * 0.66, Radius.circular(h * 0.08)));
    return Path.combine(PathOperation.union, head, shaft);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _arrowPath(size);

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.shortestSide * 0.08);
    canvas.save();
    canvas.translate(size.width * 0.05, size.height * 0.08);
    canvas.drawPath(path, shadowPaint);
    canvas.restore();

    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.16
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF4A2410);
    canvas.drawPath(path, outlinePaint);

    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.sunsetGold, AppColors.sunsetOrange, AppColors.coral],
      ).createShader(Offset.zero & size);
    canvas.drawPath(path, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _PlankArrowPainter oldDelegate) => false;
}

/// A toggle styled to look carved/inset into the wood plank itself —
/// a dark recessed track and a black thumb — rather than Flutter's
/// stock [Switch], whose bright Material pill read as a jarring
/// foreign UI element sitting on top of the wood art. The active state
/// reads via a warm glow instead of a color change, since the track
/// stays dark either way.
class PlankToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final double height;
  const PlankToggle({super.key, required this.value, required this.onChanged, required this.height});

  @override
  Widget build(BuildContext context) {
    final trackHeight = height * 0.34;
    final trackWidth = trackHeight * 1.9;
    final thumbSize = trackHeight - 5;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: trackWidth,
        height: trackHeight,
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(trackHeight / 2),
          // Still a dark, recessed inset either way — just tinted toward
          // a deep green when on and a deep red when off, so the state
          // reads at a glance instead of needing the glow alone.
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: value ? const [Color(0xFF06140A), Color(0xFF163B1E)] : const [Color(0xFF1A0705), Color(0xFF3B1210)],
          ),
          border: Border.all(color: value ? const Color(0xFF3FA34D).withValues(alpha: 0.7) : const Color(0xFFB33A2E).withValues(alpha: 0.6), width: 1.2),
          boxShadow: [
            // A faint highlight along the bottom edge and a darker line
            // along the top — together they read as light catching a
            // groove cut into the wood rather than a flat sticker.
            BoxShadow(color: Colors.white.withValues(alpha: 0.08), offset: const Offset(0, 1), blurRadius: 0),
            BoxShadow(color: Colors.black.withValues(alpha: 0.5), offset: const Offset(0, -1), blurRadius: 1),
            BoxShadow(color: (value ? const Color(0xFF3FA34D) : const Color(0xFFB33A2E)).withValues(alpha: 0.35), blurRadius: 4),
          ],
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: thumbSize,
            height: thumbSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF4A4139), Color(0xFF0A0806)],
              ),
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 2, offset: Offset(0, 1))],
            ),
          ),
        ),
      ),
    );
  }
}

class WoodTitlePlank extends StatelessWidget {
  final String title;
  final IconData icon;
  final double width;
  final double height;
  final String assetPath;

  /// A real picture standing in for [icon] when set — the same custom
  /// art (trophy/gear) the main menu's own Best Scores/Settings tiles
  /// use, so those screens read as a continuation of the tile you
  /// tapped rather than falling back to a generic Material glyph.
  final String? iconAsset;
  const WoodTitlePlank({
    super.key,
    required this.title,
    required this.icon,
    required this.width,
    required this.height,
    this.assetPath = 'assets/images/menu_board.png',
    this.iconAsset,
  });

  @override
  Widget build(BuildContext context) {
    final iconSize = height * 0.32;
    // 20% bigger than the plain Material glyph it replaces — the real
    // artwork carries more visual weight than a thin icon outline, so
    // it reads better with some extra room.
    final imageIconSize = height * 0.48;
    final iconWidget = iconAsset != null
        ? Image.asset(iconAsset!, width: imageIconSize, height: imageIconSize, fit: BoxFit.contain)
        : Icon(icon, size: iconSize, color: kPlankIconColor, shadows: kPlankIconShadows);
    return WoodPlank(
      width: width,
      height: height,
      assetPath: assetPath,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconWidget,
            const SizedBox(width: 10),
            // Flexible (not a bare child) — gives ColorfulPlankText's
            // own Wrap a real bounded width to measure against, so a
            // translation that runs wider than the English original
            // (e.g. "Mejores Puntuaciones") actually wraps to a second
            // line instead of overflowing past the plank's edge.
            Flexible(
              child: ColorfulPlankText(
                text: title,
                fontSize: height * 0.26,
                variant: kPlankTextVariant,
                font: kPlankTextFont,
                shadowStyle: kPlankShadowStyle,
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
