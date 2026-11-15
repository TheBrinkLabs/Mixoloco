import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/widgets/glass_visual.dart';
import '../../../core/widgets/submenu_kit.dart';
import '../../../data/models/ingredient.dart' show Ingredient, evolutionChainForLevel;
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
  Map<int, HighScoreDetail> _details = const {};

  @override
  void initState() {
    super.initState();
    Future.wait([loadHighScores(), loadHighScoreDetails()]).then((r) {
      if (mounted) {
        setState(() {
          _scores = r[0] as List<int>;
          _details = r[1] as Map<int, HighScoreDetail>;
        });
      }
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
            ...[
              _MyBestHeaderRow(locale: locale),
              InsetList(rows: [for (final (i, score) in scores.indexed) _ScoreRow(rank: i + 1, score: score, detail: _details[score], locale: locale)]),
            ],
        ],
      ),
    );
  }
}

/// The ingredient [d]'s best tier was on its level's chain.
Ingredient _evolution(HighScoreDetail d) {
  final chain = evolutionChainForLevel(d.level);
  return chain[d.tier.clamp(0, chain.length - 1)];
}

/// Column widths shared by [_MyBestHeaderRow] and [_ScoreRow].
const _kRankWidth = 28.0;
const _kEvoWidth = 40.0;
const _kLevelWidth = 40.0;

/// Column labels over the list — same wording as the Global board's.
class _MyBestHeaderRow extends StatelessWidget {
  final AppLocale locale;
  const _MyBestHeaderRow({required this.locale});

  static const _style = TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: SubmenuColors.textSecondary);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Row(
        children: [
          const SizedBox(width: _kRankWidth, child: Text('#', style: _style, textAlign: TextAlign.center)),
          const SizedBox(width: 12),
          SizedBox(width: _kEvoWidth, child: Text(tr(locale, 'league_col_evo'), style: _style, textAlign: TextAlign.center)),
          SizedBox(width: _kLevelWidth, child: Text(tr(locale, 'league_col_level'), style: _style, textAlign: TextAlign.center)),
          Expanded(child: Text(tr(locale, 'score_label').toUpperCase(), style: _style, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  final int rank;
  final int score;

  /// The level the run ended on and its best evolution — null for a
  /// score saved before build 28 or restored from an older backup, which
  /// only carries the number (shown as a dash).
  final HighScoreDetail? detail;
  final AppLocale locale;
  const _ScoreRow({required this.rank, required this.score, required this.detail, required this.locale});

  static const _dash = Text('–', style: TextStyle(fontFamily: 'Lilita One', fontSize: 16, color: SubmenuColors.textDisabled));

  @override
  Widget build(BuildContext context) {
    final d = detail;
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Container(
            width: _kRankWidth,
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
          SizedBox(
            width: _kEvoWidth,
            child: Center(child: d == null ? _dash : GlassVisual(ingredient: _evolution(d), size: 32, applyDisplayScale: false)),
          ),
          SizedBox(
            width: _kLevelWidth,
            child: Center(
              child: d == null ? _dash : Text('${d.level}', style: const TextStyle(fontFamily: 'Lilita One', fontSize: 16, color: Colors.white)),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('$score', maxLines: 1, style: const TextStyle(fontFamily: 'Lilita One', fontSize: 18, color: SubmenuColors.gold)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
