import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A real stone/ceramic notification panel — assets/images/
/// Notification_tablet.png — replacing the old flat AppColors.surface
/// rounded box every confirm/choice popup in the app used, per feedback
/// that flat color read as "a plain black notification bar," out of
/// place next to every other wood/stone surface in the game.
///
/// Nine-slice stretched (see [_centerSlice]) rather than a plain
/// BoxFit.fill — the source art's own rounded corners/raised rim were
/// originally ~130px in a 1286x502 file, which would stretch into huge,
/// mushy corners on a dialog only a few hundred logical pixels across if
/// scaled uniformly. The asset itself is pre-downscaled to 178x70 (one
/// Write, not computed at runtime) so its corner reads as a deliberate
/// ~18 logical px at native size — in the same ballpark as every other
/// rounded-rect surface in the app — while [_centerSlice]'s flat middle
/// still stretches to fit whatever width/height the dialog's content
/// needs.
///
/// [padding] is deliberately bigger than the plain box it replaced —
/// big enough to clear the rim entirely (the ~18px corner above, given
/// real breathing room) so text/buttons never sit on top of it.
class NotificationTablet extends StatelessWidget {
  final Widget child;
  final double? width;
  final EdgeInsetsGeometry padding;
  const NotificationTablet({
    super.key,
    required this.child,
    this.width,
    this.padding = const EdgeInsets.symmetric(horizontal: 32, vertical: 30),
  });

  static const _centerSlice = Rect.fromLTRB(18, 18, 160, 52);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: padding,
      decoration: const BoxDecoration(
        image: DecorationImage(image: AssetImage('assets/images/Notification_tablet.png'), centerSlice: _centerSlice, fit: BoxFit.fill),
      ),
      child: child,
    );
  }
}

/// A real stone/ceramic button — assets/images/button.png, same
/// nine-slice/pre-downscale reasoning as [NotificationTablet] (was a
/// ~175px native corner in an 852x639 file, same problem a plain
/// BoxFit.fill had on any button much wider than it is tall, which every
/// one of these is — now pre-downscaled to 78x58, an ~16 logical px
/// corner at native size, matching the app's existing
/// BorderRadius.circular(14-16) buttons rather than a smeared oval).
/// [selected] draws a gold ring on top (for [_LevelPickerDialog]'s own
/// highlighted-level-row use, the only place more than one of these
/// appears at once needing one picked out from the rest) — the plain
/// stone art has no selected/unselected variant of its own.
class StoneButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;
  final double? width;
  final double height;
  final bool selected;
  const StoneButton({super.key, required this.onTap, required this.child, this.width = double.infinity, this.height = 46, this.selected = false});

  static const _centerSlice = Rect.fromLTRB(15, 17, 63, 41);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          image: const DecorationImage(image: AssetImage('assets/images/button.png'), centerSlice: _centerSlice, fit: BoxFit.fill),
          borderRadius: selected ? BorderRadius.circular(14) : null,
          border: selected ? Border.all(color: AppColors.sunsetOrange, width: 2.5) : null,
        ),
        child: Center(child: child),
      ),
    );
  }
}
