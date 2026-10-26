import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/widgets/banner_ad_widget.dart';
import '../../../core/widgets/glass_visual.dart';
import '../../../core/widgets/league_tier_badge.dart';
import '../../../core/widgets/submenu_kit.dart';
import '../../../data/repositories/league_repository.dart';
import '../providers/league_provider.dart';

/// The "Global" tab of RankingsScreen (design_handoff_main_menu_v3) — this
/// player's room (once the daily/weekly rollover has placed them in
/// one), everyone in it ranked by this week's best score, and a one-time
/// banner for last week's result (promoted/relegated/stayed + any
/// credits it paid out — see rollover.js). Reads entirely from Firestore
/// via [leagueControllerProvider]; tier/room placement itself is never
/// decided here, only displayed — see tools/league-rollover for where
/// that actually happens. No own Scaffold/BarBackdrop/back button —
/// those are RankingsScreen's job now, shared with the My Best tab,
/// since this used to be its own standalone pushed screen (LeagueScreen)
/// before the v3 merge.
class GlobalRankingsTab extends ConsumerStatefulWidget {
  const GlobalRankingsTab({super.key});

  @override
  ConsumerState<GlobalRankingsTab> createState() => _GlobalRankingsTabState();
}

class _GlobalRankingsTabState extends ConsumerState<GlobalRankingsTab> {
  bool _resultBannerDismissed = false;

  @override
  void initState() {
    super.initState();
    // Same reasoning as NicknameSetupScreen — the persistent bottom
    // banner otherwise sits on top of the leaderboard's last row/the
    // result banner's dismiss button.
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
                if (!_resultBannerDismissed && state.lastWeekResultIsNew && state.lastWeekResult != null)
                  _WeekResultBanner(
                    result: state.lastWeekResult!,
                    locale: locale,
                    onDismiss: () => setState(() => _resultBannerDismissed = true),
                  ),
                _buildHeader(state, rowWidth, locale),
                const SizedBox(height: 6),
                if (state.pendingJoin)
                  _buildPendingJoin(locale)
                else if (state.leaderboard.isEmpty)
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

  Widget _buildHeader(LeagueState state, double width, AppLocale locale) {
    // Just the tier plate, full width — nickname/score are already
    // visible in this player's own row further down, so repeating them
    // here was redundant.
    return LeagueTierBadge(tier: state.tier, locale: locale, width: width);
  }

  Widget _buildPendingJoin(AppLocale locale) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: SubmenuColors.inset, borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          const Text('⏳', style: TextStyle(fontSize: 32)),
          const SizedBox(height: 12),
          Text(
            tr(locale, 'league_pending_join'),
            textAlign: TextAlign.center,
            style: submenuNunito(size: 13, weight: FontWeight.w800, color: SubmenuColors.textSecondary),
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
          tr(locale, 'league_empty_room'),
          style: submenuNunito(size: 13, weight: FontWeight.w800, color: SubmenuColors.textSecondary),
        ),
      ),
    );
  }
}

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
            SizedBox(width: 76, child: Text(tr(locale, 'score_label').toUpperCase(), style: _labelStyle, textAlign: TextAlign.right)),
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
            // Widened from 56 — scores can reach 7 digits (the security
            // rules cap bestScore at 5,000,000) and this was only ever
            // comfortably fitting 5 before clipping/overlapping its
            // neighbor.
            width: 76,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('${entry.score}', style: const TextStyle(fontFamily: 'Lilita One', fontSize: 15, color: SubmenuColors.gold)),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekResultBanner extends StatelessWidget {
  final Map<String, dynamic> result;
  final AppLocale locale;
  final VoidCallback onDismiss;
  const _WeekResultBanner({required this.result, required this.locale, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final outcome = (result['outcome'] as String?) ?? 'stayed';
    final tier = (result['tier'] as String?) ?? 'bronze';
    final credits = (result['creditsAwarded'] as int?) ?? 0;
    final isWinner = (result['isWinner'] as bool?) ?? false;

    final String headline = isWinner
        ? tr(locale, 'league_result_won')
        : outcome == 'promoted'
        ? tr(locale, 'league_result_promoted')
        : outcome == 'relegated'
        ? tr(locale, 'league_result_relegated')
        : tr(locale, 'league_result_week_complete');

    final String emoji = isWinner ? '🏆' : outcome == 'promoted' ? '⬆️' : outcome == 'relegated' ? '⬇️' : '📊';
    final tierLabel = labelForTier(tier, locale);
    final subtitle = credits > 0 ? '$tierLabel · ${tr(locale, 'league_credits_earned').replaceFirst('{n}', '$credits')}' : tierLabel;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SubmenuColors.goldEdge, width: 2),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [SubmenuColors.goldTop, SubmenuColors.goldBottom],
        ),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 30)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(headline, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black87)),
              ],
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Icons.close_rounded, color: Colors.black54, size: 20),
          ),
        ],
      ),
    );
  }
}
