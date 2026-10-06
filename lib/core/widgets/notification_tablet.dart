import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A real stone/ceramic notification panel — assets/images/
/// Notification_tablet.png, stretched to fill whatever rectangle its
/// content naturally sizes to (BoxFit.fill, not contain/cover — the
/// image's own rounded-rect shape and edge highlight read fine stretched
/// non-uniformly, and a consistent *method* of fitting across every
/// dialog matters more than preserving its exact native aspect in each
/// one, which varies with how much text/how many buttons that dialog
/// has). Replaces the old flat AppColors.surface rounded box every
/// confirm/choice popup in the app used — per feedback that flat color
/// read as "a plain black notification bar," out of place next to every
/// other wood/stone surface in the game. The image's own baked-in rim
/// already reads as a border, so there's no separate Border.all layered
/// on top the way the old box had one.
class NotificationTablet extends StatelessWidget {
  final Widget child;
  final double? width;
  final EdgeInsetsGeometry padding;
  const NotificationTablet({
    super.key,
    required this.child,
    this.width,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: padding,
      decoration: const BoxDecoration(image: DecorationImage(image: AssetImage('assets/images/Notification_tablet.png'), fit: BoxFit.fill)),
      child: child,
    );
  }
}

/// A real stone/ceramic button — assets/images/button.png, same
/// BoxFit.fill stretch reasoning as [NotificationTablet] — replacing the
/// old flat AppColors.gradientSunset pill every dialog's primary action
/// used. [selected] draws a gold ring on top (for [_LevelPickerDialog]'s
/// own highlighted-level-row use, the only place more than one of these
/// appears at once needing one picked out from the rest) — the plain
/// stone art has no selected/unselected variant of its own.
class StoneButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;
  final double? width;
  final double height;
  final bool selected;
  const StoneButton({super.key, required this.onTap, required this.child, this.width = double.infinity, this.height = 46, this.selected = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          image: const DecorationImage(image: AssetImage('assets/images/button.png'), fit: BoxFit.fill),
          borderRadius: selected ? BorderRadius.circular(14) : null,
          border: selected ? Border.all(color: AppColors.sunsetOrange, width: 2.5) : null,
        ),
        child: Center(child: child),
      ),
    );
  }
}
