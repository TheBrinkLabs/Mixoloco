import 'package:flutter/material.dart';

// A self-contained gold/navy token set, same reasoning as hud_kit.dart's
// and submenu_kit.dart's own: every popup in the app reaches for this
// file, so it stays decoupled from the sub-menu screens' own
// SubmenuColors rather than importing that (menu-screen-specific) file
// into every dialog call site.
const _gold = Color(0xFFFFC94A);
const _goldTop = Color(0xFFFFD95E);
const _goldBottom = Color(0xFFF39A12);
const _goldEdge = Color(0xFF7A3A00);
const _panelTop = Color(0xFF1F5385);
const _panelBottom = Color(0xFF143A5E);
const _ring = Color(0xFF0B2238);

/// Every confirm/choice popup in the app's shared container — a
/// gold-rimmed navy panel, matching the sub-menu redesign's own
/// SubmenuPanel look (design_handoff_submenus) rather than the earlier
/// light-stone-tablet art it replaced. Nested like SubmenuPanel for the
/// same double-ring effect (an outer 2px navy ring around an inner 3px
/// gold border) since a single Container can only paint one border.
class NotificationTablet extends StatelessWidget {
  final Widget child;
  final double? width;
  final EdgeInsetsGeometry padding;
  const NotificationTablet({
    super.key,
    required this.child,
    this.width,
    this.padding = const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _ring, width: 2),
      ),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _gold, width: 3),
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_panelTop, _panelBottom]),
          boxShadow: [
            BoxShadow(color: _ring, offset: const Offset(0, 8)),
            BoxShadow(color: Colors.black.withValues(alpha: 0.4), offset: const Offset(0, 18), blurRadius: 30),
          ],
        ),
        child: child,
      ),
    );
  }
}

/// Every popup's own button — a solid gold-gradient pill, matching
/// [NotificationTablet]'s gold rim and the sub-menu redesign's own
/// GoldArrowButton/SubmenuGoldButton family, replacing the earlier
/// stone-button art. [child] text stays dark (see app_theme.dart's
/// AppColors.textOnStone doc) since this surface is still light gold
/// even though the tablet behind it is now navy. [selected] draws a
/// bright ring on top (for [_LevelPickerDialog]'s own highlighted-level
/// row use, the only place more than one of these appears at once
/// needing one picked out from the rest).
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
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? Colors.white : _goldEdge, width: selected ? 3 : 2),
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_goldTop, _goldBottom]),
          boxShadow: [BoxShadow(color: _goldEdge, offset: const Offset(0, 3))],
        ),
        child: Center(child: child),
      ),
    );
  }
}
