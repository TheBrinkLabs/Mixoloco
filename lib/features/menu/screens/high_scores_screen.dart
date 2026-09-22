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
            Positioned(left: 12, top: 10, child: PlankBackButton(onTap: () => Navigator.of(context).pop())),
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
                    const SizedBox(height: 10),
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
                      for (var i = 0; i < scores.length; i++) ...[
                        _ScoreRow(rank: i + 1, score: scores[i], width: plankWidth, height: plankHeight),
                        if (i < scores.length - 1) const SizedBox(height: 10),
                      ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  final int rank;
  final int score;
  final double width;
  final double height;
  const _ScoreRow({required this.rank, required this.score, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return WoodPlank(
      width: width,
      height: height,
      assetPath: 'assets/images/menu_board_3.png',
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: width * 0.09),
        child: Row(
          children: [
            ColorfulPlankText(
              text: '#$rank',
              fontSize: height * 0.24,
              variant: PlankTextVariant.plainWhite,
              font: kPlankTextFont,
              shadowStyle: kPlankShadowStyle,
            ),
            const Spacer(),
            ColorfulPlankText(
              text: '$score',
              fontSize: height * 0.28,
              variant: PlankTextVariant.plainWhite,
              font: kPlankTextFont,
              shadowStyle: kPlankShadowStyle,
            ),
          ],
        ),
      ),
    );
  }
}
