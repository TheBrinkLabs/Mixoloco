import 'package:flutter/material.dart';

/// Thick outlined "sticker" text in Lilita One, per the main-menu redesign
/// handoff (design_handoff_main_menu/README.md, "Outlined text"): a dark
/// stroke behind a solid fill, built by stacking two [Text] widgets with
/// the same style rather than a single ShaderMask/stroke-only pass — this
/// keeps the fill a flat, crisp color rather than letting the stroke eat
/// into it.
///
/// Unlike [ColorfulPlankText] (the app's existing gradient-fill wood-text
/// style used everywhere else), every call site here wants its own flat
/// fill/stroke color pair and its own stroke width, so those are explicit
/// parameters rather than a fixed enum of variants.
class OutlinedLabel extends StatelessWidget {
  final String text;
  final double fontSize;
  final Color fill;

  /// Null skips the stroke layer entirely — some labels in the handoff
  /// (the HUD pills' "LEVEL"/"UNLOCKED" captions) are plain white with no
  /// outline at all.
  final Color? stroke;
  final double strokeWidth;
  final double letterSpacing;
  final TextAlign textAlign;

  /// An extra solid (not stroked) copy of the text, offset by this much
  /// and filled with [shadowColor], drawn behind the stroke+fill — the
  /// handoff's "PLAY" treatment adds this on top of its own stroke for
  /// extra depth; most labels leave it null.
  final Offset? shadowOffset;
  final Color? shadowColor;

  const OutlinedLabel({
    super.key,
    required this.text,
    required this.fontSize,
    required this.fill,
    this.stroke,
    this.strokeWidth = 0,
    this.letterSpacing = 0,
    this.textAlign = TextAlign.center,
    this.shadowOffset,
    this.shadowColor,
  });

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontFamily: 'Lilita One',
      fontSize: fontSize,
      letterSpacing: letterSpacing,
      height: 1.0,
    );
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        if (shadowOffset != null)
          Transform.translate(
            offset: shadowOffset!,
            child: Text(
              text,
              textAlign: textAlign,
              style: base.copyWith(color: shadowColor ?? stroke),
            ),
          ),
        if (stroke != null)
          Text(
            text,
            textAlign: textAlign,
            style: base.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = strokeWidth
                ..strokeJoin = StrokeJoin.round
                ..color = stroke!,
            ),
          ),
        Text(
          text,
          textAlign: textAlign,
          style: base.copyWith(color: fill),
        ),
      ],
    );
  }
}
