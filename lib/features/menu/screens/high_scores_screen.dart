import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/widgets/submenu_kit.dart';
import '../../../data/services/high_scores_service.dart';

/// The "My Best" tab of RankingsScreen (design_handoff_main_menu_v3) — the
/// top locally-saved scores, read fresh from disk each time this tab
/// mounts. No own Scaffold/BarBackdrop/back button/title plank — those
/// are RankingsScreen's job now, shared with the Global tab, since this
/// used to be its own standalone pushed screen (HighScoresScreen) before
/// the v3 merge.
class MyBestRankingsTab extends ConsumerStatefulWidget {
  const MyBestRankingsTab({super.key});

  @override
  ConsumerState<MyBestRankingsTab> createState() => _MyBestRankingsTabState();
}

class _MyBestRankingsTabState extends ConsumerState<MyBestRankingsTab> {
  List<int>? _scores;

  @override
  void initState() {
    super.initState();
    loadHighScores().then((scores) {
      if (mounted) setState(() => _scores = scores);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scores = _scores;
    final locale = ref.watch(localeProvider);

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (scores == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: SubmenuColors.textSecondary),
              ),
            )
          else if (scores.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                tr(locale, 'no_scores_yet'),
                style: submenuNunito(size: 14, weight: FontWeight.w800, color: SubmenuColors.textSecondary),
              ),
            )
          else
            InsetList(rows: [for (final (i, score) in scores.indexed) _ScoreRow(rank: i + 1, score: score, locale: locale)]),
        ],
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  final int rank;
  final int score;
  final AppLocale locale;
  const _ScoreRow({required this.rank, required this.score, required this.locale});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: SubmenuColors.goldEdge, width: 2),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [SubmenuColors.goldTop, SubmenuColors.goldBottom],
              ),
            ),
            child: Text('$rank', style: const TextStyle(fontFamily: 'Lilita One', fontSize: 13, color: Colors.white)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tr(locale, 'score_label'),
              style: const TextStyle(fontFamily: 'Lilita One', fontSize: 16, color: Colors.white),
            ),
          ),
          Text('$score', style: const TextStyle(fontFamily: 'Lilita One', fontSize: 18, color: SubmenuColors.gold)),
        ],
      ),
    );
  }
}
