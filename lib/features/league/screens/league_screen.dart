import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/banner_ad_widget.dart';
import '../../../core/widgets/league_tier_badge.dart';
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

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: const Text('Leaderboard', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textLight)),
      ),
      body: SafeArea(
        child: state.loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.sunsetOrange))
            : state.error == 'not_signed_in'
            ? _buildConnecting()
            : RefreshIndicator(
                color: AppColors.sunsetOrange,
                onRefresh: () => ref.read(leagueControllerProvider.notifier).refresh(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    if (!_resultBannerDismissed && state.lastWeekResultIsNew && state.lastWeekResult != null)
                      _WeekResultBanner(result: state.lastWeekResult!, onDismiss: () => setState(() => _resultBannerDismissed = true)),
                    _buildHeader(state),
                    const SizedBox(height: 16),
                    if (state.pendingJoin)
                      _buildPendingJoin()
                    else if (state.leaderboard.isEmpty)
                      _buildEmpty()
                    else
                      ...state.leaderboard.asMap().entries.map((e) => _LeaderboardRow(
                        rank: e.key + 1,
                        entry: e.value,
                        isMe: e.value.uid == state.uid,
                      )),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildConnecting() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          "Couldn't connect to the league yet — check your connection and reopen this screen.",
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildHeader(LeagueState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          LeagueTierBadge(tier: state.tier, fontSize: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              state.nickname ?? 'You',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textLight),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('THIS WEEK', style: TextStyle(fontSize: 9, letterSpacing: 1.2, color: AppColors.textMuted)),
              Text('${state.myWeeklyBestScore}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.sunsetGold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPendingJoin() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: const Column(
        children: [
          Text('⏳', style: TextStyle(fontSize: 32)),
          SizedBox(height: 12),
          Text(
            "You're queued for Bronze — check back within a day to see your room.",
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Center(child: Text('No one in your room yet.', style: TextStyle(color: AppColors.textMuted))),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final int rank;
  final LeagueLeaderboardEntry entry;
  final bool isMe;
  const _LeaderboardRow({required this.rank, required this.entry, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isMe ? AppColors.sunsetOrange.withValues(alpha: 0.16) : AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: isMe ? Border.all(color: AppColors.sunsetOrange, width: 1.2) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('$rank', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textMuted)),
          ),
          Expanded(
            child: Text(
              entry.nickname,
              style: TextStyle(fontSize: 14, fontWeight: isMe ? FontWeight.w800 : FontWeight.w600, color: AppColors.textLight),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text('${entry.score}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.sunsetGold)),
        ],
      ),
    );
  }
}

class _WeekResultBanner extends StatelessWidget {
  final Map<String, dynamic> result;
  final VoidCallback onDismiss;
  const _WeekResultBanner({required this.result, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final outcome = (result['outcome'] as String?) ?? 'stayed';
    final tier = (result['tier'] as String?) ?? 'bronze';
    final credits = (result['creditsAwarded'] as int?) ?? 0;
    final isWinner = (result['isWinner'] as bool?) ?? false;

    final String headline = isWinner
        ? "You won your room!"
        : outcome == 'promoted'
        ? "Promoted!"
        : outcome == 'relegated'
        ? "Relegated"
        : "Week complete";

    final String emoji = isWinner ? '🏆' : outcome == 'promoted' ? '⬆️' : outcome == 'relegated' ? '⬇️' : '📊';

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
                Text(
                  credits > 0 ? '${labelForTier(tier)} · +$credits credits' : labelForTier(tier),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black87),
                ),
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
