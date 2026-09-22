import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_theme.dart';

/// A handful of candidate replacements for the flat black/burnt wood-
/// engraved look (see wood_text_style.dart) — all built from the same
/// bold, rounded face the logo's own lettering echoes, just
/// filled/outlined/shadowed differently, so they can sit side by side on
/// one screen for a quick "which one" comparison before picking a single
/// style to roll out everywhere the old look was used.
enum PlankTextVariant {
  /// Warm gold->orange->coral gradient with a dark outline — pulls
  /// straight from the logo's "LOCO" half and the app's own sunset
  /// gradient (AppColors.gradientSunset).
  sunsetGradient,

  /// Cool sky->ocean blue gradient with a crisp white outline — the
  /// logo's "MIX" half.
  oceanGradient,

  /// Solid coral fill, thick white outline, a hard (unblurred) offset
  /// shadow instead of a soft one — reads as a chunky sticker rather
  /// than printed text.
  coralPop,

  /// Mirrors the real wordmark's own two-tone split rather than one
  /// smooth sweep across the whole label: the first word (or, for a
  /// single-word label, its first half) is blue with a *vertical*
  /// per-letter gradient — light blue up top, dark blue down low, the
  /// same shading each "MIX" letter has — while the second word/half
  /// gets its own vertical yellow-to-red gradient, echoing "LOCO"'s
  /// gold->orange run shaded the same top-to-bottom way.
  logoGradient,

  /// Cream fill, bold ocean-blue outline, soft shadow — an inverted
  /// take (light fill, colored line) instead of every other variant's
  /// colored-fill-plus-neutral-outline.
  creamOutline,

  /// Plain solid white, no gradient — for numbers (prices, ranks,
  /// scores). [logoGradient]'s blue/yellow-red split is meant for
  /// words; splitting a short number's digits in half between two
  /// unrelated colors just reads as broken, so numeric labels use this
  /// instead, keeping the same font/outline/shadow treatment.
  plainWhite,
}

/// Candidate display faces to trial the winning color treatment
/// (logoGradient) against — all bold/rounded "game logo" style faces
/// from Google Fonts (already a dependency), picked for variety rather
/// than closeness to any one look, so the comparison actually covers
/// different territory rather than five near-identical rounded faces.
enum PlankFont { fredoka, baloo2, titanOne, luckiestGuy, bangers }

/// Depth treatments to trial once the outline's dropped — with no
/// stroke doing the work of separating the letters from the background,
/// the shadow is the only thing left carrying that job, so it's worth
/// seeing several side by side rather than guessing at one.
enum PlankShadowStyle {
  /// A genuinely blurred drop shadow (Shadow.blurRadius, not a solid
  /// offset copy) — soft and close, the least "designed" of the set.
  soft,

  /// A crisp, unblurred offset duplicate — the letters read like they're
  /// sitting slightly proud of the wood, a flat "pop-up" look.
  hardOffset,

  /// A soft, low-offset glow in a warm light color radiating evenly
  /// outward instead of falling to one side — halo rather than shadow.
  glow,

  /// Several progressively-fading hard copies stepping out in one
  /// direction — a stretched "long shadow" / retro poster-lettering
  /// look.
  longCast,

  /// No shadow at all — just the gradient fill (and outline, if any)
  /// straight on the wood.
  none,
}

TextStyle _plankFontStyle(PlankFont font, {required double fontSize, required double letterSpacing}) {
  switch (font) {
    case PlankFont.fredoka:
      return GoogleFonts.fredoka(fontSize: fontSize, fontWeight: FontWeight.w600, letterSpacing: letterSpacing);
    case PlankFont.baloo2:
      return GoogleFonts.baloo2(fontSize: fontSize, fontWeight: FontWeight.w700, letterSpacing: letterSpacing);
    case PlankFont.titanOne:
      return GoogleFonts.titanOne(fontSize: fontSize * 0.9, letterSpacing: letterSpacing);
    case PlankFont.luckiestGuy:
      return GoogleFonts.luckiestGuy(fontSize: fontSize * 0.9, letterSpacing: letterSpacing);
    case PlankFont.bangers:
      return GoogleFonts.bangers(fontSize: fontSize * 1.05, letterSpacing: letterSpacing + 0.5);
  }
}

/// Every lowercase 'i' keeps its stem but swaps the dot for a cherry —
/// the same "a themed picture standing in for a letter" trick the real
/// wordmark logo uses for its own O (an 'o'/'O' swap that used to live
/// here too, dropped per feedback that it read as too busy — 'o' is now
/// just a normal glyph like every other letter). Applied per-character
/// (see _GlyphCell) rather than as a whole string so the image can sit
/// inline without disturbing the shadow/outline/fill text underneath
/// everything else.
const _cherryAsset = 'assets/images/ingredient_cherry.png';

class ColorfulPlankText extends StatelessWidget {
  final String text;
  final double fontSize;
  final PlankTextVariant variant;
  final PlankFont font;
  final double letterSpacing;

  /// Null keeps each variant's own default outline choice; pass an
  /// explicit value (including no outline at all) to override it — see
  /// [PlankShadowStyle] for the other half of "no outline, trial
  /// shadows instead".
  final bool showOutline;
  final PlankShadowStyle shadowStyle;

  const ColorfulPlankText({
    super.key,
    required this.text,
    required this.fontSize,
    required this.variant,
    this.font = PlankFont.fredoka,
    this.letterSpacing = 0.3,
    this.showOutline = true,
    this.shadowStyle = PlankShadowStyle.soft,
  });

  @override
  Widget build(BuildContext context) {
    final base = _plankFontStyle(font, fontSize: fontSize, letterSpacing: letterSpacing);
    switch (variant) {
      case PlankTextVariant.sunsetGradient:
        return _GlyphRow(
          text: text,
          style: base,
          fontSize: fontSize,
          colors: const [AppColors.sunsetGold, AppColors.sunsetOrange, AppColors.coral],
          outline: showOutline ? const Color(0xFF4A2410) : null,
          shadowStyle: shadowStyle,
        );
      case PlankTextVariant.oceanGradient:
        return _GlyphRow(
          text: text,
          style: base,
          fontSize: fontSize,
          colors: const [Color(0xFFCDEFFB), Color(0xFF4FA8D8), Color(0xFF1C6FA5)],
          outline: showOutline ? Colors.white : null,
          shadowStyle: shadowStyle,
        );
      case PlankTextVariant.coralPop:
        return _GlyphRow(
          text: text,
          style: base,
          fontSize: fontSize,
          colors: const [AppColors.coral],
          outline: showOutline ? Colors.white : null,
          shadowStyle: shadowStyle,
        );
      case PlankTextVariant.logoGradient:
        return _GlyphRow(
          text: text,
          style: base,
          fontSize: fontSize,
          colors: const [],
          wordSplit: true,
          // A faint blue rather than the usual dark outline — barely
          // there, just enough to separate the letters from the wood.
          outline: showOutline ? const Color(0x554FA8D8) : null,
          shadowStyle: shadowStyle,
        );
      case PlankTextVariant.creamOutline:
        return _GlyphRow(
          text: text,
          style: base,
          fontSize: fontSize,
          colors: const [AppColors.textLight],
          outline: showOutline ? const Color(0xFF1C6FA5) : null,
          shadowStyle: shadowStyle,
        );
      case PlankTextVariant.plainWhite:
        return _GlyphRow(
          text: text,
          style: base,
          fontSize: fontSize,
          // AppColors.textLight — a warm off-white, ever so slightly
          // duller than pure white so numbers don't glare against the
          // wood the way flat #FFFFFF did.
          colors: const [AppColors.textLight],
          outline: showOutline ? const Color(0x554FA8D8) : null,
          shadowStyle: shadowStyle,
        );
    }
  }
}

/// Representative solid color for [variant] — used to tint the icon next
/// to a plank label so it doesn't clash with a fully gradient/outlined
/// text style sitting right beside it.
Color plankAccentColor(PlankTextVariant variant) {
  switch (variant) {
    case PlankTextVariant.sunsetGradient:
      return AppColors.sunsetOrange;
    case PlankTextVariant.oceanGradient:
      return const Color(0xFF2E86C1);
    case PlankTextVariant.coralPop:
      return AppColors.coral;
    case PlankTextVariant.logoGradient:
      return const Color(0xFF3E9FD1);
    case PlankTextVariant.creamOutline:
      return const Color(0xFF1C6FA5);
    case PlankTextVariant.plainWhite:
      return AppColors.textLight;
  }
}

/// Renders [text] one character at a time in a Row — 'o'/'O' and the
/// dot of 'i' are swapped for real ingredient art; every other letter
/// gets its own shadow+outline+fill. Per-character (rather than one
/// gradient ShaderMask over the whole string) is what makes it possible
/// to drop real images inline without the images themselves getting
/// tinted by a gradient mask meant only for the text. [outline] is
/// nullable — no stroke layer is built at all when it's null.
///
/// Two fill modes: the plain one samples [colors] smoothly left-to-right
/// across the whole string; [wordSplit] instead mirrors the logo's own
/// two-tone wordmark — first word (or first half, for a single-word
/// label) gets a light-to-dark-blue top-to-bottom per-letter gradient,
/// second word/half a yellow-to-red top-to-bottom per-letter gradient —
/// both halves shaded the same direction the real wordmark's own letters
/// are, just with different color pairs.
class _GlyphRow extends StatelessWidget {
  final String text;
  final TextStyle style;
  final double fontSize;
  final List<Color> colors;
  final Color? outline;
  final PlankShadowStyle shadowStyle;
  final bool wordSplit;

  const _GlyphRow({
    required this.text,
    required this.style,
    required this.fontSize,
    required this.colors,
    this.outline,
    required this.shadowStyle,
    this.wordSplit = false,
  });

  // Sampled directly from mixoloco_logo.png's own "MIX" lettering
  // (brightest/darkest blue pixels in the actual art) so this text
  // treatment genuinely matches the wordmark rather than approximating it.
  static const _lightBlue = Color(0xFF91D4F2);
  static const _darkBlue = Color(0xFF114465);
  // A brighter, purer yellow up top and a deeper red down low than
  // before — more distance between the two ends per feedback that the
  // fade should read as more dramatic.
  static const _yellow = Color(0xFFFFEB0A);
  static const _red = Color(0xFFB71C1C);

  Color _sample(double t) {
    if (colors.length == 1) return colors.first;
    final scaled = t.clamp(0.0, 1.0) * (colors.length - 1);
    final i = scaled.floor().clamp(0, colors.length - 2);
    return Color.lerp(colors[i], colors[i + 1], scaled - i)!;
  }

  @override
  Widget build(BuildContext context) {
    final chars = text.split('');
    final n = chars.length;
    final strokeWidth = fontSize * (shadowStyle == PlankShadowStyle.hardOffset ? 0.11 : 0.1);
    if (wordSplit) {
      // Split right after the first space (a 2-word label); a
      // single-word label has no space to split on, so it's halved
      // instead — the same proportional "first chunk / second chunk"
      // split the MIX/LOCO wordmark itself has. Both halves use the same
      // top-to-bottom per-letter gradient technique, just with a
      // different color pair, mirroring how the real wordmark shades
      // every one of its own letters top-to-bottom rather than sweeping
      // a color change left-to-right across a word.
      final spaceIndex = chars.indexOf(' ');
      final splitAt = spaceIndex != -1 ? spaceIndex + 1 : (n / 2).ceil();
      // Each word/half is its own Row (so the per-letter gradient within
      // it is unaffected), and the two Rows sit in a Wrap rather than a
      // single flat Row of every letter — some translations (Spanish
      // especially: "Mejores Puntuaciones" for "Best Scores") run wider
      // than the English original the caller sized this for, and a
      // plain Row just overflows past its bounds instead of doing
      // anything about it. Wrap drops the second word/half to its own
      // line automatically once the two don't both fit, *provided* the
      // caller actually constrains this widget's width (an unbounded
      // Row(mainAxisSize: min) never triggers a wrap — see call sites
      // using Expanded/Flexible for that reason).
      Widget wordChunk(int start, int end, List<Color> gradient) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [for (var i = start; i < end; i++) _glyphCell(chars[i], strokeWidth: strokeWidth, verticalGradient: gradient)],
      );
      return Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: fontSize * 0.06,
        children: [wordChunk(0, splitAt, const [_lightBlue, _darkBlue]), wordChunk(splitAt, n, const [_yellow, _red])],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < n; i++) _glyphCell(chars[i], strokeWidth: strokeWidth, fillColor: _sample(n <= 1 ? 0 : i / (n - 1))),
      ],
    );
  }

  /// The behind-the-fill layer(s) for one glyph — see [PlankShadowStyle].
  /// A real Shadow.blurRadius (not a translated duplicate) is what makes
  /// [PlankShadowStyle.soft]/[glow] genuinely soft rather than just a
  /// crisp offset copy, so those two apply their shadows straight on
  /// the fill Text's style rather than as a separate widget.
  List<Widget> _shadowLayers(String display) {
    switch (shadowStyle) {
      case PlankShadowStyle.none:
        return const [];
      case PlankShadowStyle.hardOffset:
        return [
          Transform.translate(
            offset: Offset(fontSize * 0.08, fontSize * 0.11),
            child: Text(display, style: style.copyWith(color: const Color(0xFF2A1508))),
          ),
        ];
      case PlankShadowStyle.longCast:
        return [
          for (var step = 5; step >= 1; step--)
            Transform.translate(
              offset: Offset(fontSize * 0.045 * step, fontSize * 0.06 * step),
              child: Text(display, style: style.copyWith(color: Color(0xFF2A1508).withValues(alpha: 0.16 + 0.05 * (5 - step)))),
            ),
        ];
      case PlankShadowStyle.soft:
      case PlankShadowStyle.glow:
        // Handled inline on the fill layer's own TextStyle.shadows —
        // nothing extra to stack behind it.
        return const [];
    }
  }

  TextStyle _fillStyle(Color fillColor) {
    switch (shadowStyle) {
      case PlankShadowStyle.soft:
        return style.copyWith(
          color: fillColor,
          shadows: [Shadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: fontSize * 0.1, offset: Offset(fontSize * 0.03, fontSize * 0.05))],
        );
      case PlankShadowStyle.glow:
        return style.copyWith(
          color: fillColor,
          shadows: [
            Shadow(color: AppColors.sunsetGold.withValues(alpha: 0.85), blurRadius: fontSize * 0.12),
            Shadow(color: Colors.white.withValues(alpha: 0.55), blurRadius: fontSize * 0.28),
          ],
        );
      case PlankShadowStyle.hardOffset:
      case PlankShadowStyle.longCast:
      case PlankShadowStyle.none:
        return style.copyWith(color: fillColor);
    }
  }

  /// [fillColor] is used as-is when set; otherwise [verticalGradient]
  /// (a top color, bottom color pair) is painted as a per-letter
  /// ShaderMask scoped to just this one glyph, so every letter in that
  /// half of the label gets its own identical top-to-bottom gradient
  /// rather than one gradient smeared across all of them.
  Widget _glyphCell(String ch, {required double strokeWidth, List<Color>? verticalGradient, Color? fillColor}) {
    final isDotlessI = ch == 'i';
    final display = isDotlessI ? 'ı' : ch;
    final outlineColor = outline;
    final fill = fillColor != null
        ? Text(display, style: _fillStyle(fillColor))
        : ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) =>
                LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: verticalGradient!).createShader(bounds),
            child: Text(display, style: style.copyWith(color: Colors.white)),
          );
    final stem = Stack(
      clipBehavior: Clip.none,
      children: [
        ..._shadowLayers(display),
        if (outlineColor != null)
          Text(
            display,
            style: style.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = strokeWidth
                ..strokeJoin = StrokeJoin.round
                ..color = outlineColor,
            ),
          ),
        fill,
      ],
    );
    if (!isDotlessI) return stem;
    // A Column (cherry stacked directly above the dotless stem) instead
    // of a Positioned/negative-offset overlay — a guessed pixel offset
    // against Text's own ascent metrics put the cherry floating a full
    // plank-row away from the actual letter; stacking in normal layout
    // flow can't drift like that regardless of fontSize.
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset(_cherryAsset, width: fontSize * 0.26, height: fontSize * 0.26, fit: BoxFit.contain),
        SizedBox(height: fontSize * 0.03),
        stem,
      ],
    );
  }
}
