import 'dart:io';
import 'package:image/image.dart' as img;

// One-off measurement tool: scans assets/images/bar_table.png row by row to
// find the opaque (alpha>0) horizontal extent at each row, so we can see
// exactly where the tabletop's wood-grain trapezoid ends and the front
// apron face begins, and what the true far/near width ratio is.
void main() {
  final bytes = File('assets/images/bar_table.png').readAsBytesSync();
  final image = img.decodePng(bytes)!;
  final w = image.width, h = image.height;
  print('image size: ${w}x$h');

  int? firstOpaqueRow;
  int? lastOpaqueRow;
  final widths = <int, ({int left, int right, int width})>{};

  for (var y = 0; y < h; y++) {
    int? left;
    int? right;
    for (var x = 0; x < w; x++) {
      final a = image.getPixel(x, y).a;
      if (a > 10) {
        left ??= x;
        right = x;
      }
    }
    if (left != null && right != null) {
      firstOpaqueRow ??= y;
      lastOpaqueRow = y;
      widths[y] = (left: left, right: right, width: right - left + 1);
    }
  }

  print('firstOpaqueRow=$firstOpaqueRow (frac=${firstOpaqueRow! / h})');
  print('lastOpaqueRow=$lastOpaqueRow (frac=${lastOpaqueRow! / h})');

  // Print width at every 2% of the opaque span so we can see the taper
  // shape and find where it stops widening (near edge of the tabletop
  // surface, before the front apron face).
  final span = lastOpaqueRow - firstOpaqueRow;
  for (var pct = 0; pct <= 100; pct += 2) {
    final y = firstOpaqueRow + (span * pct / 100).round();
    final rec = widths[y];
    if (rec == null) continue;
    print(
      'pct=$pct% y=$y yFrac=${(y / h).toStringAsFixed(4)} '
      'left=${rec.left} right=${rec.right} width=${rec.width} '
      'widthFrac=${(rec.width / w).toStringAsFixed(4)} '
      'centerFrac=${((rec.left + rec.right) / 2 / w).toStringAsFixed(4)}',
    );
  }
}
