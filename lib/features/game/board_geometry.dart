import 'package:flutter/material.dart';
import '../../core/widgets/bar_backdrop.dart';

/// Screen-space placement of the play area — where the physics world sits
/// on top of the table art. Computed once from the raw screen size and
/// shared by GameScreen (Flutter overlay positioning) and MixolocoGame
/// (Forge2D world sizing), so the two can never drift out of sync and the
/// zero-size/degenerate-size guard only has to live in one place.
class BoardGeometry {
  final bool isValid;
  final double boardMargin;
  final double width;
  final double tableTop;
  final double tableSurfaceNear;

  const BoardGeometry._({
    required this.isValid,
    required this.boardMargin,
    required this.width,
    required this.tableTop,
    required this.tableSurfaceNear,
  });

  static const empty = BoardGeometry._(
    isValid: false,
    boardMargin: 0,
    width: 0,
    tableTop: 0,
    tableSurfaceNear: 0,
  );

  factory BoardGeometry.of(Size screenSize, {bool rooftop = false}) {
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    if (!screenWidth.isFinite || !screenHeight.isFinite || screenWidth <= 0 || screenHeight <= 0) {
      return empty;
    }

    final tableTop = screenHeight * tableTopFraction(screenWidth, screenHeight, rooftop: rooftop);
    // The true near edge of the wood-grain playing surface — well above
    // kTableNearFraction, which reaches past the front apron block to the
    // bottom of the whole table graphic.
    final tableSurfaceNear = screenHeight * tableSurfaceNearFraction(screenWidth, screenHeight, rooftop: rooftop);
    if (tableSurfaceNear <= tableTop) return empty;

    const boardMargin = 16.0;
    final width = screenWidth - boardMargin * 2;
    if (width <= 0) return empty;

    return BoardGeometry._(
      isValid: true,
      boardMargin: boardMargin,
      width: width,
      tableTop: tableTop,
      tableSurfaceNear: tableSurfaceNear,
    );
  }

  double get height => tableSurfaceNear - tableTop;

  /// The rect the Flame GameWidget occupies.
  Rect get playAreaRect => Rect.fromLTWH(boardMargin, tableTop, width, height);
}
