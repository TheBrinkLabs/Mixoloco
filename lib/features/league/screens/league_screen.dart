import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/widgets/banner_ad_widget.dart';
import '../../../core/widgets/glass_visual.dart';
import '../../../core/widgets/submenu_kit.dart';
import '../../../data/repositories/league_repository.dart';
import '../providers/league_provider.dart';
import '../widgets/week_result_dialog.dart';

/// The "Global" tab of RankingsScreen (design_handoff_main_menu_v3) — the
/// 10 highest scores worldwide this week (the week resets every Monday,
/// 00:00 UTC), and a one-time pop-up ([WeekResultDialog]) when this player finished in last
/// week's top 10 (their place + the credits it paid — see rollover.js).
/// Reads entirely from Firestore via [leagueControllerProvider]. No own
/// Scaffold/BarBackdrop/back button —
/// those are RankingsScreen's job now, shared with the My Best tab,
/// since this used to be its own standalone pushed screen (LeagueScreen)
/// before the v3 merge.
class GlobalRankingsTab extends ConsumerStatefulWidget {
  const GlobalRankingsTab({super.key});

  @override
  ConsumerState<GlobalRankingsTab> createState() => _GlobalRankingsTabState();
}

class _GlobalRankingsTabState extends ConsumerState<GlobalRankingsTab> {
  bool _resultShown = false;

  @override
  void initState() {
    super.initState();
    // Same reasoning as NicknameSetupScreen — the persistent bottom
    // banner otherwise sits on top of the leaderboard's last row.
    ref.read(bannerPositionProvider.notifier).state = BannerPosition.hidden;
    Future.microtask(() => ref.read(leagueControllerProvider.notifier).refresh());
  }

  @override
  void dispose() {
    ref.read(bannerPositionProvider.notifier).state = BannerPosition.bottom;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(leagueControllerProvider);
    final locale = ref.watch(localeProvider);
    final screenSize = MediaQuery.sizeOf(context);
    final rowWidth = screenSize.width - 32;

    // Last week's top-10 finish: pop the result up once, the moment it loads.
    ref.listen(leagueControllerProvider, (_, next) {
      final result = next.lastWeekResult;
      if (_resultShown || !next.lastWeekResultIsNew || result == null) return;
      _resultShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) WeekResultDialog.show(context, result, locale);
      });
    });

    return state.loading
        ? const Center(child: CircularProgressIndicator(color: SubmenuColors.gold))
        : state.error == 'not_signed_in'
        ? _buildConnecting(locale)
        : RefreshIndicator(
            color: SubmenuColors.gold,
            backgroundColor: SubmenuColors.panelBottom,
            onRefresh: () => ref.read(leagueControllerProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _buildHeader(locale),
                const SizedBox(height: 6),
                if (state.leaderboard.isEmpty)
                  _buildEmpty(locale)
                else ...[
                  _LeaderboardHeaderRow(width: rowWidth, locale: locale),
                  ...state.leaderboard.asMap().entries.map((e) => _LeaderboardRow(
                    rank: e.key + 1,
                    entry: e.value,
                    isMe: e.value.uid == state.uid,
                    width: rowWidth,
                  )),
                ],
              ],
            ),
          );
  }

  Widget _buildConnecting(AppLocale locale) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          tr(locale, 'league_connecting_error'),
          textAlign: TextAlign.center,
          style: submenuNunito(size: 14, weight: FontWeight.w800, color: SubmenuColors.textSecondary),
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocale locale) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: [
          Text(
            tr(locale, 'league_top10_title'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'Lilita One', fontSize: 22, color: SubmenuColors.gold),
          ),
          const SizedBox(height: 2),
          Text(
            tr(locale, 'league_top10_subtitle'),
            textAlign: TextAlign.center,
            style: submenuNunito(size: 12, weight: FontWeight.w800, color: SubmenuColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(AppLocale locale) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Text(
          tr(locale, 'league_top10_empty'),
          textAlign: TextAlign.center,
          style: submenuNunito(size: 13, weight: FontWeight.w800, color: SubmenuColors.textSecondary),
        ),
      ),
    );
  }
}

/// Wide enough for a 7-digit score at full size (it used to be 76, which
/// wrapped 1,000,000+); 8+ digits drop to a slightly smaller font.
const _kScoreColumnWidth = 86.0;

/// Column labels for [_LeaderboardRow] — plain text, not wood-plank
/// styled, since it's a thin one-off header rather than a real board.
class _LeaderboardHeaderRow extends StatelessWidget {
  final double width;
  final AppLocale locale;
  const _LeaderboardHeaderRow({required this.width, required this.locale});

  static const _labelStyle = TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: SubmenuColors.textSecondary);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
      child: SizedBox(
        width: width - 28,
        child: Row(
          children: [
            const SizedBox(width: 22, child: Text('#', style: _labelStyle)),
            Expanded(child: Text(tr(locale, 'league_col_name'), style: _labelStyle)),
            SizedBox(width: 30, child: Text(tr(locale, 'league_col_evo'), style: _labelStyle, textAlign: TextAlign.center)),
            SizedBox(width: 26, child: Text(tr(locale, 'league_col_level'), style: _labelStyle, textAlign: TextAlign.center)),
            SizedBox(width: _kScoreColumnWidth, child: Text(tr(locale, 'score_label').toUpperCase(), style: _labelStyle, textAlign: TextAlign.right)),
          ],
        ),
      ),
    );
  }
}

/// One player's row — a [BlueTile] at half [kMenuBoard3Aspect]'s usual
/// height and a smaller font throughout, per feedback that the full-size
/// board/font this used before left no room for the two new columns
/// (Evolution/Level) alongside Position/Name/Score. Plain white
/// OutlinedLabels (score gets a gold fill instead, to keep standing out)
/// rather than a heavier decorative treatment — five columns of real
/// data packed this tight needs to read cleanly over looking decorative,
/// same reasoning high_scores_screen.dart's own rank/score row already
/// uses.
class _LeaderboardRow extends StatelessWidget {
  final int rank;
  final LeagueLeaderboardEntry entry;
  final bool isMe;
  final double width;
  const _LeaderboardRow({required this.rank, required this.entry, required this.isMe, required this.width});

  @override
  Widget build(BuildContext context) {
    const height = 44.0;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      height: height,
      padding: EdgeInsets.symmetric(horizontal: width * 0.04),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: SubmenuColors.inset,
        border: Border.all(color: isMe ? SubmenuColors.gold : Colors.transparent, width: 2),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text('$rank', style: const TextStyle(fontFamily: 'Lilita One', fontSize: 15, color: Colors.white)),
          ),
          Expanded(
            child: Text(
              entry.nickname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'Lilita One', fontSize: 14, color: Colors.white),
            ),
          ),
          SizedBox(width: 30, child: Center(child: GlassVisual(ingredient: entry.evolutionIngredient, size: 28, applyDisplayScale: false))),
          SizedBox(
            width: 26,
            child: Center(
              child: Text('${entry.level}', style: const TextStyle(fontFamily: 'Lilita One', fontSize: 14, color: Colors.white)),
            ),
          ),
          SizedBox(
            width: _kScoreColumnWidth,
            child: Align(
              alignment: Alignment.centerRight,
              // One line always: 8+ digits step the font down a little, and
              // anything wider still shrinks to fit rather than wrapping.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  '${entry.score}',
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontFamily: 'Lilita One', fontSize: '${entry.score}'.length >= 8 ? 13 : 15, color: SubmenuColors.gold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
