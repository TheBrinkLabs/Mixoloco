import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/outlined_label.dart';
import 'bar_backdrop.dart';

// Re-exported so screen files only need one import for both this kit
// and the outlined-text widget it's built on.
export '../theme/outlined_label.dart';

/// Shared design tokens for the sub-menu redesign
/// (design_handoff_submenus/README.md) — Guide, Settings, Ingredients,
/// Cocktails, Cocktail detail, Songs. A few values happen to match
/// hud_kit.dart's own HudColors (both trace back to the same gold-rim/
/// navy family), but this screen family has enough of its own tokens
/// (the inset list, the card gradient, the paper recipe card, locked/
/// secondary text) that it gets its own complete token set rather than
/// cross-referencing HudColors and risking a transcription mismatch.
abstract class SubmenuColors {
  static const gold = Color(0xFFFFC94A);
  static const goldTop = Color(0xFFFFD95E);
  static const goldBottom = Color(0xFFF39A12);
  static const goldEdge = Color(0xFF7A3A00);

  static const panelTop = Color(0xFF1F5385);
  static const panelBottom = Color(0xFF143A5E);
  static const inset = Color(0xFF0E2C4A);
  static const ring = Color(0xFF0B2238);
  static const cardTop = Color(0xFF3480BD);
  static const cardBottom = Color(0xFF1F5385);
  static const plateTop = Color(0xFF2B6AA0);
  static const plateBottom = Color(0xFF163A5F);

  static const textSecondary = Color(0xFFA9CDEB);
  static const textDisabled = Color(0xFF5F86AB);
  static const lockedCard = Color(0xFF0E2C4A);
  static const lockedCardBorder = Color(0xFF23476B);

  static const green = Color(0xFF56C83A);
  static const greenBright = Color(0xFF8FE35A);
  static const greenEdge = Color(0xFF155A17);
  static const toggleOffTrack = Color(0xFF3A4F63);
  static const toggleOffBorder = Color(0xFF1F2E3C);

  static const red = Color(0xFFE8332F);
  static const redEdge = Color(0xFF7A1010);
  static const resetBorder = Color(0xFFFF6B5E);
  static const resetText = Color(0xFFFF8A7E);

  static const paperTop = Color(0xFFFBF5E6);
  static const paperBottom = Color(0xFFEFE4C8);
  static const paperBorder = Color(0xFFC9B48A);
  static const paperInk = Color(0xFF3B2A1A);
  static const paperNumber = Color(0xFFC4651A);
  static const paperLabel = Color(0xFF9A6A2A);

  static const dotReached = Color(0xFF8FB6DA);
}

TextStyle submenuNunito({required double size, required FontWeight weight, required Color color, double? height}) =>
    GoogleFonts.nunito(fontSize: size, fontWeight: weight, color: color, height: height);

/// The redesign's own full-screen tone wash — distinct from the main
/// menu's own `_ToneGradient` (different stops/colours per
/// design_handoff_submenus/README.md's "Background layers").
class SubmenuToneGradient extends StatelessWidget {
  const SubmenuToneGradient({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.0, 0.18, 0.70, 1.0],
          colors: [Color(0x8C0E2846), Color(0x000E2846), Color(0x0028141E), Color(0x6628141E)],
        ),
      ),
    );
  }
}

/// The 46×46 gold-rimmed round back button, top-left on every sub-menu
/// screen — replaces [PlankBackButton] on this screen family.
class SubmenuBackButton extends StatefulWidget {
  final VoidCallback onTap;

  /// Defaults to the back chevron; the How to Play guide uses a close (×)
  /// since on first launch there's nothing to go "back" to.
  final IconData icon;
  const SubmenuBackButton({super.key, required this.onTap, this.icon = Icons.chevron_left_rounded});

  @override
  State<SubmenuBackButton> createState() => _SubmenuBackButtonState();
}

class _SubmenuBackButtonState extends State<SubmenuBackButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: SubmenuColors.ring, width: 2),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF2B6AA0), Color(0xFF163A5F)],
            ),
            boxShadow: [BoxShadow(color: SubmenuColors.ring, offset: const Offset(0, 4))],
          ),
          child: Center(
            child: Icon(widget.icon, color: Colors.white, size: widget.icon == Icons.chevron_left_rounded ? 30 : 26),
          ),
        ),
      ),
    );
  }
}

/// The gold ribbon title overlapping the panel's top edge.
class RibbonTitle extends StatelessWidget {
  final String text;
  const RibbonTitle({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(30, 6, 30, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SubmenuColors.goldEdge, width: 3),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [SubmenuColors.goldTop, SubmenuColors.goldBottom],
        ),
        boxShadow: [
          BoxShadow(color: SubmenuColors.goldEdge, offset: const Offset(0, 4)),
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), offset: const Offset(0, 8), blurRadius: 14),
        ],
      ),
      child: OutlinedLabel(
        text: text.toUpperCase(),
        fontSize: 30,
        fill: Colors.white,
        stroke: SubmenuColors.goldEdge,
        strokeWidth: 5,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// The navy gold-rimmed panel every sub-menu screen's content sits on.
class SubmenuPanel extends StatelessWidget {
  final Widget child;
  const SubmenuPanel({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: SubmenuColors.ring, width: 2),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 46, 14, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: SubmenuColors.gold, width: 3),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [SubmenuColors.panelTop, SubmenuColors.panelBottom],
          ),
          boxShadow: [
            BoxShadow(color: SubmenuColors.ring, offset: const Offset(0, 8)),
            BoxShadow(color: Colors.black.withValues(alpha: 0.4), offset: const Offset(0, 18), blurRadius: 30),
          ],
        ),
        child: child,
      ),
    );
  }
}

/// The shared screen shell: backdrop + tone wash + back button + ribbon
/// title + panel. [panelTop]/[ribbonTop] default to the standard values;
/// Cocktail detail passes its own (the hero sits above the panel there).
/// [panelBottom] is set for the screens whose content scrolls inside a
/// fixed-height panel (Ingredients/Cocktails/Songs/Detail) — anchoring
/// both the panel's top and bottom gives it a tight height, which is
/// what lets a `LevelPager`'s `Expanded(PageView(...))` inside it work.
/// Left null for Settings/Guide, which just grow to fit their content
/// (only `top` is anchored, so the panel sizes to its child).
class SubmenuScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  final double panelTop;
  final double ribbonTop;
  final double? panelBottom;
  final List<Widget> aboveRibbon;

  /// Which scene photo sits behind the panel — the beach bar by default,
  /// same as [BarBackdrop] itself. Screens whose content is paged per
  /// level (Ingredients/Cocktails/Songs, via [LevelPager]) pass the
  /// current page's own level through here so the backdrop tracks which
  /// level's content is showing, not just which level the player's
  /// lifetime progress has reached.
  final String backgroundAssetPath;

  /// An "After Dark" level's evening grade on that photo — see
  /// [BarBackdrop.night].
  final bool night;

  /// False on the first-launch name screen, which is the app's root.
  final bool showBack;
  const SubmenuScaffold({
    super.key,
    required this.title,
    required this.child,
    this.panelTop = 146,
    this.ribbonTop = 122,
    this.panelBottom,
    this.aboveRibbon = const [],
    this.backgroundAssetPath = 'assets/images/beach_background.webp',
    this.night = false,
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context) {
    // Added to the back button's own top offset (not the panel/ribbon,
    // which already sit well clear of any status bar) since it's the
    // one element close enough to the top edge to risk sitting under it.
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      body: BarBackdrop(
        showTable: false,
        backgroundAssetPath: backgroundAssetPath,
        night: night,
        child: Stack(
          children: [
            const Positioned.fill(child: SubmenuToneGradient()),
            Positioned(
              left: 20,
              top: 10 + topInset,
              child: showBack ? SubmenuBackButton(onTap: () => Navigator.of(context).pop()) : const SizedBox.shrink(),
            ),
            ...aboveRibbon,
            Positioned(
              left: 16,
              right: 16,
              top: panelTop,
              bottom: panelBottom,
              child: SubmenuPanel(child: child),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: ribbonTop,
              child: Center(child: RibbonTitle(text: title)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The small gold circular arrow button — used by [LevelPager]'s header
/// and reused as-is (just a bigger [size]) by Cocktail detail's hero
/// prev/next arrows.
class GoldArrowButton extends StatefulWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final double size;
  const GoldArrowButton({super.key, required this.icon, required this.enabled, required this.onTap, this.size = 40});

  @override
  State<GoldArrowButton> createState() => _GoldArrowButtonState();
}

class _GoldArrowButtonState extends State<GoldArrowButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: widget.enabled ? 1.0 : 0.35,
      child: GestureDetector(
        onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: widget.enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: widget.enabled ? (_) => setState(() => _pressed = false) : null,
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: SubmenuColors.goldEdge, width: 2),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [SubmenuColors.goldTop, SubmenuColors.goldBottom],
              ),
              boxShadow: [BoxShadow(color: SubmenuColors.goldEdge, offset: const Offset(0, 3))],
            ),
            child: Icon(widget.icon, color: Colors.white, size: widget.size * 0.65),
          ),
        ),
      ),
    );
  }
}

/// The level-swipe header (arrows + "LEVEL n OF total" + name + dots)
/// wrapping a [PageView] of per-level content — shared by Ingredients/
/// Cocktails/Songs. Always used inside a [SubmenuScaffold] with
/// `panelBottom` set, so the `Expanded(PageView(...))` below has the
/// bounded height it needs. A page the player hasn't reached yet shows
/// [LockedLevelPage] instead of calling [pageBuilder].
class LevelPager extends StatefulWidget {
  final int itemCount;
  final int initialPage;
  final String Function(int index) levelName;
  final bool Function(int index) levelReached;
  final String lockedNoun;
  final Widget Function(BuildContext context, int index) pageBuilder;

  /// Fired on every page change (swipe or arrow tap), including the
  /// initial build — lets the host screen keep its own backdrop (see
  /// [SubmenuScaffold.backgroundAssetPath]) in sync with whichever
  /// level's page is actually showing.
  final void Function(int index)? onPageChanged;
  const LevelPager({
    super.key,
    required this.itemCount,
    required this.initialPage,
    required this.levelName,
    required this.levelReached,
    required this.lockedNoun,
    required this.pageBuilder,
    this.onPageChanged,
  });

  @override
  State<LevelPager> createState() => _LevelPagerState();
}

class _LevelPagerState extends State<LevelPager> {
  late final PageController _controller = PageController(initialPage: widget.initialPage);
  late int _page = widget.initialPage;

  void _goTo(int page) {
    _controller.animateToPage(page, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            GoldArrowButton(icon: Icons.chevron_left_rounded, enabled: _page > 0, onTap: () => _goTo(_page - 1)),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'LEVEL ${_page + 1} OF ${widget.itemCount}',
                    style: const TextStyle(fontFamily: 'Lilita One', fontSize: 11, letterSpacing: 1.3, color: SubmenuColors.gold),
                  ),
                  const SizedBox(height: 2),
                  OutlinedLabel(
                    text: widget.levelName(_page).toUpperCase(),
                    fontSize: 22,
                    fill: Colors.white,
                    stroke: SubmenuColors.ring,
                    strokeWidth: 4,
                  ),
                ],
              ),
            ),
            GoldArrowButton(
              icon: Icons.chevron_right_rounded,
              enabled: _page < widget.itemCount - 1,
              onTap: () => _goTo(_page + 1),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.itemCount; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: i == _page ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: i == _page
                      ? SubmenuColors.gold
                      : (widget.levelReached(i) ? SubmenuColors.dotReached : SubmenuColors.ring),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.itemCount,
            onPageChanged: (i) {
              setState(() => _page = i);
              widget.onPageChanged?.call(i);
            },
            itemBuilder: (context, i) => widget.levelReached(i)
                ? widget.pageBuilder(context, i)
                : LockedLevelPage(levelName: widget.levelName(i), noun: widget.lockedNoun),
          ),
        ),
      ],
    );
  }
}

/// Shown by [LevelPager] in place of a level's real content when the
/// player hasn't reached it yet.
class LockedLevelPage extends StatelessWidget {
  final String levelName;
  final String noun;
  const LockedLevelPage({super.key, required this.levelName, required this.noun});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: SubmenuColors.goldEdge, width: 3),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [SubmenuColors.goldTop, SubmenuColors.goldBottom],
              ),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), offset: const Offset(0, 5))],
            ),
            child: const Icon(Icons.lock_rounded, color: SubmenuColors.goldEdge, size: 34),
          ),
          const SizedBox(height: 12),
          const OutlinedLabel(text: 'LOCKED', fontSize: 24, fill: Colors.white, stroke: SubmenuColors.ring, strokeWidth: 4),
          const SizedBox(height: 12),
          Text(
            'Reach $levelName to unlock its $noun.',
            textAlign: TextAlign.center,
            style: submenuNunito(size: 14, weight: FontWeight.w800, color: SubmenuColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// The "Collected 13 / 13" space-between row under a [LevelPager].
class CountRow extends StatelessWidget {
  final String label;
  final String value;
  const CountRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: submenuNunito(size: 13, weight: FontWeight.w900, color: SubmenuColors.textSecondary)),
          Text(value, style: submenuNunito(size: 13, weight: FontWeight.w900, color: SubmenuColors.gold)),
        ],
      ),
    );
  }
}

/// A group label above an [InsetList] — used by Settings/Shop/Rankings.
class GroupHeader extends StatelessWidget {
  final String text;
  const GroupHeader({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontFamily: 'Lilita One',
          fontSize: 12,
          letterSpacing: 1.4,
          color: SubmenuColors.gold,
        ),
      ),
    );
  }
}

/// The inset (`#0E2C4A`) rounded list a group's rows sit in, with a
/// hairline divider between each one — used by Settings/Shop/Rankings.
class InsetList extends StatelessWidget {
  final List<Widget> rows;
  const InsetList({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: SubmenuColors.inset,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), offset: const Offset(0, 2), blurRadius: 4)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// The 32px gold-on-navy circle every inset row's leading icon sits in.
class IconBadge extends StatelessWidget {
  final IconData icon;
  const IconBadge({super.key, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: SubmenuColors.gold, width: 2),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [SubmenuColors.plateTop, SubmenuColors.plateBottom],
        ),
      ),
      child: Icon(icon, color: SubmenuColors.gold, size: 18),
    );
  }
}

/// An [InsetList] row's shared shell — icon badge, label, trailing
/// content. Height grows to fit [trailing] when [minHeight] isn't tall
/// enough for it (e.g. Shop's two-line price rows).
class SubmenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget trailing;
  final VoidCallback? onTap;
  final double minHeight;
  final double labelFontSize;
  const SubmenuRow({
    super.key,
    required this.icon,
    required this.label,
    required this.trailing,
    this.onTap,
    this.minHeight = 50,
    this.labelFontSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    final row = Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconBadge(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Lilita One', fontSize: labelFontSize, color: Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
    if (onTap == null) return row;
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: row);
  }
}

/// The small pill a row's "current value" shows in (Settings'
/// Language/Nickname, Shop's fallback price while a store query is in
/// flight).
class SubmenuValuePill extends StatelessWidget {
  final String text;
  final IconData icon;
  const SubmenuValuePill({super.key, required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFF1A4670),
        border: Border.all(color: const Color(0xFF2F72AA), width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: const TextStyle(fontFamily: 'Lilita One', fontSize: 13, color: Colors.white)),
          const SizedBox(width: 4),
          Icon(icon, color: SubmenuColors.gold, size: 10),
        ],
      ),
    );
  }
}

/// A small solid gold action button — Shop's Buy/Watch-Ad rows.
class SubmenuGoldButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  const SubmenuGoldButton({super.key, required this.label, required this.onTap, this.loading = false});

  @override
  State<SubmenuGoldButton> createState() => _SubmenuGoldButtonState();
}

class _SubmenuGoldButtonState extends State<SubmenuGoldButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: SubmenuColors.goldEdge, width: 2),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [SubmenuColors.goldTop, SubmenuColors.goldBottom],
              ),
              boxShadow: [BoxShadow(color: SubmenuColors.goldEdge, offset: const Offset(0, 3))],
            ),
            child: widget.loading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: SubmenuColors.goldEdge))
                : Text(widget.label, style: const TextStyle(fontFamily: 'Lilita One', fontSize: 13, color: SubmenuColors.goldEdge)),
          ),
        ),
      ),
    );
  }
}

/// The shared "locked item" treatment — a 45%-black silhouette of
/// [sprite] with a small gold lock badge centred over it, used by the
/// Ingredients/Cocktails card grids and the Songs row's locked state.
Widget lockedSilhouette(Widget sprite, {double lockSize = 26}) {
  return Stack(
    alignment: Alignment.center,
    children: [
      ColorFiltered(
        colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.45), BlendMode.srcATop),
        child: sprite,
      ),
      Container(
        width: lockSize,
        height: lockSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [SubmenuColors.goldTop, SubmenuColors.goldBottom],
          ),
          border: Border.all(color: SubmenuColors.goldEdge, width: 1.5),
        ),
        child: Icon(Icons.lock_rounded, color: SubmenuColors.goldEdge, size: lockSize * 0.55),
      ),
    ],
  );
}
