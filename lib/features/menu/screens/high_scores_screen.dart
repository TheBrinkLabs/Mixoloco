import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colorful_plank_text.dart';
import '../../../core/widgets/bar_backdrop.dart';
import '../../../core/widgets/wood_plank.dart';
import '../../../data/services/high_scores_service.dart';

/// The top locally-saved scores, read fresh from disk each time this
/// screen opens — there's no live provider for this since it only ever
/// changes between games, never while this screen itself is showing.
class HighScoresScreen extends ConsumerStatefulWidget {
  const HighScoresScreen({super.key});

  @override
  ConsumerState<HighScoresScreen> createState() => _HighScoresScreenState();
}

class _HighScoresScreenState extends ConsumerState<HighScoresScreen> {
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
    final screenSize = MediaQuery.sizeOf(context);
    const sideMargin = 28.0;
    final plankWidth = screenSize.width - sideMargin * 2;
    final plankHeight = plankWidth / kMenuBoard3Aspect;

    return Scaffold(
      body: BarBackdrop(
        showTable: false,
        showHeaderBoard: false,
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    WoodTitlePlank(
                      title: tr(locale, 'best_scores'),
                      icon: Icons.emoji_events_rounded,
                      width: plankWidth,
                      height: plankHeight,
                      assetPath: 'assets/images/menu_board_3.png',
                      iconAsset: 'assets/images/best_scores.png',
                    ),
                    const SizedBox(height: 14),
                    if (scores == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.textMuted),
                        ),
                      )
                    else if (scores.isEmpty)
                      WoodPlank(
                        width: plankWidth,
                        height: plankHeight,
                        assetPath: 'assets/images/menu_board_3.png',
                        child: Center(
                          child: ColorfulPlankText(
                            text: tr(locale, 'no_scores_yet'),
                            fontSize: plankHeight * 0.2,
                            variant: kPlankTextVariant,
                            font: kPlankTextFont,
                            shadowStyle: kPlankShadowStyle,
                          ),
                        ),
                      )
                    else
                      // Thinner boards, flush together — same layout as
                      // the Leaderboard's own rows, per feedback.
                      for (final (i, score) in scores.indexed) _ScoreRow(rank: i + 1, score: score, width: plankWidth, height: plankHeight / 2),
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
}

/// Half [kMenuBoard3Aspect]'s usual height and a bigger relative font
/// than that height would otherwise suggest — [height] comes in already
/// halved, so these multipliers are calibrated against that, same as
/// league_screen.dart's own half-height row.
class _ScoreRow extends StatelessWidget {
  final int rank;
  final int score;
  final double width;
  final double height;
  const _ScoreRow({required this.rank, required this.score, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      child: WoodPlank(
        width: width,
        height: height,
        assetPath: 'assets/images/menu_board_3.png',
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: width * 0.09),
          child: Row(
            children: [
              ColorfulPlankText(
                text: '#$rank',
                fontSize: height * 0.4,
                variant: PlankTextVariant.plainWhite,
                font: kPlankTextFont,
                shadowStyle: kPlankShadowStyle,
              ),
              const Spacer(),
              ColorfulPlankText(
                text: '$score',
                fontSize: height * 0.46,
                variant: PlankTextVariant.plainWhite,
                font: kPlankTextFont,
                shadowStyle: kPlankShadowStyle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
