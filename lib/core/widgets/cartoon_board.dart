import 'package:flutter/material.dart';

/// cartoon_board.png, cropped tight to its own opaque content (zero
/// margin, same convention menu_board_3.png/menu_board_white.png's own
/// doc comments establish) — a flat illustrated plank replacing the
/// photographic white board on the home menu's option tiles. [child]
/// (icon/label content) paints on top, same as every other board
/// widget in the app.
class CartoonBoard extends StatelessWidget {
  final double width;
  final double height;
  final Widget? child;
  const CartoonBoard({super.key, required this.width, required this.height, this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/cartoon_board.png', fit: BoxFit.fill),
          ?child,
        ],
      ),
    );
  }
}
