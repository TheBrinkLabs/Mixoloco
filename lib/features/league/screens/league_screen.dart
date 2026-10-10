import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colorful_plank_text.dart';
import '../../../core/widgets/bar_backdrop.dart';
import '../../../core/widgets/banner_ad_widget.dart';
import '../../../core/widgets/glass_visual.dart';
import '../../../core/widgets/league_tier_badge.dart';
import '../../../core/widgets/wood_plank.dart';
import '../../../data/repositories/league_repository.dart';
import '../providers/league_provider.dart';

/// The weekly leaderboard — this player's room (once the daily/weekly
/// rollover has placed them in one), everyone in it ranked by this
/// week's best score, and a one-time banner for last week's result
/// (promoted/relegated/stayed + any credits it paid out — see
/// rollover.js). Reads entirely from Firestore via [leagueControllerProvider];
/// tier/room placement itself is never decided here, only displayed —
/// see tools/league-rollover for where that actually happens.
class LeagueScreen extends ConsumerStatefulWidget {
  const LeagueScreen({super.key});

  @override
  ConsumerState<LeagueScreen> createState() => _LeagueScreenState();
}

class _LeagueScreenState extends ConsumerState<LeagueScreen> {
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

    return Scaffold(
      body: BarBackdrop(
        showTable: false,
        showHeaderBoard: false,
        child: Stack(
          children: [
            SafeArea(
              child: state.loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.sunsetOrange))
                  : state.error == 'not_signed_in'
                  ? _buildConnecting(locale)
                  : RefreshIndicator(
                      color: AppColors.sunsetOrange,
                      onRefresh: () => ref.read(leagueControllerProvider.notifier).refresh(),
                      child: ListView(
                        // No more title plank above the tier plaque (see
                        // _buildHeader) — it reads as its own header now,
                        // so this just needs enough clearance to sit
                        // clear of the back button, not a full title's
                        // worth of top padding.
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
                    ),
            ),
            // Painted last — see info_screen.dart's matching comment.
            Positioned(left: 12, top: 10, child: PlankBackButton(onTap: () => Navigator.of(context).pop())),
          ],
        ),
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
          style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
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
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          const Text('⏳', style: TextStyle(fontSize: 32)),
          const SizedBox(height: 12),
          Text(
            tr(locale, 'league_pending_join'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(AppLocale locale) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(child: Text(tr(locale, 'league_empty_room'), style: const TextStyle(color: AppColors.textMuted))),
    );
  }
}

/// Column labels for [_LeaderboardRow] — plain text, not wood-plank
/// styled, since it's a thin one-off header rather than a real board.
class _LeaderboardHeaderRow extends StatelessWidget {
  final double width;
  final AppLocale locale;
  const _LeaderboardHeaderRow({required this.width, required this.locale});

  static const _labelStyle = TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.textMuted);

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
            SizedBox(width: 56, child: Text(tr(locale, 'score_label').toUpperCase(), style: _labelStyle, textAlign: TextAlign.right)),
          ],
        ),
      ),
    );
  }
}

/// One player's row — a wood_plank board like every other list in the
/// app, but at half [kMenuBoard3Aspect]'s usual height and a smaller
/// font throughout, per feedback that the full-size board/font this
/// used before left no room for the two new columns (Evolution/Level)
/// alongside Position/Name/Score. Plain white text (not the heavy
/// gradient ColorfulPlankText treatment every other board uses) — five
/// columns of real data packed this tight needs to read cleanly over
/// looking decorative, same reasoning high_scores_screen.dart's own
/// rank/score row already used.
class _LeaderboardRow extends StatelessWidget {
  final int rank;
  final LeagueLeaderboardEntry entry;
  final bool isMe;
  final double width;
  const _LeaderboardRow({required this.rank, required this.entry, required this.isMe, required this.width});

  @override
  Widget build(BuildContext context) {
    final height = (width / kMenuBoard3Aspect) / 2;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: isMe ? BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.sunsetOrange, width: 1.6)) : null,
      child: WoodPlank(
        width: width,
        height: height,
        assetPath: 'assets/images/menu_board_3.png',
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: width * 0.04),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: ColorfulPlankText(text: '$rank', fontSize: height * 0.34, variant: PlankTextVariant.plainWhite, font: kPlankTextFont, shadowStyle: kPlankShadowStyle),
              ),
              Expanded(
                child: ColorfulPlankText(
                  text: entry.nickname,
                  fontSize: height * 0.3,
                  variant: PlankTextVariant.plainWhite,
                  font: kPlankTextFont,
                  shadowStyle: kPlankShadowStyle,
                ),
              ),
              SizedBox(width: 30, child: Center(child: GlassVisual(ingredient: entry.evolutionIngredient, size: height * 0.68, applyDisplayScale: false))),
              SizedBox(
                width: 26,
                child: Center(
                  child: ColorfulPlankText(text: '${entry.level}', fontSize: height * 0.3, variant: PlankTextVariant.plainWhite, font: kPlankTextFont, shadowStyle: kPlankShadowStyle),
                ),
              ),
              SizedBox(
                width: 56,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ColorfulPlankText(
                    text: '${entry.score}',
                    fontSize: height * 0.32,
                    variant: PlankTextVariant.sunsetGradient,
                    font: kPlankTextFont,
                    shadowStyle: kPlankShadowStyle,
                  ),
                ),
              ),
            ],
          ),
        ),
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
      decoration: BoxDecoration(gradient: AppColors.gradientSunset, borderRadius: BorderRadius.circular(16)),
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
