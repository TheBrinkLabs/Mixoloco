import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/widgets/submenu_kit.dart';
import '../../menu/screens/high_scores_screen.dart';
import '../../onboarding/screens/nickname_setup_screen.dart';
import '../providers/league_provider.dart';
import 'league_screen.dart';

enum RankingsTab { myBest, global }

/// Replaces the old separate Best-Scores/Leaderboard destinations
/// (design_handoff_main_menu_v3) with one screen, two tabs — "My Best"
/// (local scores, see [MyBestRankingsTab]) and "Global" (the weekly
/// leaderboard, see [GlobalRankingsTab]). Always opens on My Best by
/// default (no account needed for that tab); switching to Global is
/// where the existing one-time-nickname gate kicks in, same flow
/// MenuScreen's old `_openLeaderboard` used, just moved here.
class RankingsScreen extends ConsumerStatefulWidget {
  final RankingsTab initialTab;
  const RankingsScreen({super.key, this.initialTab = RankingsTab.myBest});

  @override
  ConsumerState<RankingsScreen> createState() => _RankingsScreenState();
}

class _RankingsScreenState extends ConsumerState<RankingsScreen> {
  late RankingsTab _tab = widget.initialTab;

  // IndexedStack below keeps every child it's ever given permanently
  // mounted (that's the whole point — tab switches don't lose scroll
  // position/state), which means GlobalRankingsTab's own initState
  // (hiding the ad banner, firing a Firestore refresh) would otherwise
  // run the instant this screen opens even if the player stays on My
  // Best the entire time. Only ever giving IndexedStack the real
  // GlobalRankingsTab once the player has actually selected that tab —
  // a cheap placeholder before that — keeps those side effects tied to
  // genuinely opening the tab, not just opening this screen.
  late bool _globalTabEverSelected = widget.initialTab == RankingsTab.global;

  Future<void> _selectGlobalTab() async {
    final hasNickname = await ref.read(leagueControllerProvider.notifier).hasNickname();
    if (!mounted) return;
    if (!hasNickname) {
      // Same lazy one-time gate MenuScreen's old `_openLeaderboard` used —
      // NicknameSetupScreen's own success path pushReplaces itself with a
      // fresh RankingsScreen(initialTab: global) rather than popping back
      // here, so this tab just stays on My Best underneath it.
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NicknameSetupScreen()));
      return;
    }
    setState(() {
      _tab = RankingsTab.global;
      _globalTabEverSelected = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);

    return SubmenuScaffold(
      title: tr(locale, 'rankings'),
      panelBottom: 72,
      child: Column(
        children: [
          _RankingsTabBar(
            tab: _tab,
            locale: locale,
            onSelectMyBest: () => setState(() => _tab = RankingsTab.myBest),
            onSelectGlobal: _selectGlobalTab,
          ),
          const SizedBox(height: 10),
          Expanded(
            child: IndexedStack(
              index: _tab.index,
              children: [
                const MyBestRankingsTab(),
                if (_globalTabEverSelected) const GlobalRankingsTab() else const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Two-segment selector styled per design_handoff_main_menu_v3's
/// Rankings spec: "a navy gradient, a #0B2238 border, and the active tab
/// filled with the gold ribbon gradient" — the same HUD-pill look
/// [hud_kit.dart] already shares between the menu and gameplay HUDs.
class _RankingsTabBar extends StatelessWidget {
  final RankingsTab tab;
  final AppLocale locale;
  final VoidCallback onSelectMyBest;
  final VoidCallback onSelectGlobal;
  const _RankingsTabBar({
    required this.tab,
    required this.locale,
    required this.onSelectMyBest,
    required this.onSelectGlobal,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: SubmenuColors.ring, width: 2),
        color: SubmenuColors.inset,
      ),
      child: Row(
        children: [
          Expanded(
            child: _RankingsTabSegment(
              label: tr(locale, 'my_best').toUpperCase(),
              active: tab == RankingsTab.myBest,
              onTap: onSelectMyBest,
            ),
          ),
          Expanded(
            child: _RankingsTabSegment(
              label: tr(locale, 'global').toUpperCase(),
              active: tab == RankingsTab.global,
              onTap: onSelectGlobal,
            ),
          ),
        ],
      ),
    );
  }
}

class _RankingsTabSegment extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _RankingsTabSegment({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: active ? Border.all(color: SubmenuColors.goldEdge, width: 2) : null,
          gradient: active
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [SubmenuColors.goldTop, SubmenuColors.goldBottom],
                )
              : null,
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: OutlinedLabel(
              text: label,
              fontSize: 14,
              fill: Colors.white,
              stroke: active ? SubmenuColors.goldEdge : SubmenuColors.ring,
              strokeWidth: 2.5,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ),
    );
  }
}
